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
            if captureVM.isFaceDetected && captureVM.scanProgress < 1.0 {
                HStack(spacing: 16) {
                    Image(systemName: "arrow.left")
                        .font(.title2.bold())
                        .foregroundStyle(captureVM.leftProgress >= 1.0 ? Color.green : .white)
                        .opacity(captureVM.leftProgress >= 1.0 ? 0.5 : (arrowPulse ? 1.0 : 0.4))

                    VStack(spacing: 4) {
                        Text("얼굴을 좌우로")
                        Text("천천히 돌려주세요")
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

    // ── 체류 시간 기반 스캔 ──────────────────────────────
    // 각 방향에서 일정 시간 이상 머물러야 진행됨
    private let yawThreshold: Float     = 0.18   // 이 각도 이상 돌아야 카운트
    private let requiredDwell: Double   = 1.2    // 각 방향당 필요 체류 시간(초)
    private let minTotalTime: Double    = 3.0    // 최소 총 스캔 시간(초)
    private let captureDelay: Double    = 0.8    // 100% 후 캡처까지 대기(초)

    private var leftDwell:  Double = 0   // yaw > threshold 누적 시간
    private var rightDwell: Double = 0   // yaw < -threshold 누적 시간
    private var totalElapsed: Double = 0
    private var lastTimestamp: Date? = nil
    private var hasAutoCaptured = false
    private var isCountingDown = false

    var statusMessage: String {
        if isCapturing    { return "스캔 완료! 처리 중..." }
        if isCountingDown { return "완료! 잠시 기다려주세요..." }
        if !isFaceDetected { return "얼굴을 가이드 안에 맞춰주세요" }
        if scanProgress >= 1.0 { return "완료! 잠시 기다려주세요..." }
        if leftProgress >= 1.0  { return "이제 반대쪽으로 돌려주세요 →" }
        if rightProgress >= 1.0 { return "← 반대쪽으로 돌려주세요" }
        return "좌우로 천천히 고개를 돌려주세요"
    }

    /// 매 프레임 ARFaceAnchor에서 yaw 추출 + 체류 시간 누적
    func updateScan(from anchor: ARFaceAnchor) {
        guard !hasAutoCaptured, !isCountingDown else { return }

        let now = Date()
        let dt = lastTimestamp.map { now.timeIntervalSince($0) } ?? (1.0 / 30.0)
        lastTimestamp = now

        // 너무 큰 dt는 포즈 손실로 간주 (최대 0.1초)
        let clampedDt = min(dt, 0.1)
        totalElapsed += clampedDt

        // columns.2.x: 얼굴 정면 벡터의 x성분 → 좌우 회전량
        let yaw = anchor.transform.columns.2.x

        if yaw > yawThreshold {
            leftDwell  += clampedDt
        } else if yaw < -yawThreshold {
            rightDwell += clampedDt
        }

        let lp = min(leftDwell  / requiredDwell, 1.0)
        let rp = min(rightDwell / requiredDwell, 1.0)

        // 전체 진행률: 좌우 체류 + 최소 총 시간 모두 충족해야 100%
        let timeFactor = min(totalElapsed / minTotalTime, 1.0)
        let coverFactor = (lp + rp) / 2.0
        let combinedProgress = min(timeFactor, coverFactor)

        leftProgress  = lp
        rightProgress = rp
        scanProgress  = combinedProgress

        if lp >= 1.0 && rp >= 1.0 && totalElapsed >= minTotalTime {
            isCountingDown = true
            hasAutoCaptured = true
            // 1.5초 후 정면을 바라볼 때 캡처
            DispatchQueue.main.asyncAfter(deadline: .now() + captureDelay) {
                self.capture()
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
