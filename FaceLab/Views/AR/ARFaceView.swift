import SwiftUI
import ARKit
import RealityKit

struct ARFaceView: View {
    @StateObject private var arViewModel = ARFaceViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                ARFaceContainerView(arViewModel: arViewModel)
                    .ignoresSafeArea()

                VStack {
                    Spacer()

                    HStack(spacing: 16) {
                        Button {
                            arViewModel.captureSnapshot()
                        } label: {
                            Image(systemName: "camera.circle.fill")
                                .font(.system(size: 64))
                                .foregroundStyle(.white)
                                .shadow(radius: 4)
                        }
                    }
                    .padding(.bottom, 40)
                }

                if !arViewModel.isFaceDetected {
                    VStack {
                        Text("Position your face in the frame")
                            .font(.headline)
                            .padding()
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        Spacer()
                    }
                    .padding(.top, 100)
                }
            }
            .navigationTitle("Face Scan")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - AR Container (UIViewRepresentable)
struct ARFaceContainerView: UIViewRepresentable {
    @ObservedObject var arViewModel: ARFaceViewModel

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)

        // Configure face tracking
        let config = ARFaceTrackingConfiguration()
        config.maximumNumberOfTrackedFaces = 1
        config.isLightEstimationEnabled = true

        arView.session.delegate = context.coordinator
        arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])

        arViewModel.arView = arView
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}

    func makeCoordinator() -> ARSessionCoordinator {
        ARSessionCoordinator(arViewModel: arViewModel)
    }
}

// MARK: - AR Session Coordinator
class ARSessionCoordinator: NSObject, ARSessionDelegate {
    let arViewModel: ARFaceViewModel

    init(arViewModel: ARFaceViewModel) {
        self.arViewModel = arViewModel
    }

    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        for anchor in anchors {
            guard let faceAnchor = anchor as? ARFaceAnchor else { continue }
            DispatchQueue.main.async {
                self.arViewModel.isFaceDetected = true
                self.arViewModel.addFaceMesh(for: faceAnchor)
            }
        }
    }

    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        for anchor in anchors {
            guard let faceAnchor = anchor as? ARFaceAnchor else { continue }
            DispatchQueue.main.async {
                self.arViewModel.updateFaceMesh(for: faceAnchor)
            }
        }
    }

    func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        for anchor in anchors {
            guard anchor is ARFaceAnchor else { continue }
            DispatchQueue.main.async {
                self.arViewModel.isFaceDetected = false
            }
        }
    }
}

// MARK: - ViewModel
@MainActor
class ARFaceViewModel: ObservableObject {
    @Published var isFaceDetected = false
    @Published var capturedImage: UIImage?

    weak var arView: ARView?
    private var faceEntity: ModelEntity?

    func addFaceMesh(for faceAnchor: ARFaceAnchor) {
        guard let arView else { return }

        // Create face mesh from ARKit geometry
        let faceGeometry = faceAnchor.geometry
        var meshDescriptor = MeshDescriptor(name: "faceMesh")
        meshDescriptor.positions = MeshBuffer(faceGeometry.vertices.map { SIMD3<Float>($0.0, $0.1, $0.2) })
        meshDescriptor.primitives = .triangles(faceGeometry.triangleIndices.map { UInt32($0) })
        meshDescriptor.textureCoordinates = MeshBuffer(faceGeometry.textureCoordinates.map { SIMD2<Float>($0.0, $0.1) })

        guard let meshResource = try? MeshResource.generate(from: [meshDescriptor]) else { return }

        // Semi-transparent skin-tone material (base layer for makeup)
        var material = SimpleMaterial()
        material.color = .init(tint: .clear)
        material.metallic = 0
        material.roughness = 1

        let entity = ModelEntity(mesh: meshResource, materials: [material])
        faceEntity = entity

        let anchorEntity = AnchorEntity(anchor: faceAnchor)
        anchorEntity.addChild(entity)
        arView.scene.addAnchor(anchorEntity)
    }

    func updateFaceMesh(for faceAnchor: ARFaceAnchor) {
        guard let faceEntity else { return }

        let faceGeometry = faceAnchor.geometry
        var meshDescriptor = MeshDescriptor(name: "faceMesh")
        meshDescriptor.positions = MeshBuffer(faceGeometry.vertices.map { SIMD3<Float>($0.0, $0.1, $0.2) })
        meshDescriptor.primitives = .triangles(faceGeometry.triangleIndices.map { UInt32($0) })
        meshDescriptor.textureCoordinates = MeshBuffer(faceGeometry.textureCoordinates.map { SIMD2<Float>($0.0, $0.1) })

        guard let meshResource = try? MeshResource.generate(from: [meshDescriptor]) else { return }
        faceEntity.model?.mesh = meshResource
    }

    func captureSnapshot() {
        guard let arView else { return }
        arView.snapshot(saveToHDR: false) { image in
            DispatchQueue.main.async {
                self.capturedImage = image
            }
        }
    }
}
