import SwiftUI
import SceneKit
import Photos

// ============================================================
// MARK: - Face3DEditorView
// 레이아웃: 좌측 메이크업 툴 / 중앙 3D / 우측 브러시 타입 / 하단 컨트롤 패널
// ============================================================
struct Face3DEditorView: View {
    let scanData: FaceScanData
    @EnvironmentObject var router: AppRouter
    @StateObject private var viewModel: FaceEditorViewModel
    @State private var showColorPicker = false
    @State private var customColor: Color = .red

    private let accent = Color(red: 0.93, green: 0.28, blue: 0.48)

    init(scanData: FaceScanData) {
        self.scanData = scanData
        _viewModel = StateObject(wrappedValue: FaceEditorViewModel(scanData: scanData))
    }

    var body: some View {
        ZStack {
            Color(white: 0.08).ignoresSafeArea()
            FaceSceneContainer(viewModel: viewModel).ignoresSafeArea()

            if viewModel.isBeforeMode {
                VStack {
                    Text("BEFORE")
                        .font(.caption.bold()).foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 5)
                        .background(.black.opacity(0.65), in: Capsule())
                        .padding(.top, 70)
                    Spacer()
                }
            }

            if viewModel.showCaptureFlash {
                Color.white.ignoresSafeArea().opacity(0.75)
                    .allowsHitTesting(false).transition(.opacity)
            }

            VStack(spacing: 0) {
                topBar.padding(.top, 56)

                HStack(alignment: .top, spacing: 0) {
                    leftToolSidebar
                    Spacer()
                    rightProductSidebar
                }
                .padding(.top, 6)

                Spacer()
                bottomPanel
            }
        }
        .sheet(isPresented: $showColorPicker) { colorPickerSheet }
        .animation(.easeInOut(duration: 0.15), value: viewModel.showCaptureFlash)
        .animation(.easeInOut(duration: 0.2),  value: viewModel.isBeforeMode)
        .animation(.spring(response: 0.28),    value: viewModel.selectedTool)
        .animation(.spring(response: 0.28),    value: viewModel.selectedRegion)
        .animation(.spring(response: 0.28),    value: viewModel.interactionMode)
    }

    // ── Top Bar ──
    private var topBar: some View {
        HStack(spacing: 8) {
            Button { router.goTo(.inputMethod) } label: { iconButton("chevron.left") }
            Spacer()
            Text("3D Makeup Editor")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
            Spacer()
            Button { viewModel.resetCamera() } label: { iconButton("arrow.triangle.2.circlepath.camera") }
            Button { viewModel.capturePhoto()  } label: { iconButton("square.and.arrow.up") }
        }
        .padding(.horizontal, 12)
    }

    private func iconButton(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white.opacity(0.85))
            .frame(width: 30, height: 30)
            .background(Color.white.opacity(0.10), in: Circle())
    }

    // ── Left Sidebar: Face Regions ──
    private var leftToolSidebar: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 2) {
                ForEach(FaceRegion.allCases) { region in
                    regionCell(region)
                }
            }
            .padding(.vertical, 5)
        }
        .frame(width: 54)
        .background(sidebarBG)
    }

    private func regionCell(_ region: FaceRegion) -> some View {
        let isSelected = viewModel.selectedRegion == region
        return Button {
            viewModel.selectedRegion = region
            viewModel.selectedTool = nil
        } label: {
            VStack(spacing: 3) {
                Image(systemName: region.icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(isSelected ? accent : .white.opacity(0.50))
                    .frame(height: 18)
                Text(region.rawValue)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(isSelected ? accent : .white.opacity(0.38))
                    .lineLimit(1)
            }
            .frame(width: 46, height: 46)
            .background(cellBG(isSelected))
        }
    }

    // ── Right Sidebar: Rotate + Region Products ──
    private var rightProductSidebar: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 2) {
                // 회전 버튼 (맨 위)
                rotateHandCell

                // 구분선
                Rectangle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 30, height: 1)
                    .padding(.vertical, 2)

                // 선택된 부위에 해당하는 도구
                ForEach(viewModel.selectedRegion.tools) { tool in
                    toolPickerCell(tool)
                }
            }
            .padding(.vertical, 5)
        }
        .frame(width: 54)
        .background(sidebarBG)
    }

    private var rotateHandCell: some View {
        let isSelected = viewModel.interactionMode == .rotate
        return Button {
            viewModel.interactionMode = .rotate
            viewModel.selectedTool = nil
        } label: {
            VStack(spacing: 3) {
                RotateHandIcon(isSelected: isSelected, accent: accent)
                    .frame(width: 22, height: 22)
                Text("ROTATE")
                    .font(.system(size: 6, weight: .bold))
                    .foregroundStyle(isSelected ? accent : .white.opacity(0.38))
                    .lineLimit(1)
            }
            .frame(width: 46, height: 46)
            .background(cellBG(isSelected))
        }
    }

    private func toolPickerCell(_ tool: MakeupTool) -> some View {
        let isSelected = viewModel.selectedTool == tool
        return Button {
            viewModel.selectedTool = tool
            viewModel.interactionMode = .paint
        } label: {
            VStack(spacing: 3) {
                Image(systemName: tool.icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(isSelected ? accent : .white.opacity(0.50))
                    .frame(height: 18)
                Text(tool.shortLabel)
                    .font(.system(size: 5.5, weight: .bold))
                    .foregroundStyle(isSelected ? accent : .white.opacity(0.38))
                    .lineLimit(2).minimumScaleFactor(0.7)
                    .multilineTextAlignment(.center)
            }
            .frame(width: 46, height: 50)
            .background(cellBG(isSelected))
        }
    }

    private func cellBG(_ isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(isSelected ? accent.opacity(0.14) : Color.white.opacity(0.04))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? accent.opacity(0.55) : .clear, lineWidth: 1)
            )
    }

    private var sidebarBG: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color(white: 0.10).opacity(0.88))
    }

    // ── Bottom Panel ──
    private var bottomPanel: some View {
        VStack(spacing: 0) {
            if let tool = viewModel.selectedTool {
                // Color Palette
                HStack(spacing: 8) {
                    Text("Color")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.70))

                    Button { showColorPicker = true } label: {
                        Circle()
                            .fill(AngularGradient(
                                colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red],
                                center: .center))
                            .frame(width: 26, height: 26)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(tool.colorPresets.indices, id: \.self) { i in
                                let color = tool.colorPresets[i]
                                let sel = viewModel.isColorSelected(color)
                                Circle().fill(color)
                                    .frame(width: 26, height: 26)
                                    .overlay { if sel { Circle().strokeBorder(.white, lineWidth: 2) } }
                                    .scaleEffect(sel ? 1.10 : 1)
                                    .animation(.spring(response: 0.2), value: sel)
                                    .onTapGesture { viewModel.setColor(color) }
                            }
                        }
                    }

                    Button { showColorPicker = true } label: {
                        ZStack {
                            Circle().fill(Color.white.opacity(0.09))
                                .overlay(Circle().strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
                                .frame(width: 26, height: 26)
                            Image(systemName: "plus").font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.60))
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)

                // 슬라이더 2개
                VStack(spacing: 6) {
                    sliderRow(icon: "paintbrush.pointed.fill", label: "Brush Size",
                              value: Binding(get: { viewModel.currentToolState.brushSize },
                                             set: { viewModel.setBrushSize($0) }),
                              display: "\(Int(viewModel.currentToolState.brushSize * 100))px")

                    sliderRow(icon: "drop.fill", label: "Opacity",
                              value: Binding(get: { viewModel.currentToolState.intensity },
                                             set: { viewModel.setIntensity($0) }),
                              display: "\(Int(viewModel.currentToolState.intensity * 100))%")
                }
                .padding(.top, 8)
            } else {
                // 제품 미선택 안내
                HStack(spacing: 8) {
                    Image(systemName: "hand.point.right")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.28))
                    Text("오른쪽에서 제품을 선택하세요")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.35))
                }
                .frame(height: 76)
            }

            // 액션 바 (항상 표시)
            actionBar
                .padding(.top, 10)
                .padding(.bottom, 32)
        }
        .background(EditorBottomBackground())
    }

    private func sliderRow(icon: String, label: String, value: Binding<Double>, display: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.50))
                .frame(width: 14)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))
                .frame(width: 62, alignment: .leading)
            Slider(value: value, in: 0...1).tint(accent)
            Text(display)
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.50))
                .frame(width: 34, alignment: .trailing)
        }
        .padding(.horizontal, 14)
    }

    private var actionBar: some View {
        HStack(spacing: 0) {
            Button { viewModel.reset() } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.counterclockwise").font(.system(size: 11, weight: .semibold))
                    Text("Reset").font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.white.opacity(0.75))
                .frame(height: 38)
                .padding(.horizontal, 14)
                .background(Color.white.opacity(0.08), in: Capsule())
            }

            Spacer()

            HStack(spacing: 0) {
                beforeAfterButton(title: "Before", isActive: viewModel.isBeforeMode) {
                    if !viewModel.isBeforeMode { viewModel.toggleBeforeAfter() }
                }
                beforeAfterButton(title: "After", isActive: !viewModel.isBeforeMode) {
                    if viewModel.isBeforeMode { viewModel.toggleBeforeAfter() }
                }
            }
            .padding(2)
            .background(Color.white.opacity(0.09), in: Capsule())

            Spacer()

            Button { viewModel.capturePhoto() } label: {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .bold))
                    Text("Apply").font(.system(size: 13, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(height: 38)
                .padding(.horizontal, 16)
                .background(accent, in: Capsule())
            }
        }
        .padding(.horizontal, 14)
    }

    private func beforeAfterButton(title: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isActive ? Color(white: 0.10) : .white.opacity(0.45))
                .frame(width: 56, height: 30)
                .background(isActive ? .white : .clear, in: Capsule())
        }
    }

    // 커스텀 색상 피커 시트
    private var colorPickerSheet: some View {
        NavigationStack {
            VStack(spacing: 24) {
                ColorPicker("", selection: $customColor, supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 280, height: 280)
                Button("적용하기") {
                    viewModel.setColor(customColor)
                    showColorPicker = false
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
            }
            .padding()
            .navigationTitle("커스텀 색상")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { showColorPicker = false }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// ============================================================
// MARK: - RotateHandIcon
// Canvas로 그린 회전 아이콘 (오빗 모드 버튼용)
// ============================================================
private struct RotateHandIcon: View {
    let isSelected: Bool
    let accent: Color

    private var col: Color { isSelected ? accent : Color(white: 0.60) }

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let cx = w * 0.5, cy = h * 0.5
            let r = w * 0.36

            // 원형 화살표 호 (약 300°)
            var arc = Path()
            arc.addArc(center: CGPoint(x: cx, y: cy), radius: r,
                       startAngle: .degrees(130), endAngle: .degrees(50), clockwise: false)
            ctx.stroke(arc, with: .color(col), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))

            // 화살표 머리 (호 끝 부분)
            let headAngle: CGFloat = 50 * .pi / 180
            let hx = cx + r * cos(headAngle)
            let hy = cy + r * sin(headAngle)
            var head = Path()
            head.move(to: CGPoint(x: hx - 4, y: hy - 3))
            head.addLine(to: CGPoint(x: hx + 2, y: hy + 1))
            head.addLine(to: CGPoint(x: hx - 1, y: hy + 4))
            ctx.fill(head, with: .color(col))
        }
    }
}

// ============================================================
// MARK: - BrushToolIcon
// Canvas로 직접 그린 메이크업 브러시 일러스트 아이콘
// 참조: 둥근 파우더 / 포인트 세부 / 팬 / 뷰티블렌더 / 플랫앵글 / 퍼프
// ============================================================
private struct BrushToolIcon: View {
    let type: BrushType
    let isSelected: Bool
    let accent: Color

    /// 선택 여부에 따라 모(毛) 색상 결정
    private var bristle: Color {
        isSelected ? accent : Color(red: 0.88, green: 0.80, blue: 0.70)
    }
    private let gold   = Color(red: 0.80, green: 0.68, blue: 0.36)
    private let dark   = Color(white: 0.16)

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height

            // 공용 헬퍼: 둥근 사각형 Path
            func rr(_ x: CGFloat, _ y: CGFloat,
                    _ bw: CGFloat, _ bh: CGFloat, _ r: CGFloat) -> Path {
                Path(roundedRect: CGRect(x: x, y: y, width: bw, height: bh),
                     cornerRadius: r)
            }

            switch type {

            // ── Round powder brush ──
            // 둥근 돔 헤드 + 금 페룰 + 검정 핸들
            case .brush:
                // 브리슬 도움(dome)
                ctx.fill(
                    Path(ellipseIn: CGRect(x: w*0.05, y: 0, width: w*0.90, height: h*0.44)),
                    with: .color(bristle)
                )
                // 광택 하이라이트
                ctx.fill(
                    Path(ellipseIn: CGRect(x: w*0.18, y: h*0.03, width: w*0.28, height: h*0.11)),
                    with: .color(.white.opacity(0.28))
                )
                // 페룰 (금)
                ctx.fill(rr(w*0.29, h*0.42, w*0.42, h*0.08, 2), with: .color(gold))
                // 핸들
                ctx.fill(rr(w*0.36, h*0.49, w*0.28, h*0.51, 3), with: .color(dark))

            // ── Detail pencil brush ──
            // 얇은 포인트 팁 + 핸들
            case .pencil:
                var tip = Path()
                tip.move(to: CGPoint(x: w*0.50, y: 0))
                tip.addCurve(to: CGPoint(x: w*0.50, y: h*0.20),
                             control1: CGPoint(x: w*0.26, y: h*0.08),
                             control2: CGPoint(x: w*0.26, y: h*0.18))
                tip.addCurve(to: CGPoint(x: w*0.50, y: 0),
                             control1: CGPoint(x: w*0.74, y: h*0.18),
                             control2: CGPoint(x: w*0.74, y: h*0.08))
                ctx.fill(tip, with: .color(bristle))
                ctx.fill(rr(w*0.32, h*0.18, w*0.36, h*0.08, 2), with: .color(gold))
                ctx.fill(rr(w*0.36, h*0.25, w*0.28, h*0.75, 3), with: .color(dark))

            // ── Fan brush ──
            // 부채꼴로 펼쳐진 브리슬
            case .airbrush:
                var fan = Path()
                fan.move(to: CGPoint(x: w*0.50, y: h*0.38))
                fan.addLine(to: CGPoint(x: 0, y: 0))
                fan.addQuadCurve(to: CGPoint(x: w, y: 0),
                                 control: CGPoint(x: w*0.50, y: h*0.14))
                fan.closeSubpath()
                ctx.fill(fan, with: .color(bristle.opacity(0.90)))
                // 브리슬 결(세선)
                for i in 1..<6 {
                    let t = CGFloat(i) / 6.0
                    var line = Path()
                    line.move(to: CGPoint(x: w*0.50, y: h*0.38))
                    line.addLine(to: CGPoint(x: w*t, y: 0))
                    ctx.stroke(line, with: .color(.white.opacity(0.12)), lineWidth: 0.5)
                }
                ctx.fill(rr(w*0.29, h*0.36, w*0.42, h*0.08, 2), with: .color(gold))
                ctx.fill(rr(w*0.36, h*0.43, w*0.28, h*0.57, 3), with: .color(dark))

            // ── Beauty blender sponge ──
            // 달걀형 스폰지, 핸들 없음
            case .sponge:
                // 달걀 실루엣 (아래가 더 둥글게)
                var egg = Path()
                egg.addEllipse(in: CGRect(x: w*0.08, y: h*0.04, width: w*0.84, height: h*0.92))
                ctx.fill(egg, with: .color(bristle.opacity(0.90)))
                // 상단 광택
                ctx.fill(
                    Path(ellipseIn: CGRect(x: w*0.26, y: h*0.10, width: w*0.28, height: h*0.14)),
                    with: .color(.white.opacity(0.32))
                )
                // 중간 솔기선
                var seam = Path()
                seam.addEllipse(in: CGRect(x: w*0.14, y: h*0.46, width: w*0.72, height: h*0.10))
                ctx.stroke(seam, with: .color(.white.opacity(0.20)), lineWidth: 0.8)

            // ── Flat angled brush ──
            // 각진 플랫 헤드 (아이섀도/쉐딩 용)
            case .smudge:
                var head = Path()
                head.move(to: CGPoint(x: w*0.06, y: h*0.14))
                head.addLine(to: CGPoint(x: w*0.94, y: h*0.04))
                head.addLine(to: CGPoint(x: w*0.94, y: h*0.34))
                head.addLine(to: CGPoint(x: w*0.06, y: h*0.34))
                head.closeSubpath()
                ctx.fill(head, with: .color(bristle))
                // 브리슬 결
                for i in 1..<5 {
                    let x = w * (0.20 + CGFloat(i) * 0.15)
                    var line = Path()
                    line.move(to: CGPoint(x: x, y: h*0.06))
                    line.addLine(to: CGPoint(x: x, y: h*0.32))
                    ctx.stroke(line, with: .color(.white.opacity(0.12)), lineWidth: 0.5)
                }
                ctx.fill(rr(w*0.29, h*0.33, w*0.42, h*0.08, 2), with: .color(gold))
                ctx.fill(rr(w*0.36, h*0.40, w*0.28, h*0.60, 3), with: .color(dark))

            // ── Powder puff ──
            // 둥근 퍼프 + 리본 장식
            case .layer:
                ctx.fill(
                    Path(ellipseIn: CGRect(x: 0, y: 0, width: w, height: h*0.86)),
                    with: .color(bristle.opacity(0.88))
                )
                ctx.fill(
                    Path(ellipseIn: CGRect(x: w*0.20, y: h*0.08, width: w*0.30, height: h*0.14)),
                    with: .color(.white.opacity(0.26))
                )
                // 리본 왼쪽
                ctx.fill(
                    Path(ellipseIn: CGRect(x: w*0.15, y: h*0.36, width: w*0.30, height: h*0.14)),
                    with: .color(.white.opacity(0.40))
                )
                // 리본 오른쪽
                ctx.fill(
                    Path(ellipseIn: CGRect(x: w*0.55, y: h*0.36, width: w*0.30, height: h*0.14)),
                    with: .color(.white.opacity(0.40))
                )
                // 리본 중앙 매듭
                ctx.fill(
                    Path(ellipseIn: CGRect(x: w*0.42, y: h*0.39, width: w*0.16, height: h*0.08)),
                    with: .color(.white.opacity(0.65))
                )
            }
        }
        .frame(width: 30, height: 40)
    }
}

// ── 하단 패널 배경 (상단 모서리만 라운드) ──
private struct EditorBottomBackground: View {
    var body: some View {
        Color(white: 0.10)
            .clipShape(UnevenRoundedRectangle(
                topLeadingRadius: 28, bottomLeadingRadius: 0,
                bottomTrailingRadius: 0, topTrailingRadius: 28,
                style: .continuous
            ))
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
        let eyes: [(SIMD3<Float>?, Float, Float, UIColor, String)] = [
            (scanData.leftEyePosition,  scanData.leftEyeHoleRadius,  scanData.leftIrisRadius,  scanData.leftIrisColor,  "eye_left"),
            (scanData.rightEyePosition, scanData.rightEyeHoleRadius, scanData.rightIrisRadius, scanData.rightIrisColor, "eye_right")
        ]
        for (position, holeRadius, irisRadius, irisColor, name) in eyes {
            guard let pos = position else { continue }
            let eyeNode = makeEyeballNode(irisColor: irisColor, holeRadius: holeRadius, irisRadius: irisRadius)
            eyeNode.name = name
            eyeNode.simdPosition = pos
            scene.rootNode.addChildNode(eyeNode)
        }
    }

    static func makeEyeballNode(irisColor: UIColor, holeRadius: Float = 0.011, irisRadius: Float = 0.006) -> SCNNode {
        let eyeNode = SCNNode()
        let eyeRadius = CGFloat(holeRadius)

        // ── 공막 (흰자) ──
        // 따뜻한 베이지/황갈색 톤 — 순백·아이보리보다 더 낮은 채도
        let sclera = SCNSphere(radius: eyeRadius)
        let scleraMat = SCNMaterial()
        scleraMat.lightingModel = .blinn
        scleraMat.diffuse.contents  = makeScleraTexture()
        scleraMat.specular.contents = UIColor(white: 0.12, alpha: 1)   // 반사 최소화
        scleraMat.shininess         = 12
        scleraMat.ambient.contents  = UIColor(red: 0.45, green: 0.40, blue: 0.35, alpha: 1)
        scleraMat.writesToDepthBuffer  = true
        scleraMat.readsFromDepthBuffer = true
        sclera.materials = [scleraMat]
        eyeNode.addChildNode(SCNNode(geometry: sclera))

        // ── 홍채 + 동공 디스크 ──
        // 카메라 이미지 픽셀 스캔으로 측정한 실제 홍채 반경 사용 (인물별 정확한 크기)
        let irisPlaneR = CGFloat(irisRadius)
        let irisDisk = SCNPlane(width: irisPlaneR * 2, height: irisPlaneR * 2)
        let irisMat = SCNMaterial()
        irisMat.lightingModel = .blinn
        irisMat.diffuse.contents  = makeEyeTexture(irisColor: irisColor)
        irisMat.specular.contents = UIColor(white: 0.08, alpha: 1)
        irisMat.shininess         = 18
        irisMat.isDoubleSided     = true   // 뒤에서도 렌더링
        irisMat.writesToDepthBuffer  = true
        irisMat.readsFromDepthBuffer = true
        irisDisk.materials = [irisMat]

        let irisNode = SCNNode(geometry: irisDisk)
        // 공막 구체 앞면 = eyeRadius, 홍채를 1.01×로 배치해야
        // 깊이 테스트에서 항상 공막 앞에 렌더링됨 (각막 돌출 구조와도 일치)
        irisNode.simdPosition = SIMD3(0, 0, Float(eyeRadius) * 1.01)
        eyeNode.addChildNode(irisNode)

        return eyeNode
    }

    // ── 공막(흰자) 텍스처 ──
    // 순백이 아닌 따뜻한 크림색 + 미세 혈관 흔적으로 사실감 부여
    static func makeScleraTexture() -> UIImage {
        let size = CGSize(width: 256, height: 256)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let c = CGPoint(x: 128, y: 128)
            let r: CGFloat = 128

            // 기본 공막 색상: 황갈색 베이지 — 흰색과 거리를 두어 자연스러운 눈 표현
            UIColor(red: 0.78, green: 0.72, blue: 0.63, alpha: 1).setFill()
            UIBezierPath(arcCenter: c, radius: r, startAngle: 0, endAngle: .pi*2, clockwise: true).fill()

            // 미세 혈관 (가장자리 방향으로 얇은 분홍선)
            let vesselColor = UIColor(red: 0.80, green: 0.58, blue: 0.58, alpha: 0.32)
            for i in 0..<12 {
                let baseAngle = CGFloat(i) * .pi / 6
                let path = UIBezierPath()
                let startR = r * 0.55
                path.move(to: CGPoint(x: c.x + cos(baseAngle)*startR,
                                      y: c.y + sin(baseAngle)*startR))
                // 혈관은 가지치기 형태로 끝부분이 갈라짐
                let midAngle = baseAngle + CGFloat(i % 2 == 0 ? 0.06 : -0.06)
                let midR = r * 0.78
                path.addLine(to: CGPoint(x: c.x + cos(midAngle)*midR,
                                         y: c.y + sin(midAngle)*midR))
                let endAngle1 = midAngle + 0.05
                let endAngle2 = midAngle - 0.05
                path.addLine(to: CGPoint(x: c.x + cos(endAngle1)*r*0.92,
                                         y: c.y + sin(endAngle1)*r*0.92))
                path.move(to: CGPoint(x: c.x + cos(midAngle)*midR,
                                      y: c.y + sin(midAngle)*midR))
                path.addLine(to: CGPoint(x: c.x + cos(endAngle2)*r*0.88,
                                         y: c.y + sin(endAngle2)*r*0.88))
                path.lineWidth = 0.6
                vesselColor.setStroke()
                path.stroke()
            }

            // 눈꺼풀 접촉 부분 (상하 가장자리 미세 붉은기)
            let limbusColor = UIColor(red: 0.90, green: 0.82, blue: 0.82, alpha: 0.2)
            let topPath = UIBezierPath(arcCenter: c, radius: r*0.95,
                                       startAngle: .pi*1.2, endAngle: .pi*1.8, clockwise: true)
            topPath.lineWidth = r * 0.18
            limbusColor.setStroke()
            topPath.stroke()
        }
    }

    // ── 홍채/동공 텍스처 생성 ──
    // 레이어: 홍채 기본색 → 스트로마 섬유 → 크립트 → 리마링 → 동공 → 각막 하이라이트
    static func makeEyeTexture(irisColor: UIColor) -> UIImage {
        let size = CGSize(width: 512, height: 512)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let c = CGPoint(x: 256, y: 256)
            let r: CGFloat = 256

            var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            irisColor.getHue(&h, saturation: &s, brightness: &b, alpha: &a)

            // 1. 홍채 기본 배경 — 원본 밝기보다 15% 낮춰서 인물 눈빛에 자연스러운 깊이감
            let baseColor = UIColor(hue: h, saturation: min(1, s * 1.05), brightness: b * 0.72, alpha: 1)
            baseColor.setFill()
            UIBezierPath(arcCenter: c, radius: r, startAngle: 0, endAngle: .pi*2, clockwise: true).fill()

            // 외곽 어두운 링 (깊이감)
            let outerDark = UIColor(hue: h, saturation: min(1, s*1.2), brightness: b*0.45, alpha: 0.65)
            for ring in 0..<3 {
                let ringR = r * (0.82 + CGFloat(ring) * 0.06)
                let ringPath = UIBezierPath(arcCenter: c, radius: ringR,
                                            startAngle: 0, endAngle: .pi*2, clockwise: true)
                ringPath.lineWidth = r * 0.05
                outerDark.setStroke()
                ringPath.stroke()
            }

            // 2. 스트로마 섬유 (방사형 — 촘촘한 결)
            let fiberCount = 60
            for i in 0..<fiberCount {
                let angle = CGFloat(i) * .pi * 2 / CGFloat(fiberCount)
                // 홀수/짝수로 밝기 교차 → 자연스러운 결
                let alpha: CGFloat = (i % 3 == 0) ? 0.40 : 0.18
                let fiberBright: CGFloat = (i % 2 == 0) ? b * 0.42 : b * 0.88
                let fiberColor = UIColor(hue: h,
                                         saturation: (i % 2 == 0) ? min(1, s*1.3) : s*0.55,
                                         brightness: fiberBright, alpha: alpha)
                let innerR = r * 0.33
                // 섬유 길이 변화로 불규칙한 질감
                let outerR = r * (0.72 + CGFloat(i % 5) * 0.05)
                let path = UIBezierPath()
                path.move(to: CGPoint(x: c.x + cos(angle)*innerR, y: c.y + sin(angle)*innerR))
                path.addLine(to: CGPoint(x: c.x + cos(angle)*outerR, y: c.y + sin(angle)*outerR))
                path.lineWidth = (i % 4 == 0) ? 1.8 : 0.9
                fiberColor.setStroke()
                path.stroke()
            }

            // 3. 크립트 (Crypts) — 홍채 내부 불규칙 패턴 (결정적 위치)
            let cryptColor = UIColor(hue: h, saturation: s, brightness: b * 0.35, alpha: 0.45)
            let cryptAngles: [CGFloat] = [0.4, 1.1, 1.9, 2.8, 3.7, 4.5, 5.3, 6.0]
            let cryptDists: [CGFloat] = [0.52, 0.64, 0.55, 0.70, 0.58, 0.62, 0.48, 0.67]
            let cryptSizes: [CGFloat] = [0.07, 0.05, 0.08, 0.06, 0.07, 0.05, 0.06, 0.08]
            for i in 0..<cryptAngles.count {
                let px = c.x + cos(cryptAngles[i]) * r * cryptDists[i]
                let py = c.y + sin(cryptAngles[i]) * r * cryptDists[i]
                cryptColor.setFill()
                UIBezierPath(arcCenter: CGPoint(x: px, y: py), radius: r * cryptSizes[i],
                             startAngle: 0, endAngle: .pi*2, clockwise: true).fill()
            }

            // 4. 리마 링 (Limbal ring) — 홍채 가장자리 짙은 테두리 (젊고 건강한 눈 특징)
            let limbalRing = UIColor(hue: h, saturation: min(1, s*1.1), brightness: b * 0.22, alpha: 0.75)
            let limbal = UIBezierPath(arcCenter: c, radius: r * 0.90,
                                      startAngle: 0, endAngle: .pi*2, clockwise: true)
            limbal.lineWidth = r * 0.12
            limbalRing.setStroke()
            limbal.stroke()

            // 5. 동공 (Pupil) — 순수 검정
            UIColor(red: 0.04, green: 0.04, blue: 0.06, alpha: 1).setFill()
            UIBezierPath(arcCenter: c, radius: r * 0.30, startAngle: 0, endAngle: .pi*2, clockwise: true).fill()

            // 6. 동공-홍채 경계 (자연스러운 그라데이션 효과)
            let pupilEdge = UIColor(hue: h, saturation: min(1, s*1.3), brightness: b * 0.28, alpha: 0.6)
            let pe = UIBezierPath(arcCenter: c, radius: r * 0.35,
                                   startAngle: 0, endAngle: .pi*2, clockwise: true)
            pe.lineWidth = r * 0.10
            pupilEdge.setStroke()
            pe.stroke()

            // 7. 각막 반사 하이라이트 — 절제된 톤으로 자연스러운 습윤감만 표현
            UIColor.white.withAlphaComponent(0.38).setFill()
            UIBezierPath(arcCenter: CGPoint(x: c.x + r*0.16, y: c.y - r*0.20),
                         radius: r * 0.07, startAngle: 0, endAngle: .pi*2, clockwise: true).fill()
            UIColor.white.withAlphaComponent(0.15).setFill()
            UIBezierPath(arcCenter: CGPoint(x: c.x - r*0.14, y: c.y + r*0.16),
                         radius: r * 0.035, startAngle: 0, endAngle: .pi*2, clockwise: true).fill()
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
            if viewModel.interactionMode == .rotate {
                handleOrbit(gesture)
            } else {
                handlePaint(gesture)
            }
        }

        @MainActor
        private func handleOrbit(_ gesture: UIPanGestureRecognizer) {
            guard let cameraNode = viewModel.cameraNode else { return }
            let translation = gesture.translation(in: gesture.view)

            switch gesture.state {
            case .began:
                lastPanPoint = .zero
            case .changed:
                let dx = Float(translation.x - lastPanPoint.x) * 0.005
                lastPanPoint = translation

                // Y축(좌우) 회전만 허용 — ±65° 제한
                let maxAngle: Float = 65 * .pi / 180
                viewModel.orbitAngleY = max(-maxAngle, min(maxAngle, viewModel.orbitAngleY + dx))
                viewModel.orbitAngleX = 0

                updateCameraOrbit(cameraNode)
            default:
                break
            }
        }

        @MainActor
        private func handlePaint(_ gesture: UIPanGestureRecognizer) {
            guard gesture.state == .began || gesture.state == .changed else { return }
            guard let scnView = viewModel.scnView else { return }
            let location = gesture.location(in: scnView)
            let hits = scnView.hitTest(location, options: [
                SCNHitTestOption.searchMode: SCNHitTestSearchMode.closest.rawValue,
                SCNHitTestOption.backFaceCulling: true
            ])
            guard let hit = hits.first(where: { $0.node === viewModel.faceNode }) else { return }
            let uv = hit.textureCoordinates(withMappingChannel: 0)
            viewModel.paintAtUV(uv: CGPoint(x: CGFloat(uv.x), y: CGFloat(uv.y)))
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
// 3D 뷰어 상태 + orbit 카메라 + 직접 페인팅
// ============================================================
@MainActor
class FaceEditorViewModel: ObservableObject {
    let scanData: FaceScanData

    // MARK: Published State
    @Published var selectedTool: MakeupTool? = nil
    @Published var selectedRegion: FaceRegion = .full
    @Published var interactionMode: InteractionMode = .rotate
    @Published var isBeforeMode = false
    @Published var showCaptureFlash = false

    // MARK: Tool States (per-tool color/size/opacity)
    var toolStates: [MakeupTool: ToolLayerState] = [:]

    // MARK: Paint Canvas
    private var paintCanvasImage: UIImage? = nil

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
    var currentToolState: ToolLayerState {
        guard let tool = selectedTool else { return ToolLayerState(tool: .blend) }
        return toolStates[tool] ?? ToolLayerState(tool: tool)
    }

    func isColorSelected(_ color: Color) -> Bool {
        guard let tool = selectedTool, let state = toolStates[tool] else { return false }
        return UIColor(state.selectedColor).isApproximatelyEqual(to: UIColor(color))
    }

    // MARK: Actions
    func setColor(_ color: Color) {
        guard let tool = selectedTool else { return }
        if toolStates[tool] == nil { toolStates[tool] = ToolLayerState(tool: tool) }
        toolStates[tool]?.selectedColor = color
    }

    func setIntensity(_ intensity: Double) {
        guard let tool = selectedTool else { return }
        if toolStates[tool] == nil { toolStates[tool] = ToolLayerState(tool: tool) }
        toolStates[tool]?.intensity = intensity
    }

    func setBrushSize(_ size: Double) {
        guard let tool = selectedTool else { return }
        if toolStates[tool] == nil { toolStates[tool] = ToolLayerState(tool: tool) }
        toolStates[tool]?.brushSize = size
    }

    func toggleBeforeAfter() {
        isBeforeMode.toggle()
        applyMakeupTexture()
    }

    func reset() {
        toolStates.removeAll()
        paintCanvasImage = nil
        applyMakeupTexture()
    }

    func paintAtUV(uv: CGPoint) {
        guard let tool = selectedTool else { return }
        let state = toolStates[tool] ?? ToolLayerState(tool: tool)
        let brushPx = CGFloat(state.brushSize * 60 + 8)
        let pixelX = uv.x * 1024
        let pixelY = uv.y * 1024

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1; format.opaque = false
        let result = UIGraphicsImageRenderer(size: CGSize(width: 1024, height: 1024), format: format).image { ctx in
            paintCanvasImage?.draw(at: .zero)
            let rect = CGRect(x: pixelX - brushPx, y: pixelY - brushPx,
                              width: brushPx * 2, height: brushPx * 2)
            MakeupTextureRenderer.drawBrushStroke(
                ctx: ctx.cgContext, rect: rect,
                color: UIColor(state.selectedColor),
                intensity: CGFloat(state.intensity),
                maxAlpha: tool.maxAlpha,
                isHardEdge: tool.isHardEdge
            )
        }
        paintCanvasImage = result
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
    // MARK: 텍스처 적용 (페인트 캔버스만)
    // 자동 레이어 렌더링 없음 — 직접 터치로 칠한 것만 표시
    // ──────────────────────────────────────────
    func applyMakeupTexture() {
        guard let faceNode = faceNode else { return }
        let skinFallback = UIColor(red: 0.87, green: 0.75, blue: 0.65, alpha: 1)

        if isBeforeMode {
            faceNode.geometry?.firstMaterial?.diffuse.contents =
                scanData.faceTexture ?? skinFallback
            return
        }

        guard let paint = paintCanvasImage else {
            faceNode.geometry?.firstMaterial?.diffuse.contents =
                scanData.faceTexture ?? skinFallback
            return
        }

        let size = CGSize(width: 1024, height: 1024)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1; format.opaque = true
        let result = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            if let base = scanData.faceTexture {
                base.draw(in: CGRect(origin: .zero, size: size))
            } else {
                UIColor(red: 0.87, green: 0.75, blue: 0.65, alpha: 1).setFill()
                UIBezierPath(rect: CGRect(origin: .zero, size: size)).fill()
            }
            paint.draw(in: CGRect(origin: .zero, size: size))
        }
        faceNode.geometry?.firstMaterial?.diffuse.contents = result
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
