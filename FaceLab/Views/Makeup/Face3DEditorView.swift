import SwiftUI
import SceneKit
import Photos

// ============================================================
// MARK: - Face3DEditorView
// 캡처된 3D 얼굴 모델 뷰어 + 메이크업 에디터
// 레이아웃: 좌측 카테고리 사이드바 / 중앙 3D 뷰 / 우측 컨트롤 사이드바 / 하단 액션바
// ============================================================
struct Face3DEditorView: View {
    let scanData: FaceScanData
    @EnvironmentObject var router: AppRouter
    @StateObject private var viewModel: FaceEditorViewModel

    init(scanData: FaceScanData) {
        self.scanData = scanData
        _viewModel = StateObject(wrappedValue: FaceEditorViewModel(scanData: scanData))
    }

    var body: some View {
        ZStack {
            // 전체 배경
            Color(white: 0.06).ignoresSafeArea()

            // 3D Scene (전체 화면)
            FaceSceneContainer(viewModel: viewModel)
                .ignoresSafeArea()

            // Before 배지
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

            // 캡처 플래시
            if viewModel.showCaptureFlash {
                Color.white.ignoresSafeArea()
                    .opacity(0.75)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }

            // ── UI 오버레이 레이아웃 ──
            VStack(spacing: 0) {
                // 상단 바
                topBar
                    .padding(.top, 60)

                // 중간 영역: 좌측 사이드바 + 3D공간 + 우측 사이드바
                HStack(spacing: 0) {
                    leftCategorySidebar
                    Spacer()
                    rightControlSidebar
                }

                // 하단: 컬러 팔레트 + 액션 버튼
                bottomBar
                    .padding(.bottom, 34)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: viewModel.showCaptureFlash)
        .animation(.easeInOut(duration: 0.2), value: viewModel.isBeforeMode)
        .animation(.spring(response: 0.3), value: viewModel.selectedCategory)
    }

    // ──────────────────────────────────────────
    // MARK: Top Bar
    // ──────────────────────────────────────────
    private var topBar: some View {
        HStack {
            Button { router.goTo(.inputMethod) } label: {
                Image(systemName: "chevron.left")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(.black.opacity(0.4), in: Circle())
            }
            Spacer()
            Text("3D Makeup Editor")
                .font(.headline)
                .foregroundStyle(.white)
            Spacer()
            // 카메라 리셋
            Button { viewModel.resetCamera() } label: {
                Image(systemName: "arrow.triangle.2.circlepath.camera")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(.black.opacity(0.4), in: Circle())
            }
        }
        .padding(.horizontal, 20)
    }

    // ──────────────────────────────────────────
    // MARK: Left Category Sidebar
    // 5종 카테고리 세로 배치
    // ──────────────────────────────────────────
    private var leftCategorySidebar: some View {
        VStack(spacing: 6) {
            ForEach(MakeupCategory.allCases) { cat in
                let isSelected = viewModel.selectedCategory == cat
                Button {
                    viewModel.selectedCategory = cat
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: cat.icon)
                            .font(.system(size: 18))
                        Text(cat.rawValue)
                            .font(.system(size: 8, weight: .semibold))
                    }
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.5))
                    .frame(width: 56, height: 56)
                    .background(
                        isSelected
                            ? Color.accentColor.opacity(0.55)
                            : Color.black.opacity(0.35),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                }
            }
        }
        .padding(.leading, 10)
        .padding(.vertical, 8)
    }

    // ──────────────────────────────────────────
    // MARK: Right Control Sidebar
    // 컬러 세로 팔레트 + 브러시 사이즈 + 강도 슬라이더
    // ──────────────────────────────────────────
    private var rightControlSidebar: some View {
        VStack(spacing: 12) {
            // 세로 컬러 팔레트
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 8) {
                    ForEach(viewModel.selectedCategory.colorPresets.indices, id: \.self) { i in
                        let color = viewModel.selectedCategory.colorPresets[i]
                        let selected = viewModel.isColorSelected(color)
                        Circle()
                            .fill(color)
                            .frame(width: 30, height: 30)
                            .overlay {
                                if selected {
                                    Circle().strokeBorder(.white, lineWidth: 2.5)
                                }
                            }
                            .shadow(color: color.opacity(0.4), radius: selected ? 4 : 2, y: 1)
                            .scaleEffect(selected ? 1.15 : 1.0)
                            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: selected)
                            .onTapGesture { viewModel.setColor(color) }
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 280)

            // 브러시 사이즈 표시
            if viewModel.selectedCategory != .eraser {
                VStack(spacing: 4) {
                    // 브러시 크기를 원 크기로 시각화
                    let brushVisualSize = 12 + viewModel.currentLayer.brushSize * 20
                    Circle()
                        .fill(.white.opacity(0.7))
                        .frame(width: brushVisualSize, height: brushVisualSize)
                        .frame(width: 36, height: 36)

                    Text("Size")
                        .font(.system(size: 8))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .onTapGesture {
                    // 탭하면 브러시 크기 순환: 0.25 → 0.5 → 0.75 → 1.0 → 0.25
                    let current = viewModel.currentLayer.brushSize
                    let next: Double
                    if current < 0.35 { next = 0.5 }
                    else if current < 0.6 { next = 0.75 }
                    else if current < 0.85 { next = 1.0 }
                    else { next = 0.25 }
                    viewModel.setBrushSize(next)
                }

                // 강도 (세로 슬라이더 대용 — % 표시 + 탭으로 조절)
                VStack(spacing: 4) {
                    // 커스텀 세로 강도 인디케이터
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(.white.opacity(0.15))
                            .frame(width: 6, height: 60)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(viewModel.currentLayer.selectedColor)
                            .frame(width: 6, height: max(4, 60 * viewModel.currentLayer.intensity))
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                // 위에서 아래로: 1.0 → 0.0
                                let barHeight: CGFloat = 60
                                let ratio = 1.0 - min(1, max(0, value.location.y / barHeight))
                                viewModel.setIntensity(ratio)
                            }
                    )

                    Text("\(Int(viewModel.currentLayer.intensity * 100))%")
                        .font(.system(size: 9, weight: .medium).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .padding(.trailing, 10)
        .padding(.vertical, 8)
    }

    // ──────────────────────────────────────────
    // MARK: Bottom Bar
    // 가로 컬러 행 + 액션 버튼들
    // ──────────────────────────────────────────
    private var bottomBar: some View {
        VStack(spacing: 10) {
            // 가로 컬러 팔레트 (빠른 접근)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(viewModel.selectedCategory.colorPresets.indices, id: \.self) { i in
                        let color = viewModel.selectedCategory.colorPresets[i]
                        let selected = viewModel.isColorSelected(color)
                        Circle()
                            .fill(color)
                            .frame(width: 28, height: 28)
                            .overlay {
                                if selected {
                                    Circle().strokeBorder(.white, lineWidth: 2)
                                }
                            }
                            .scaleEffect(selected ? 1.12 : 1.0)
                            .onTapGesture { viewModel.setColor(color) }
                    }
                }
                .padding(.horizontal, 16)
            }

            // 액션 버튼 행
            HStack(spacing: 16) {
                // Reset
                Button { viewModel.reset() } label: {
                    VStack(spacing: 3) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 16))
                        Text("Reset")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 54, height: 44)
                }

                // Before / After
                Button { viewModel.toggleBeforeAfter() } label: {
                    VStack(spacing: 3) {
                        Image(systemName: viewModel.isBeforeMode ? "eye.fill" : "eye.slash.fill")
                            .font(.system(size: 16))
                        Text(viewModel.isBeforeMode ? "After" : "Before")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .foregroundStyle(viewModel.isBeforeMode ? Color.accentColor : .white.opacity(0.8))
                    .frame(width: 54, height: 44)
                }

                // 강도 슬라이더 (가로)
                HStack(spacing: 6) {
                    Image(systemName: "circle")
                        .font(.system(size: 7))
                        .foregroundStyle(.white.opacity(0.4))
                    Slider(
                        value: Binding(
                            get: { viewModel.currentLayer.intensity },
                            set: { viewModel.setIntensity($0) }
                        ),
                        in: 0.0...1.0
                    )
                    .tint(viewModel.currentLayer.selectedColor)
                    Image(systemName: "circle.fill")
                        .font(.system(size: 7))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .frame(maxWidth: .infinity)

                // 레이어 On/Off
                Toggle("", isOn: Binding(
                    get: { viewModel.currentLayer.isEnabled },
                    set: { viewModel.setEnabled($0) }
                ))
                .labelsHidden()
                .scaleEffect(0.75)

                // 캡처
                Button { viewModel.capturePhoto() } label: {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.accentColor, in: Circle())
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 10)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .padding(.horizontal, 8)
    }
}

// ============================================================
// MARK: - FaceSceneContainer (UIViewRepresentable)
// 3-point 스튜디오 라이팅 + PBR skin material + 커스텀 카메라 제어
// ============================================================
struct FaceSceneContainer: UIViewRepresentable {
    @ObservedObject var viewModel: FaceEditorViewModel

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView(frame: .zero)
        scnView.antialiasingMode = .multisampling4X
        scnView.backgroundColor = UIColor(red: 0.08, green: 0.08, blue: 0.12, alpha: 1)
        scnView.autoenablesDefaultLighting = false
        scnView.allowsCameraControl = false
        scnView.preferredFramesPerSecond = 60

        let scene = SCNScene()
        let center = viewModel.scanData.meshCenter
        let radius = viewModel.scanData.meshRadius

        // ── 얼굴 Mesh 노드 ──
        let geometry = viewModel.scanData.buildGeometry()
        let material = Self.buildSkinMaterial(texture: viewModel.scanData.faceTexture)
        geometry.materials = [material]

        let faceNode = SCNNode(geometry: geometry)
        scene.rootNode.addChildNode(faceNode)
        viewModel.faceNode = faceNode

        // ── 안구 배치 ──
        Self.addEyeballs(to: scene, scanData: viewModel.scanData)

        // ── 3-Point 스튜디오 라이팅 ──
        Self.addStudioLighting(to: scene, center: center, radius: radius)

        // ── 카메라 ──
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.fieldOfView = 42        // 넓은 FOV → 얼굴이 화면 일부만 차지
        cameraNode.camera?.zNear = 0.001
        cameraNode.camera?.zFar = 10
        let camDist = radius * 5.0                // 충분히 뒤로 → 얼굴이 작게 + 여백 확보
        cameraNode.position = SCNVector3(center.x, center.y + radius * 0.1, center.z + camDist)
        cameraNode.look(at: SCNVector3(center.x, center.y, center.z))
        scene.rootNode.addChildNode(cameraNode)

        scnView.scene = scene
        scnView.pointOfView = cameraNode

        viewModel.scnView = scnView
        viewModel.cameraNode = cameraNode
        viewModel.initialCameraPosition = cameraNode.position
        viewModel.orbitTarget = SCNVector3(center.x, center.y, center.z)

        // ── 제스처 등록 ──
        let panGesture = UIPanGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        let pinchGesture = UIPinchGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        scnView.addGestureRecognizer(panGesture)
        scnView.addGestureRecognizer(pinchGesture)

        return scnView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        viewModel.applyMakeupTexture()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    // ──────────────────────────────────────────
    // MARK: PBR Skin Material
    // ──────────────────────────────────────────
    static func buildSkinMaterial(texture: UIImage?) -> SCNMaterial {
        let mat = SCNMaterial()
        // Blinn은 HDR 환경맵 없이도 부드럽고 자연스러운 피부 질감 표현
        mat.lightingModel = .blinn
        mat.isDoubleSided = true

        let skinFallback = UIColor(red: 0.88, green: 0.76, blue: 0.66, alpha: 1)
        mat.diffuse.contents  = texture ?? skinFallback
        mat.diffuse.wrapS = .clamp
        mat.diffuse.wrapT = .clamp
        mat.diffuse.intensity = 1.0

        // 피부 하이라이트: 약한 스페큘러
        mat.specular.contents = UIColor(white: 0.25, alpha: 1)
        mat.shininess         = 18.0

        // 앰비언트: 어두운 곳 채움
        mat.ambient.contents  = UIColor(red: 0.55, green: 0.45, blue: 0.40, alpha: 1)
        mat.ambient.intensity = 0.4

        // 깊이 쓰기 명시적 활성화 → 헤드 구체가 페이스 메시를 침범하지 않도록
        mat.writesToDepthBuffer = true
        mat.readsFromDepthBuffer = true

        return mat
    }

    // ──────────────────────────────────────────
    // MARK: 안구 배치
    //
    // face mesh 정점 기반 눈 구멍 중심 위치에 안구 구체 배치
    // 홍채 색상은 촬영 시 카메라 이미지에서 샘플링한 실제 색상 사용
    // ──────────────────────────────────────────
    static func addEyeballs(to scene: SCNScene, scanData: FaceScanData) {
        let eyes: [(SIMD3<Float>?, Float, UIColor)] = [
            (scanData.leftEyePosition,  scanData.leftEyeHoleRadius,  scanData.leftIrisColor),
            (scanData.rightEyePosition, scanData.rightEyeHoleRadius, scanData.rightIrisColor)
        ]
        for (position, holeRadius, irisColor) in eyes {
            guard let pos = position else { continue }
            let eyeNode = makeEyeballNode(irisColor: irisColor, holeRadius: holeRadius)
            eyeNode.simdPosition = pos
            scene.rootNode.addChildNode(eyeNode)
        }
    }

    static func makeEyeballNode(irisColor: UIColor, holeRadius: Float = 0.011) -> SCNNode {
        let eyeNode = SCNNode()
        // 안구 반경 = 눈 구멍 반경과 동일하게 맞춤 (눈 구멍에 꼭 맞는 크기)
        let eyeRadius = CGFloat(holeRadius)

        // ── 공막 (흰자) ──
        let sclera = SCNSphere(radius: eyeRadius)
        let scleraMat = SCNMaterial()
        scleraMat.lightingModel = .blinn
        scleraMat.diffuse.contents  = UIColor(white: 0.97, alpha: 1)
        scleraMat.specular.contents = UIColor(white: 0.7, alpha: 1)
        scleraMat.shininess = 55
        scleraMat.writesToDepthBuffer   = true
        scleraMat.readsFromDepthBuffer  = true
        sclera.materials = [scleraMat]
        eyeNode.addChildNode(SCNNode(geometry: sclera))

        // ── 홍채 + 동공 디스크 ──
        // 홍채 반경 = 안구 반경의 55% (실제 비율)
        let irisRadius = eyeRadius * 0.55
        let irisDisk = SCNCylinder(radius: irisRadius, height: 0.0001)
        let irisMat = SCNMaterial()
        irisMat.lightingModel = .blinn
        irisMat.diffuse.contents = makeEyeTexture(irisColor: irisColor)
        irisMat.isDoubleSided = false
        irisMat.writesToDepthBuffer  = true
        irisMat.readsFromDepthBuffer = true
        irisDisk.materials = [irisMat]

        let irisNode = SCNNode(geometry: irisDisk)
        // SCNCylinder 기본 축 = Y → X축으로 90° 회전하면 면이 +Z를 향함
        irisNode.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
        // 공막 앞 표면에 살짝 돌출
        irisNode.simdPosition = SIMD3(0, 0, Float(eyeRadius) * 0.97)
        eyeNode.addChildNode(irisNode)

        return eyeNode
    }

    // ── 홍채/동공 텍스처 생성 ──
    // 동심원: 홍채(sampled color) + 동공(검정) + 하이라이트(흰점)
    static func makeEyeTexture(irisColor: UIColor) -> UIImage {
        let size = CGSize(width: 256, height: 256)
        return UIGraphicsImageRenderer(size: size).image { _ in
            let c = CGPoint(x: 128, y: 128)
            let r: CGFloat = 128

            // 홍채
            irisColor.setFill()
            UIBezierPath(arcCenter: c, radius: r, startAngle: 0, endAngle: .pi * 2, clockwise: true).fill()

            // 홍채 방사형 결 (미세 어두운 선)
            var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            irisColor.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
            let darkIris = UIColor(hue: h, saturation: min(1, s * 1.3), brightness: b * 0.65, alpha: 0.45)
            for i in 0..<20 {
                let angle = CGFloat(i) * .pi / 10
                let path = UIBezierPath()
                path.move(to: CGPoint(x: c.x + cos(angle) * r * 0.32, y: c.y + sin(angle) * r * 0.32))
                path.addLine(to: CGPoint(x: c.x + cos(angle) * r, y: c.y + sin(angle) * r))
                path.lineWidth = 1.2
                darkIris.setStroke()
                path.stroke()
            }

            // 동공
            UIColor.black.setFill()
            UIBezierPath(arcCenter: c, radius: r * 0.36, startAngle: 0, endAngle: .pi * 2, clockwise: true).fill()

            // 각막 하이라이트
            UIColor.white.withAlphaComponent(0.55).setFill()
            UIBezierPath(arcCenter: CGPoint(x: 150, y: 106), radius: 15,
                         startAngle: 0, endAngle: .pi * 2, clockwise: true).fill()
        }
    }

    // ──────────────────────────────────────────
    // MARK: 3-Point Studio Lighting
    // ──────────────────────────────────────────
    static func addStudioLighting(to scene: SCNScene, center: SIMD3<Float>, radius: Float) {
        let d = radius * 4

        let keyNode = SCNNode()
        keyNode.light = SCNLight()
        keyNode.light?.type = .directional
        keyNode.light?.intensity = 900
        keyNode.light?.color = UIColor(white: 1.0, alpha: 1)
        keyNode.light?.castsShadow = true
        keyNode.light?.shadowRadius = 4
        keyNode.light?.shadowSampleCount = 8
        keyNode.position = SCNVector3(center.x + d * 0.7, center.y + d * 0.5, center.z + d)
        keyNode.look(at: SCNVector3(center.x, center.y, center.z))
        scene.rootNode.addChildNode(keyNode)

        let fillNode = SCNNode()
        fillNode.light = SCNLight()
        fillNode.light?.type = .directional
        fillNode.light?.intensity = 400
        fillNode.light?.color = UIColor(red: 0.95, green: 0.95, blue: 1.0, alpha: 1)
        fillNode.position = SCNVector3(center.x - d * 0.6, center.y - d * 0.2, center.z + d * 0.8)
        fillNode.look(at: SCNVector3(center.x, center.y, center.z))
        scene.rootNode.addChildNode(fillNode)

        let rimNode = SCNNode()
        rimNode.light = SCNLight()
        rimNode.light?.type = .directional
        rimNode.light?.intensity = 500
        rimNode.light?.color = UIColor(red: 0.90, green: 0.92, blue: 1.0, alpha: 1)
        rimNode.position = SCNVector3(center.x, center.y + d * 0.3, center.z - d)
        rimNode.look(at: SCNVector3(center.x, center.y, center.z))
        scene.rootNode.addChildNode(rimNode)

        let ambientNode = SCNNode()
        ambientNode.light = SCNLight()
        ambientNode.light?.type = .ambient
        ambientNode.light?.intensity = 250
        ambientNode.light?.color = UIColor(red: 0.90, green: 0.85, blue: 0.82, alpha: 1)
        scene.rootNode.addChildNode(ambientNode)
    }

    // ──────────────────────────────────────────
    // MARK: Gesture Coordinator
    // ──────────────────────────────────────────
    class Coordinator: NSObject {
        let viewModel: FaceEditorViewModel
        private var lastPanPoint: CGPoint = .zero
        private var lastPinchScale: CGFloat = 1

        init(viewModel: FaceEditorViewModel) {
            self.viewModel = viewModel
        }

        @MainActor
        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let cameraNode = viewModel.cameraNode else { return }
            let translation = gesture.translation(in: gesture.view)

            switch gesture.state {
            case .began:
                lastPanPoint = .zero
            case .changed:
                let dx = Float(translation.x - lastPanPoint.x) * 0.005
                lastPanPoint = translation

                // Y축(좌우) 회전만 허용 — 상하(X축) 회전 없음
                viewModel.orbitAngleY += dx
                viewModel.orbitAngleX = 0   // 항상 수평 고정

                updateCameraOrbit(cameraNode)
            default:
                break
            }
        }

        @MainActor
        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            guard let cameraNode = viewModel.cameraNode else { return }

            switch gesture.state {
            case .began:
                lastPinchScale = 1
            case .changed:
                let delta = Float(gesture.scale / lastPinchScale)
                lastPinchScale = gesture.scale

                viewModel.orbitDistance /= delta
                let minDist = viewModel.scanData.meshRadius * 3.0
                let maxDist = viewModel.scanData.meshRadius * 8.0
                viewModel.orbitDistance = max(minDist, min(maxDist, viewModel.orbitDistance))

                updateCameraOrbit(cameraNode)
            default:
                break
            }
        }

        @MainActor
        private func updateCameraOrbit(_ cameraNode: SCNNode) {
            let target = viewModel.orbitTarget
            let dist = viewModel.orbitDistance
            let ax = viewModel.orbitAngleX
            let ay = viewModel.orbitAngleY

            let x = target.x + dist * sin(ay) * cos(ax)
            let y = target.y + dist * sin(ax)
            let z = target.z + dist * cos(ay) * cos(ax)

            cameraNode.position = SCNVector3(x, y, z)
            cameraNode.look(at: target)
        }
    }
}

// ============================================================
// MARK: - FaceEditorViewModel
// 3D 뷰어 상태 + orbit 카메라 + 메이크업 합성
// ============================================================
@MainActor
class FaceEditorViewModel: ObservableObject {
    let scanData: FaceScanData

    // MARK: Published State
    @Published var selectedCategory: MakeupCategory = .lip
    @Published var layers: [MakeupCategory: MakeupLayerState] = {
        Dictionary(uniqueKeysWithValues: MakeupCategory.allCases.map {
            ($0, MakeupLayerState(category: $0))
        })
    }()
    @Published var isBeforeMode = false
    @Published var showCaptureFlash = false

    // MARK: Scene References
    weak var faceNode: SCNNode?
    weak var cameraNode: SCNNode?
    weak var scnView: SCNView?

    // MARK: Orbit Camera State
    var orbitAngleX: Float = 0
    var orbitAngleY: Float = 0
    var orbitDistance: Float = 0
    var orbitTarget: SCNVector3 = SCNVector3Zero
    var initialCameraPosition: SCNVector3 = SCNVector3Zero

    init(scanData: FaceScanData) {
        self.scanData = scanData
        self.orbitDistance = scanData.meshRadius * 5.0
    }

    // MARK: Computed
    var currentLayer: MakeupLayerState {
        layers[selectedCategory] ?? MakeupLayerState(category: selectedCategory)
    }

    func isColorSelected(_ color: Color) -> Bool {
        guard let stored = layers[selectedCategory] else { return false }
        return UIColor(stored.selectedColor).isApproximatelyEqual(to: UIColor(color))
    }

    // MARK: Actions
    func setColor(_ color: Color) {
        layers[selectedCategory]?.selectedColor = color
        applyMakeupTexture()
    }

    func setIntensity(_ intensity: Double) {
        layers[selectedCategory]?.intensity = intensity
        applyMakeupTexture()
    }

    func setBrushSize(_ size: Double) {
        layers[selectedCategory]?.brushSize = size
        applyMakeupTexture()
    }

    func setEnabled(_ enabled: Bool) {
        layers[selectedCategory]?.isEnabled = enabled
        applyMakeupTexture()
    }

    func toggleBeforeAfter() {
        isBeforeMode.toggle()
        applyMakeupTexture()
    }

    func reset() {
        for cat in MakeupCategory.allCases {
            layers[cat] = MakeupLayerState(category: cat)
        }
        applyMakeupTexture()
    }

    func resetCamera() {
        guard let cameraNode = cameraNode else { return }

        orbitAngleX = 0
        orbitAngleY = 0
        orbitDistance = scanData.meshRadius * 5.0

        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.4
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        cameraNode.position = initialCameraPosition
        cameraNode.look(at: orbitTarget)
        SCNTransaction.commit()
    }

    // ──────────────────────────────────────────
    // MARK: 메이크업 텍스처 합성
    // ──────────────────────────────────────────
    func applyMakeupTexture() {
        guard let faceNode = faceNode else { return }
        let skinFallback = UIColor(red: 0.87, green: 0.75, blue: 0.65, alpha: 1)

        if isBeforeMode {
            faceNode.geometry?.firstMaterial?.diffuse.contents =
                scanData.faceTexture ?? skinFallback
            return
        }

        let makeupOverlay = MakeupTextureRenderer.render(layers: Array(layers.values))
        let composited = compositeTexture(base: scanData.faceTexture, overlay: makeupOverlay)

        faceNode.geometry?.firstMaterial?.diffuse.contents =
            composited ?? scanData.faceTexture ?? skinFallback
    }

    private func compositeTexture(base: UIImage?, overlay: UIImage?) -> UIImage? {
        guard overlay != nil else { return base }
        let size = CGSize(width: 1024, height: 1024)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            if let base = base {
                base.draw(in: CGRect(origin: .zero, size: size))
            } else {
                UIColor(red: 0.87, green: 0.75, blue: 0.65, alpha: 1).setFill()
                UIBezierPath(rect: CGRect(origin: .zero, size: size)).fill()
            }
            overlay?.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    // MARK: Capture
    func capturePhoto() {
        guard let scnView = scnView else { return }
        let image = scnView.snapshot()

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
}
