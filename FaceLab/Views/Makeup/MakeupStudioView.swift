import SwiftUI
import ARKit
import RealityKit

struct MakeupStudioView: View {
    @StateObject private var viewModel = MakeupStudioViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                // AR Camera with face tracking + makeup overlay
                MakeupARContainerView(viewModel: viewModel)
                    .ignoresSafeArea()

                VStack {
                    Spacer()

                    // Brush opacity slider
                    if viewModel.isEditing {
                        VStack(spacing: 12) {
                            HStack {
                                Text("Opacity")
                                    .font(.caption)
                                    .foregroundStyle(.white)
                                Slider(value: $viewModel.brushSettings.opacity, in: 0.1...1.0)
                                    .tint(.white)
                                Text("\(Int(viewModel.brushSettings.opacity * 100))%")
                                    .font(.caption)
                                    .foregroundStyle(.white)
                                    .frame(width: 40)
                            }

                            HStack {
                                Text("Size")
                                    .font(.caption)
                                    .foregroundStyle(.white)
                                Slider(value: $viewModel.brushSettings.size, in: 0.1...1.0)
                                    .tint(.white)
                                Text("\(Int(viewModel.brushSettings.size * 100))%")
                                    .font(.caption)
                                    .foregroundStyle(.white)
                                    .frame(width: 40)
                            }
                        }
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal)
                    }

                    // Color palette
                    ColorPaletteView(selectedColor: $viewModel.brushSettings.color)
                        .padding(.horizontal)

                    // Brush selector
                    BrushSelectorView(selectedBrush: $viewModel.brushSettings.type)
                        .padding(.bottom, 8)
                }
            }
            .navigationTitle("Makeup Studio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(viewModel.isEditing ? "Done" : "Edit") {
                        viewModel.isEditing.toggle()
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        viewModel.resetMakeup()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                }
            }
        }
    }
}

// MARK: - Color Palette
struct ColorPaletteView: View {
    @Binding var selectedColor: Color

    private let colors: [Color] = [
        .red, .pink, .orange, .brown,
        Color(red: 0.8, green: 0.4, blue: 0.4), // rose
        Color(red: 0.6, green: 0.3, blue: 0.3), // mauve
        Color(red: 0.9, green: 0.7, blue: 0.5), // nude
        Color(red: 0.5, green: 0.2, blue: 0.3), // berry
        Color(red: 0.8, green: 0.6, blue: 0.7), // light pink
        Color(red: 0.4, green: 0.2, blue: 0.2), // dark brown
    ]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(colors.indices, id: \.self) { index in
                    Circle()
                        .fill(colors[index])
                        .frame(width: 36, height: 36)
                        .overlay(
                            Circle()
                                .stroke(.white, lineWidth: selectedColor == colors[index] ? 3 : 0)
                        )
                        .shadow(radius: 2)
                        .onTapGesture {
                            selectedColor = colors[index]
                        }
                }
            }
            .padding(.vertical, 8)
        }
        .padding(.horizontal)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Brush Selector
struct BrushSelectorView: View {
    @Binding var selectedBrush: BrushType

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(BrushType.allCases) { brush in
                    VStack(spacing: 4) {
                        Image(systemName: brush.icon)
                            .font(.title2)
                            .frame(width: 48, height: 48)
                            .background(
                                selectedBrush == brush
                                    ? Color.accentColor.opacity(0.3)
                                    : Color.clear
                            )
                            .clipShape(Circle())
                            .overlay(
                                Circle().stroke(
                                    selectedBrush == brush ? Color.accentColor : .clear,
                                    lineWidth: 2
                                )
                            )

                        Text(brush.rawValue)
                            .font(.caption2)
                    }
                    .foregroundStyle(selectedBrush == brush ? .primary : .secondary)
                    .onTapGesture {
                        selectedBrush = brush
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }
}

// MARK: - Makeup AR Container
struct MakeupARContainerView: UIViewRepresentable {
    @ObservedObject var viewModel: MakeupStudioViewModel

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)

        let config = ARFaceTrackingConfiguration()
        config.maximumNumberOfTrackedFaces = 1
        config.isLightEstimationEnabled = true

        arView.session.delegate = context.coordinator
        arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])

        viewModel.arView = arView
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        viewModel.applyCurrentBrush()
    }

    func makeCoordinator() -> MakeupARCoordinator {
        MakeupARCoordinator(viewModel: viewModel)
    }
}

class MakeupARCoordinator: NSObject, ARSessionDelegate {
    let viewModel: MakeupStudioViewModel

    init(viewModel: MakeupStudioViewModel) {
        self.viewModel = viewModel
    }

    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        for anchor in anchors {
            guard let faceAnchor = anchor as? ARFaceAnchor else { continue }
            DispatchQueue.main.async {
                self.viewModel.setupFaceEntity(for: faceAnchor)
            }
        }
    }

    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        for anchor in anchors {
            guard let faceAnchor = anchor as? ARFaceAnchor else { continue }
            DispatchQueue.main.async {
                self.viewModel.updateFaceGeometry(for: faceAnchor)
            }
        }
    }
}

// MARK: - ViewModel
@MainActor
class MakeupStudioViewModel: ObservableObject {
    @Published var brushSettings = BrushSettings()
    @Published var isEditing = false
    @Published var appliedLayers: [MakeupLayer] = []

    weak var arView: ARView?
    private var faceEntity: ModelEntity?

    func setupFaceEntity(for faceAnchor: ARFaceAnchor) {
        guard let arView else { return }

        let faceGeometry = faceAnchor.geometry
        var meshDescriptor = MeshDescriptor(name: "makeupFace")
        meshDescriptor.positions = MeshBuffer(faceGeometry.vertices.map { SIMD3<Float>($0.0, $0.1, $0.2) })
        meshDescriptor.primitives = .triangles(faceGeometry.triangleIndices.map { UInt32($0) })
        meshDescriptor.textureCoordinates = MeshBuffer(faceGeometry.textureCoordinates.map { SIMD2<Float>($0.0, $0.1) })

        guard let meshResource = try? MeshResource.generate(from: [meshDescriptor]) else { return }

        var material = SimpleMaterial()
        material.color = .init(tint: brushSettings.uiColor.withAlphaComponent(CGFloat(brushSettings.opacity)))
        material.metallic = 0
        material.roughness = 0.8

        let entity = ModelEntity(mesh: meshResource, materials: [material])
        faceEntity = entity

        let anchorEntity = AnchorEntity(anchor: faceAnchor)
        anchorEntity.addChild(entity)
        arView.scene.addAnchor(anchorEntity)
    }

    func updateFaceGeometry(for faceAnchor: ARFaceAnchor) {
        guard let faceEntity else { return }

        let faceGeometry = faceAnchor.geometry
        var meshDescriptor = MeshDescriptor(name: "makeupFace")
        meshDescriptor.positions = MeshBuffer(faceGeometry.vertices.map { SIMD3<Float>($0.0, $0.1, $0.2) })
        meshDescriptor.primitives = .triangles(faceGeometry.triangleIndices.map { UInt32($0) })
        meshDescriptor.textureCoordinates = MeshBuffer(faceGeometry.textureCoordinates.map { SIMD2<Float>($0.0, $0.1) })

        guard let meshResource = try? MeshResource.generate(from: [meshDescriptor]) else { return }
        faceEntity.model?.mesh = meshResource
    }

    func applyCurrentBrush() {
        guard let faceEntity else { return }
        var material = SimpleMaterial()
        material.color = .init(tint: brushSettings.uiColor.withAlphaComponent(CGFloat(brushSettings.opacity)))
        material.metallic = 0
        material.roughness = 0.8
        faceEntity.model?.materials = [material]
    }

    func resetMakeup() {
        appliedLayers.removeAll()
        guard let faceEntity else { return }
        var material = SimpleMaterial()
        material.color = .init(tint: .clear)
        material.metallic = 0
        material.roughness = 1
        faceEntity.model?.materials = [material]
    }
}
