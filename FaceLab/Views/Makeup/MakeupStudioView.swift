import SwiftUI
import ARKit
import SceneKit
import Photos

// ============================================================
// MARK: - MakeupStudioView (메인 뷰)
// 전체 화면 AR 카메라 + 하단 메이크업 컨트롤 패널
// ============================================================
struct MakeupStudioView: View {
    @StateObject private var viewModel = MakeupViewModel()

    var body: some View {
        ZStack {
            // 전체 화면 AR 뷰 (ARSCNView 래퍼)
            FaceARSceneView(viewModel: viewModel)
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
                        .padding(.top, 70)
                    Spacer()
                }
            }

            // Before 모드 배지
            if viewModel.isBeforeMode {
                VStack {
                    Text("BEFORE")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 5)
                        .background(.black.opacity(0.65), in: Capsule())
                        .padding(.top, 70)
                    Spacer()
                }
            }

            // 캡처 플래시 효과
            if viewModel.showCaptureFlash {
                Color.white
                    .ignoresSafeArea()
                    .opacity(0.75)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }

            // UI 오버레이
            VStack(spacing: 0) {
                topBar
                Spacer()
                bottomPanel
            }
        }
        .animation(.easeInOut(duration: 0.15), value: viewModel.showCaptureFlash)
        .animation(.easeInOut(duration: 0.2),  value: viewModel.isBeforeMode)
        .animation(.easeInOut(duration: 0.2),  value: viewModel.isFaceDetected)
    }

    // ──────────────────────────────────────────
    // MARK: Top Bar
    // ──────────────────────────────────────────
    private var topBar: some View {
        HStack {
            Text("FaceLab")
                .font(.title3.bold())
                .foregroundStyle(.white)

            Spacer()

            // 캡처 버튼 (상단 우측)
            Button {
                viewModel.capturePhoto()
            } label: {
                Image(systemName: "camera.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(.black.opacity(0.4), in: Circle())
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 60)
    }

    // ──────────────────────────────────────────
    // MARK: Bottom Control Panel
    // ──────────────────────────────────────────
    private var bottomPanel: some View {
        VStack(spacing: 0) {
            // 액션 버튼 행 (Reset / Before·After / On-Off)
            actionRow
                .padding(.horizontal, 20)
                .padding(.top, 14)

            // 브러쉬 강도 슬라이더
            intensitySlider
                .padding(.horizontal, 20)
                .padding(.top, 10)

            // 색상 팔레트
            colorPalette
                .padding(.top, 10)

            // 카테고리 탭
            categoryTabs
                .padding(.top, 6)
                .padding(.bottom, 34) // Home indicator 여백
        }
        .background(.ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }

    // ──────────────────────────────────────────
    // MARK: Action Row
    // ──────────────────────────────────────────
    private var actionRow: some View {
        HStack(spacing: 10) {
            // Reset: 모든 메이크업 초기화
            Button {
                viewModel.reset()
            } label: {
                Label("Reset", systemImage: "arrow.counterclockwise")
                    .font(.caption.bold())
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.secondary.opacity(0.18), in: Capsule())
            }

            // Before / After 비교
            Button {
                viewModel.toggleBeforeAfter()
            } label: {
                Label(
                    viewModel.isBeforeMode ? "After" : "Before",
                    systemImage: viewModel.isBeforeMode ? "eye.fill" : "eye.slash.fill"
                )
                .font(.caption.bold())
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    viewModel.isBeforeMode
                        ? Color.accentColor.opacity(0.25)
                        : Color.secondary.opacity(0.18),
                    in: Capsule()
                )
            }

            Spacer()

            // 현재 카테고리 On/Off 토글
            VStack(spacing: 2) {
                Toggle("", isOn: Binding(
                    get: { viewModel.currentLayer.isEnabled },
                    set: { viewModel.setEnabled($0) }
                ))
                .labelsHidden()
                .scaleEffect(0.85)

                Text(viewModel.selectedCategory.rawValue)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(.primary)
    }

    // ──────────────────────────────────────────
    // MARK: Intensity Slider
    // ──────────────────────────────────────────
    private var intensitySlider: some View {
        HStack(spacing: 10) {
            // 최소 아이콘
            Image(systemName: "circle")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            Slider(
                value: Binding(
                    get: { viewModel.currentLayer.intensity },
                    set: { viewModel.setIntensity($0) }
                ),
                in: 0.0...1.0
            )
            .tint(viewModel.currentLayer.selectedColor)

            // 최대 아이콘
            Image(systemName: "circle.fill")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            // 퍼센트 표시
            Text("\(Int(viewModel.currentLayer.intensity * 100))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 38, alignment: .trailing)
        }
    }

    // ──────────────────────────────────────────
    // MARK: Color Palette
    // ──────────────────────────────────────────
    private var colorPalette: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(viewModel.selectedCategory.colorPresets.indices, id: \.self) { index in
                    let color = viewModel.selectedCategory.colorPresets[index]
                    ColorSwatch(
                        color: color,
                        isSelected: viewModel.isColorSelected(color),
                        onTap: { viewModel.setColor(color) }
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
    }

    // ──────────────────────────────────────────
    // MARK: Category Tabs
    // ──────────────────────────────────────────
    private var categoryTabs: some View {
        HStack(spacing: 0) {
            ForEach(MakeupCategory.allCases) { category in
                let isSelected = viewModel.selectedCategory == category

                Button {
                    withAnimation(.spring(response: 0.3)) {
                        viewModel.selectedCategory = category
                    }
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: category.icon)
                            .font(.title3)
                        Text(category.rawValue)
                            .font(.caption2.bold())
                    }
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(.secondary.opacity(0.15))
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
    }
}

// ============================================================
// MARK: - Color Swatch (재사용 컴포넌트)
// ============================================================
private struct ColorSwatch: View {
    let color: Color
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 34, height: 34)
            .overlay {
                if isSelected {
                    Circle().strokeBorder(.white, lineWidth: 2.5)
                }
            }
            .overlay {
                if isSelected {
                    Circle().strokeBorder(color.opacity(0.4), lineWidth: 5)
                }
            }
            .shadow(color: color.opacity(0.35), radius: 3, y: 1)
            .scaleEffect(isSelected ? 1.18 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isSelected)
            .onTapGesture(perform: onTap)
    }
}

// ============================================================
// MARK: - FaceARSceneView (UIViewRepresentable)
// ARSCNView 기반 face tracking 뷰
// ARSCNFaceGeometry를 사용해 얼굴 mesh에 메이크업 텍스처 적용
// ============================================================
struct FaceARSceneView: UIViewRepresentable {
    @ObservedObject var viewModel: MakeupViewModel

    func makeUIView(context: Context) -> ARSCNView {
        let sceneView = ARSCNView(frame: .zero)
        sceneView.delegate = context.coordinator
        sceneView.automaticallyUpdatesLighting = true
        sceneView.autoenablesDefaultLighting = false

        // face tracking 세션 시작
        let config = ARFaceTrackingConfiguration()
        config.maximumNumberOfTrackedFaces = 1
        config.isLightEstimationEnabled = true
        sceneView.session.run(config, options: [.resetTracking, .removeExistingAnchors])

        // 캡처용 참조 저장
        viewModel.sceneView = sceneView
        context.coordinator.viewModel = viewModel

        return sceneView
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {
        // 텍스처 업데이트는 Coordinator의 renderer(_:didUpdate:for:)에서 처리
    }

    func makeCoordinator() -> FaceSceneCoordinator {
        FaceSceneCoordinator()
    }
}

// ============================================================
// MARK: - FaceSceneCoordinator (ARSCNViewDelegate)
// 얼굴 anchor 감지 → ARSCNFaceGeometry 생성 → 메이크업 텍스처 적용
// ============================================================
class FaceSceneCoordinator: NSObject, ARSCNViewDelegate {
    weak var viewModel: MakeupViewModel?

    private var faceGeometry: ARSCNFaceGeometry? // 얼굴 mesh (매 프레임 업데이트)
    private var faceNode: SCNNode?               // 텍스처가 붙는 SceneKit 노드
    private var lastAppliedTexture: UIImage?     // 중복 업데이트 방지용

    // 새 얼굴 anchor 감지 시 호출 → 노드 생성 반환
    func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
        guard anchor is ARFaceAnchor else { return nil }

        // ARSCNFaceGeometry는 Metal device 필요
        guard let device = (renderer as? ARSCNView)?.device,
              let faceGeo = ARSCNFaceGeometry(device: device) else {
            return nil
        }

        configureMaterial(for: faceGeo)

        self.faceGeometry = faceGeo
        let node = SCNNode(geometry: faceGeo)
        self.faceNode = node

        DispatchQueue.main.async { self.viewModel?.isFaceDetected = true }
        return node
    }

    // 매 프레임 호출 → face mesh 위치 갱신 + 텍스처 교체
    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        guard let faceAnchor = anchor as? ARFaceAnchor else { return }

        // 얼굴 변형(표정, 위치)에 따라 mesh geometry 갱신
        faceGeometry?.update(from: faceAnchor.geometry)

        // 메이크업 텍스처가 바뀐 경우에만 SCNMaterial 업데이트 (성능 최적화)
        let newTexture = viewModel?.makeupTexture
        if newTexture !== lastAppliedTexture {
            lastAppliedTexture = newTexture
            faceNode?.geometry?.firstMaterial?.diffuse.contents = newTexture ?? UIColor.clear
        }
    }

    // 얼굴이 화면 밖으로 나간 경우
    func renderer(_ renderer: SCNSceneRenderer, didRemove node: SCNNode, for anchor: ARAnchor) {
        guard anchor is ARFaceAnchor else { return }
        DispatchQueue.main.async { self.viewModel?.isFaceDetected = false }
    }

    // ──────────────────────────────────────────
    // MARK: Material Setup
    // ──────────────────────────────────────────
    private func configureMaterial(for geometry: ARSCNFaceGeometry) {
        guard let material = geometry.firstMaterial else { return }

        // .constant: 조명 영향 없음 → 메이크업 색상이 정확하게 표현
        material.lightingModel = .constant
        material.isDoubleSided = true

        // 알파 기반 투명도: alpha=0인 영역은 카메라 피드가 비침
        material.transparencyMode = .aOne
        material.blendMode = .alpha

        // 초기 상태: 완전 투명 (메이크업 없음)
        material.diffuse.contents = UIColor.clear

        // depth buffer 미기록 → 카메라 배경과의 렌더링 충돌 방지
        material.writesToDepthBuffer = false
    }
}

// ============================================================
// MARK: - MakeupViewModel
// 모든 메이크업 상태를 관리하는 중앙 ViewModel
// ============================================================
@MainActor
class MakeupViewModel: ObservableObject {

    // MARK: Published State
    @Published var selectedCategory: MakeupCategory = .lip

    // 카테고리별 레이어 상태 (색상, 강도, on/off)
    @Published var layers: [MakeupCategory: MakeupLayerState] = {
        Dictionary(uniqueKeysWithValues: MakeupCategory.allCases.map {
            ($0, MakeupLayerState(category: $0))
        })
    }()

    @Published var isBeforeMode: Bool = false
    @Published var isFaceDetected: Bool = false
    @Published var showCaptureFlash: Bool = false

    // MARK: Internal State
    /// 현재 메이크업 텍스처 — FaceSceneCoordinator가 읽어 SCNMaterial에 적용
    /// nonisolated(unsafe): SceneKit 렌더 스레드에서 읽기 전용 접근, MainActor에서만 쓰기
    nonisolated(unsafe) var makeupTexture: UIImage? = nil

    /// ARSCNView 참조 (캡처용)
    weak var sceneView: ARSCNView?

    // MARK: Computed
    /// 현재 선택된 카테고리의 레이어 상태
    var currentLayer: MakeupLayerState {
        layers[selectedCategory] ?? MakeupLayerState(category: selectedCategory)
    }

    // MARK: Color Comparison Helper
    // Color는 iOS 17+에서 Equatable이지만 정밀 비교를 위해 UIColor 경유
    func isColorSelected(_ color: Color) -> Bool {
        guard let stored = layers[selectedCategory] else { return false }
        return UIColor(stored.selectedColor).isApproximatelyEqual(to: UIColor(color))
    }

    // MARK: Actions

    func setColor(_ color: Color) {
        layers[selectedCategory]?.selectedColor = color
        updateTexture()
    }

    func setIntensity(_ intensity: Double) {
        layers[selectedCategory]?.intensity = intensity
        updateTexture()
    }

    func setEnabled(_ enabled: Bool) {
        layers[selectedCategory]?.isEnabled = enabled
        updateTexture()
    }

    func toggleBeforeAfter() {
        isBeforeMode.toggle()
        updateTexture()
    }

    /// 모든 메이크업 초기화
    func reset() {
        for category in MakeupCategory.allCases {
            layers[category] = MakeupLayerState(category: category)
        }
        updateTexture()
    }

    /// ARSCNView 스냅샷을 사진 앨범에 저장
    func capturePhoto() {
        guard let sceneView = sceneView else { return }
        let image = sceneView.snapshot()

        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else { return }
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            } completionHandler: { success, _ in
                guard success else { return }
                DispatchQueue.main.async {
                    self.showCaptureFlash = true
                    Task {
                        try? await Task.sleep(for: .milliseconds(300))
                        self.showCaptureFlash = false
                    }
                }
            }
        }
    }

    // MARK: Texture Update
    /// 현재 레이어 상태를 기반으로 메이크업 텍스처 재생성
    /// Before 모드일 때는 nil (투명) 반환
    func updateTexture() {
        if isBeforeMode {
            makeupTexture = nil
            return
        }
        makeupTexture = MakeupTextureRenderer.render(layers: Array(layers.values))
    }
}

// ============================================================
// MARK: - UIColor Approximate Equality
// Color 비교 시 부동소수점 오차 허용
// ============================================================
extension UIColor {
    func isApproximatelyEqual(to other: UIColor, tolerance: CGFloat = 0.01) -> Bool {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return abs(r1-r2) < tolerance && abs(g1-g2) < tolerance && abs(b1-b2) < tolerance
    }
}
