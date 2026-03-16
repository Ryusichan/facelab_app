import SwiftUI
import ARKit
import SceneKit

// ============================================================
// MARK: - FaceCaptureView
// 얼굴을 좌우로 돌리는 동안 yaw 각도를 추적하여
// 충분한 커버리지가 쌓이면 자동 캡처 → 3D 모델링
// ============================================================
struct FaceCaptureView: View {
    @EnvironmentObject var router: AppRouter
    @StateObject private var captureVM = FaceCaptureViewModel()
    @State private var arrowPulse = false

    var body: some View {
        ZStack {
            FaceCaptureARView(viewModel: captureVM)
                .ignoresSafeArea()

            FaceGuideOverlay(
                isFaceDetected: captureVM.isFaceDetected,
                leftProgress: captureVM.leftProgress,
                rightProgress: captureVM.rightProgress
            )

            VStack {
                statusBadge
                    .padding(.top, 70)
                Spacer()
                bottomUI
                    .padding(.bottom, 50)
            }

            // 뒤로가기
            VStack {
                HStack {
                    Button { router.goTo(.inputMethod) } label: {
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
        .onAppear {
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                arrowPulse = true
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
                (captureVM.scanProgress >= 1.0 ? Color.green
                 : captureVM.isFaceDetected ? Color.blue
                 : Color.orange).opacity(0.75),
                in: Capsule()
            )
            .animation(.easeInOut(duration: 0.3), value: captureVM.isFaceDetected)
    }

    private var bottomUI: some View {
        VStack(spacing: 14) {
            // 방향 안내 + 화살표
            if captureVM.isFaceDetected && !captureVM.isCapturing {
                if captureVM.waitingForFront {
                    // 양쪽 완료 → 정면 복귀 안내
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2.bold())
                            .foregroundStyle(Color.green)
                            .opacity(arrowPulse ? 1.0 : 0.5)
                        Text("정면을 바라봐주세요")
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
                } else if captureVM.scanProgress < 1.0 {
                    // 좌/우 방향 안내
                    HStack(spacing: 16) {
                        Image(systemName: "arrow.left")
                            .font(.title2.bold())
                            .foregroundStyle(captureVM.leftProgress >= 1.0 ? Color.green : .white)
                            .opacity(captureVM.leftProgress >= 1.0 ? 0.5 : (arrowPulse ? 1.0 : 0.4))

                        VStack(spacing: 4) {
                            Text("고개를 좌우로")
                            Text("한 번씩 돌려주세요")
                        }
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)

                        Image(systemName: "arrow.right")
                            .font(.title2.bold())
                            .foregroundStyle(captureVM.rightProgress >= 1.0 ? Color.green : .white)
                            .opacity(captureVM.rightProgress >= 1.0 ? 0.5 : (arrowPulse ? 1.0 : 0.4))
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
                }
            }

            // 진행률
            if captureVM.isFaceDetected {
                VStack(spacing: 6) {
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.white.opacity(0.2))
                            .frame(width: 240, height: 8)
                        Capsule()
                            .fill(captureVM.scanProgress >= 1.0 ? Color.green : Color.accentColor)
                            .frame(width: 240 * captureVM.scanProgress, height: 8)
                            .animation(.easeOut(duration: 0.15), value: captureVM.scanProgress)
                    }
                    Text("\(Int(captureVM.scanProgress * 100))%")
                        .font(.caption.monospacedDigit().bold())
                        .foregroundStyle(.white)
                }
            }
        }
    }
}

// MARK: - Face Guide Overlay
private struct FaceGuideOverlay: View {
    let isFaceDetected: Bool
    let leftProgress: Double
    let rightProgress: Double

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width * 0.65
            let h = w * 1.35
            let rect = CGRect(
                x: (geo.size.width - w) / 2,
                y: (geo.size.height - h) / 2 - 30,
                width: w, height: h
            )

            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black.opacity(0.35)))
                ctx.blendMode = .destinationOut
                ctx.fill(Path(ellipseIn: rect), with: .color(.white))
            }
            .compositingGroup()
            .allowsHitTesting(false)

            let borderColor: Color = isFaceDetected ? .green : .white.opacity(0.6)
            Ellipse()
                .stroke(borderColor, style: StrokeStyle(lineWidth: 2, dash: isFaceDetected ? [] : [8, 6]))
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

    func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
        guard anchor is ARFaceAnchor else { return nil }
        DispatchQueue.main.async { self.viewModel.isFaceDetected = true }
        return SCNNode()
    }

    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        guard let faceAnchor = anchor as? ARFaceAnchor else { return }
        DispatchQueue.main.async {
            self.viewModel.latestFaceAnchor = faceAnchor
            self.viewModel.updateScan(from: faceAnchor)
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
    @Published var scanProgress: Double = 0   // 0.0 ~ 1.0
    @Published var leftProgress: Double = 0   // 왼쪽 커버리지
    @Published var rightProgress: Double = 0  // 오른쪽 커버리지

    nonisolated(unsafe) var latestFaceAnchor: ARFaceAnchor?
    weak var sceneView: ARSCNView?

    // ── 단순 방향 감지 스캔 ─────────────────────────────
    // 좌/우 각 방향을 한 번씩 통과 → 정면 복귀 시 캡처
    // (정면에서 캡처해야 양쪽 텍스처가 균일하게 베이킹됨)
    private let yawThreshold: Float  = 0.20   // 좌/우 감지 각도
    private let frontThreshold: Float = 0.10  // 정면으로 간주하는 yaw 범위

    private var hasSeenLeft  = false   // 왼쪽 방향 통과 여부
    private var hasSeenRight = false   // 오른쪽 방향 통과 여부
    @Published var waitingForFront = false  // 양쪽 완료 후 정면 대기 상태
    private var hasAutoCaptured = false

    var statusMessage: String {
        if isCapturing      { return "스캔 완료! 처리 중..." }
        if waitingForFront  { return "정면을 바라봐주세요" }
        if !isFaceDetected  { return "얼굴을 가이드 안에 맞춰주세요" }
        if !hasSeenLeft     { return "← 왼쪽으로 고개를 돌려주세요" }
        if !hasSeenRight    { return "오른쪽으로 고개를 돌려주세요 →" }
        return "정면을 바라봐주세요"
    }

    /// 매 프레임 ARFaceAnchor에서 yaw 추출 → 좌/우 통과 감지 → 정면 복귀 시 캡처
    func updateScan(from anchor: ARFaceAnchor) {
        guard !hasAutoCaptured else { return }

        let yaw = anchor.transform.columns.2.x

        if !waitingForFront {
            if yaw > yawThreshold  { hasSeenLeft  = true }
            if yaw < -yawThreshold { hasSeenRight = true }

            leftProgress  = hasSeenLeft  ? 1.0 : 0.0
            rightProgress = hasSeenRight ? 1.0 : 0.0
            scanProgress  = (hasSeenLeft ? 0.5 : 0.0) + (hasSeenRight ? 0.5 : 0.0)

            if hasSeenLeft && hasSeenRight {
                waitingForFront = true
            }
        } else {
            // 정면 복귀 감지 → 즉시 캡처
            if abs(yaw) < frontThreshold {
                hasAutoCaptured = true
                capture()
            }
        }
    }

    func capture() {
        guard let sceneView = sceneView, let faceAnchor = latestFaceAnchor,
              let frame = sceneView.session.currentFrame else { return }
        isCapturing = true
        let viewportSize = sceneView.bounds.size
        capturedScanData = FaceScanData.capture(
            faceAnchor: faceAnchor,
            frame: frame,
            viewportSize: viewportSize
        )
        isCapturing = false
    }
}
