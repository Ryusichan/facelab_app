import SwiftUI
import ARKit
import SceneKit

// ============================================================
// MARK: - FaceCaptureView
// TrueDepth 카메라로 얼굴 3D mesh 캡처
// ARFaceGeometry + 카메라 텍스처를 FaceScanData로 패키징
// ============================================================
struct FaceCaptureView: View {
    @EnvironmentObject var router: AppRouter
    @StateObject private var captureVM = FaceCaptureViewModel()

    var body: some View {
        ZStack {
            // AR 카메라 뷰
            FaceCaptureARView(viewModel: captureVM)
                .ignoresSafeArea()

            // 얼굴 가이드 오버레이
            FaceGuideOverlay(isFaceDetected: captureVM.isFaceDetected)

            // UI 오버레이
            VStack {
                // 상태 텍스트
                statusBadge
                    .padding(.top, 70)

                Spacer()

                // 캡처 버튼
                captureButton
                    .padding(.bottom, 50)
            }

            // 뒤로가기 버튼
            VStack {
                HStack {
                    Button {
                        router.goTo(.inputMethod)
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.title3.bold())
                            .foregroundStyle(.white)
                            .padding(12)
                            .background(.black.opacity(0.4), in: Circle())
                    }
                    .padding(.leading, 20)
                    .padding(.top, 60)
                    Spacer()
                }
                Spacer()
            }
        }
        .onChange(of: captureVM.capturedScanData) { _, newValue in
            if let scanData = newValue {
                router.scanData = scanData
                router.goTo(.processing)
            }
        }
    }

    private var statusBadge: some View {
        Text(captureVM.statusMessage)
            .font(.callout.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                (captureVM.isFaceDetected ? Color.green : Color.orange).opacity(0.7),
                in: Capsule()
            )
    }

    private var captureButton: some View {
        Button {
            captureVM.capture()
        } label: {
            ZStack {
                Circle()
                    .fill(.white)
                    .frame(width: 72, height: 72)
                Circle()
                    .stroke(.white.opacity(0.5), lineWidth: 4)
                    .frame(width: 82, height: 82)
            }
        }
        .disabled(!captureVM.isFaceDetected || captureVM.isCapturing)
        .opacity(captureVM.isFaceDetected ? 1 : 0.4)
    }
}

// MARK: - Face Guide Overlay (타원 가이드)
private struct FaceGuideOverlay: View {
    let isFaceDetected: Bool

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width * 0.65
            let h = w * 1.35
            let rect = CGRect(
                x: (geo.size.width - w) / 2,
                y: (geo.size.height - h) / 2 - 30,
                width: w,
                height: h
            )

            // 어두운 배경 + 타원 컷아웃
            Canvas { ctx, size in
                ctx.fill(
                    Path(CGRect(origin: .zero, size: size)),
                    with: .color(.black.opacity(0.35))
                )
                ctx.blendMode = .destinationOut
                ctx.fill(
                    Path(ellipseIn: rect),
                    with: .color(.white)
                )
            }
            .compositingGroup()
            .allowsHitTesting(false)

            // 타원 테두리
            Ellipse()
                .stroke(
                    isFaceDetected ? .green : .white.opacity(0.6),
                    style: StrokeStyle(lineWidth: 2, dash: isFaceDetected ? [] : [8, 6])
                )
                .frame(width: w, height: h)
                .position(x: rect.midX, y: rect.midY)
                .animation(.easeInOut(duration: 0.3), value: isFaceDetected)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - ARView Wrapper
struct FaceCaptureARView: UIViewRepresentable {
    @ObservedObject var viewModel: FaceCaptureViewModel

    func makeUIView(context: Context) -> ARSCNView {
        let sceneView = ARSCNView(frame: .zero)
        sceneView.delegate = context.coordinator
        sceneView.automaticallyUpdatesLighting = true

        let config = ARFaceTrackingConfiguration()
        config.maximumNumberOfTrackedFaces = 1
        config.isLightEstimationEnabled = true
        sceneView.session.run(config, options: [.resetTracking, .removeExistingAnchors])

        viewModel.sceneView = sceneView
        return sceneView
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {}

    func makeCoordinator() -> FaceCaptureCoordinator {
        FaceCaptureCoordinator(viewModel: viewModel)
    }
}

// MARK: - Coordinator
class FaceCaptureCoordinator: NSObject, ARSCNViewDelegate {
    let viewModel: FaceCaptureViewModel

    init(viewModel: FaceCaptureViewModel) {
        self.viewModel = viewModel
    }

    // 얼굴 감지 시 투명 노드 반환 (카메라 피드만 표시)
    func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
        guard anchor is ARFaceAnchor else { return nil }
        DispatchQueue.main.async { self.viewModel.isFaceDetected = true }
        return SCNNode()
    }

    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        guard let faceAnchor = anchor as? ARFaceAnchor else { return }
        DispatchQueue.main.async {
            self.viewModel.latestFaceAnchor = faceAnchor
        }
    }

    func renderer(_ renderer: SCNSceneRenderer, didRemove node: SCNNode, for anchor: ARAnchor) {
        guard anchor is ARFaceAnchor else { return }
        DispatchQueue.main.async {
            self.viewModel.isFaceDetected = false
            self.viewModel.latestFaceAnchor = nil
        }
    }
}

// MARK: - ViewModel
@MainActor
class FaceCaptureViewModel: ObservableObject {
    @Published var isFaceDetected = false
    @Published var isCapturing = false
    @Published var capturedScanData: FaceScanData?

    // nonisolated(unsafe): SceneKit 렌더 스레드에서 쓰기, MainActor에서 읽기
    nonisolated(unsafe) var latestFaceAnchor: ARFaceAnchor?
    weak var sceneView: ARSCNView?

    var statusMessage: String {
        if isCapturing { return "캡처 중..." }
        if isFaceDetected { return "얼굴 감지됨 — 버튼을 눌러 캡처" }
        return "얼굴을 가이드 안에 맞춰주세요"
    }

    func capture() {
        guard let sceneView, let faceAnchor = latestFaceAnchor,
              let frame = sceneView.session.currentFrame else { return }

        isCapturing = true

        let viewportSize = sceneView.bounds.size
        let scanData = FaceScanData.capture(
            faceAnchor: faceAnchor,
            frame: frame,
            viewportSize: viewportSize
        )

        capturedScanData = scanData
        isCapturing = false
    }
}
