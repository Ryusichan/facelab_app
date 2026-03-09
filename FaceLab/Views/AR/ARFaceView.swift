import SwiftUI
import ARKit
import SceneKit

// ============================================================
// MARK: - ARFaceView
// 얼굴 스캔 프리뷰 탭 (메이크업 없이 순수 face mesh 표시)
// 메이크업 기능은 MakeupStudioView에 있음
// ============================================================
struct ARFaceView: View {
    @StateObject private var viewModel = ARFaceViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                // ARSCNView face tracking
                ARFaceSceneView(viewModel: viewModel)
                    .ignoresSafeArea()

                // 얼굴 미감지 안내
                if !viewModel.isFaceDetected {
                    VStack {
                        Text("얼굴을 카메라 안에 위치해주세요")
                            .font(.callout)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(.black.opacity(0.55), in: Capsule())
                            .padding(.top, 20)
                        Spacer()
                    }
                }

                // 하단 캡처 버튼
                VStack {
                    Spacer()
                    Button {
                        viewModel.captureSnapshot()
                    } label: {
                        Image(systemName: "camera.circle.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(.white)
                            .shadow(radius: 4)
                    }
                    .padding(.bottom, 44)
                }
            }
            .navigationTitle("Face Preview")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// ============================================================
// MARK: - ARFaceSceneView (UIViewRepresentable)
// 투명 mesh overlay로 얼굴 3D 구조 표시
// ============================================================
struct ARFaceSceneView: UIViewRepresentable {
    @ObservedObject var viewModel: ARFaceViewModel

    func makeUIView(context: Context) -> ARSCNView {
        let sceneView = ARSCNView(frame: .zero)
        sceneView.delegate = context.coordinator
        sceneView.automaticallyUpdatesLighting = true

        let config = ARFaceTrackingConfiguration()
        config.maximumNumberOfTrackedFaces = 1
        config.isLightEstimationEnabled = true
        sceneView.session.run(config, options: [.resetTracking, .removeExistingAnchors])

        viewModel.sceneView = sceneView
        context.coordinator.viewModel = viewModel
        return sceneView
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {}

    func makeCoordinator() -> ARFaceCoordinator {
        ARFaceCoordinator()
    }
}

// ============================================================
// MARK: - ARFaceCoordinator
// ============================================================
class ARFaceCoordinator: NSObject, ARSCNViewDelegate {
    weak var viewModel: ARFaceViewModel?
    private var faceGeometry: ARSCNFaceGeometry?

    func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
        guard anchor is ARFaceAnchor,
              let device = (renderer as? ARSCNView)?.device,
              let faceGeo = ARSCNFaceGeometry(device: device) else { return nil }

        // 와이어프레임 느낌의 반투명 mesh 표시
        if let material = faceGeo.firstMaterial {
            material.lightingModel = .constant
            material.isDoubleSided = true
            material.transparencyMode = .aOne
            material.blendMode = .alpha
            material.diffuse.contents = UIColor.white.withAlphaComponent(0.08)
            material.emission.contents  = UIColor(red: 0.3, green: 0.9, blue: 1.0, alpha: 0.25)
            material.writesToDepthBuffer = false
        }

        self.faceGeometry = faceGeo
        DispatchQueue.main.async { self.viewModel?.isFaceDetected = true }
        return SCNNode(geometry: faceGeo)
    }

    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        guard let faceAnchor = anchor as? ARFaceAnchor else { return }
        faceGeometry?.update(from: faceAnchor.geometry)
    }

    func renderer(_ renderer: SCNSceneRenderer, didRemove node: SCNNode, for anchor: ARAnchor) {
        guard anchor is ARFaceAnchor else { return }
        DispatchQueue.main.async { self.viewModel?.isFaceDetected = false }
    }
}

// ============================================================
// MARK: - ARFaceViewModel
// ============================================================
@MainActor
class ARFaceViewModel: ObservableObject {
    @Published var isFaceDetected = false
    @Published var capturedImage: UIImage?

    weak var sceneView: ARSCNView?

    func captureSnapshot() {
        guard let sceneView else { return }
        let image = sceneView.snapshot()
        capturedImage = image
        // TODO: Photos 저장 또는 Supabase 업로드 연동 포인트
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
    }
}
