import SwiftUI

// ============================================================
// MARK: - InputMethodView  (메인 홈 화면)
// Luxury beauty editorial — 다크 히어로 + 라이트 액션 카드
// ============================================================
struct InputMethodView: View {
    @EnvironmentObject var router: AppRouter
    @State private var dotPhase: CGFloat = 0
    @State private var pulseScale: CGFloat = 1.0
    @State private var scanLineY: CGFloat = -1

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                // ── 배경 ──
                darkBackground.ignoresSafeArea()

                // ── 히어로 상단 (60%) ──
                VStack(spacing: 0) {
                    topBar
                    Spacer()
                    heroVisual
                    Spacer()
                }
                .frame(height: geo.size.height * 0.62)

                // ── 하단 액션 카드 ──
                VStack(spacing: 0) {
                    Spacer()
                    bottomSheet(width: geo.size.width)
                }
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .onAppear { startAnimations() }
    }

    // ──────────────────────────────
    // MARK: Background
    // ──────────────────────────────
    private var darkBackground: some View {
        ZStack {
            Color(red: 0.06, green: 0.05, blue: 0.08)

            // 상단 좌측 블러 글로우
            Ellipse()
                .fill(Color(red: 0.60, green: 0.18, blue: 0.42).opacity(0.22))
                .frame(width: 340, height: 260)
                .blur(radius: 70)
                .offset(x: -100, y: -240)

            // 우측 하단 글로우
            Ellipse()
                .fill(Color(red: 0.42, green: 0.14, blue: 0.58).opacity(0.18))
                .frame(width: 280, height: 220)
                .blur(radius: 60)
                .offset(x: 130, y: 60)

            // 메시 도트 패턴 (ARKit 스캔 느낌)
            MeshDotsView(phase: dotPhase)
                .opacity(0.18)
        }
    }

    // ──────────────────────────────
    // MARK: Top Bar
    // ──────────────────────────────
    private var topBar: some View {
        HStack(alignment: .center) {
            // 로고 워드마크
            HStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.92, green: 0.48, blue: 0.68),
                                         Color(red: 0.72, green: 0.26, blue: 0.72)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 28, height: 28)
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                }
                Text("FaceLab")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }

            Spacer()

            // 프로필 버튼
            Button { router.goTo(.profile) } label: {
                ZStack {
                    Circle()
                        .strokeBorder(.white.opacity(0.15), lineWidth: 1)
                        .background(Circle().fill(.white.opacity(0.06)))
                        .frame(width: 38, height: 38)
                    Image(systemName: "person.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .padding(.horizontal, 26)
        .padding(.top, 60)
    }

    // ──────────────────────────────
    // MARK: Hero Visual
    // ──────────────────────────────
    private var heroVisual: some View {
        VStack(spacing: 0) {
            // AR 스캔 비주얼
            ZStack {
                // 외곽 펄스 링
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color(red: 0.92, green: 0.55, blue: 0.75).opacity(0.0),
                                Color(red: 0.92, green: 0.55, blue: 0.75).opacity(0.5),
                                Color(red: 0.92, green: 0.55, blue: 0.75).opacity(0.0)
                            ],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
                    .frame(width: 200, height: 200)
                    .scaleEffect(pulseScale)
                    .opacity(2 - pulseScale)

                // 중간 링
                Circle()
                    .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                    .frame(width: 162, height: 162)

                // 메인 원
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.32, green: 0.12, blue: 0.36),
                                Color(red: 0.14, green: 0.08, blue: 0.18)
                            ],
                            center: .center, startRadius: 0, endRadius: 80
                        )
                    )
                    .frame(width: 148, height: 148)
                    .overlay(
                        Circle()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.92, green: 0.55, blue: 0.75).opacity(0.6),
                                        Color(red: 0.65, green: 0.28, blue: 0.80).opacity(0.4)
                                    ],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                    )

                // 스캔 라인 (수직 이동)
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.clear,
                                     Color(red: 0.92, green: 0.55, blue: 0.75).opacity(0.7),
                                     .clear],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .frame(width: 140, height: 1.5)
                    .offset(y: scanLineY * 70)
                    .clipShape(Circle().scale(1.05))

                // 얼굴 아이콘
                Image(systemName: "face.dashed")
                    .font(.system(size: 52, weight: .ultraLight))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(red: 0.98, green: 0.82, blue: 0.91),
                                     Color(red: 0.88, green: 0.58, blue: 0.78)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )

                // 코너 크로스헤어
                ForEach(0..<4) { i in
                    Crosshair()
                        .stroke(Color(red: 0.92, green: 0.55, blue: 0.75).opacity(0.6), lineWidth: 1.2)
                        .frame(width: 16, height: 16)
                        .rotationEffect(.degrees(Double(i) * 90))
                        .offset(
                            x: [(-1), 1, 1, (-1)][i] * CGFloat(62),
                            y: [(-1), (-1), 1, 1][i] * CGFloat(62)
                        )
                }
            }
            .shadow(color: Color(red: 0.85, green: 0.30, blue: 0.65).opacity(0.5), radius: 40)

            Spacer().frame(height: 32)

            // 헤드라인
            VStack(spacing: 8) {
                Text("Scan · Style · Shine")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(red: 0.92, green: 0.60, blue: 0.78))
                    .kerning(3)
                    .textCase(.uppercase)

                Text("당신의 얼굴을\n3D로 메이크업하다")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
        }
        .padding(.horizontal, 32)
    }

    // ──────────────────────────────
    // MARK: Bottom Sheet
    // ──────────────────────────────
    private func bottomSheet(width: CGFloat) -> some View {
        ZStack(alignment: .top) {
            // 배경
            RoundedRectangle(cornerRadius: 32)
                .fill(Color(red: 0.97, green: 0.95, blue: 0.97))
                .ignoresSafeArea(edges: .bottom)

            VStack(spacing: 0) {
                // 핸들
                Capsule()
                    .fill(Color(red: 0.80, green: 0.75, blue: 0.82))
                    .frame(width: 36, height: 4)
                    .padding(.top, 12)

                VStack(spacing: 20) {
                    // 카테고리 필 버튼들
                    categoryPills

                    // 메인 CTA
                    mainCTAButton(width: width)

                    // 보조 버튼
                    secondaryCTAButton
                }
                .padding(.horizontal, 26)
                .padding(.top, 20)
                .padding(.bottom, 44)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // 카테고리 태그
    private var categoryPills: some View {
        HStack(spacing: 8) {
            ForEach(["립", "아이", "쉐딩", "하이라이터", "블러셔"], id: \.self) { tag in
                Text(tag)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(red: 0.45, green: 0.20, blue: 0.55))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(
                        Capsule()
                            .fill(Color(red: 0.92, green: 0.86, blue: 0.94))
                    )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .scrollClipDisabled()
        .fixedSize(horizontal: false, vertical: true)
        // 스크롤 없이 첫 3개만 표시
        .mask(
            HStack {
                Rectangle()
                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 40)
            }
        )
    }

    // 메인 버튼
    private func mainCTAButton(width: CGFloat) -> some View {
        Button { router.goTo(.faceCapture) } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.22))
                        .frame(width: 40, height: 40)
                    Image(systemName: "camera.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("얼굴 스캔 시작")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("TrueDepth 3D 스캔")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.white.opacity(0.72))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(
                LinearGradient(
                    colors: [Color(red: 0.90, green: 0.40, blue: 0.65),
                             Color(red: 0.68, green: 0.22, blue: 0.72)],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: 20)
            )
            .shadow(color: Color(red: 0.80, green: 0.25, blue: 0.60).opacity(0.45), radius: 16, y: 6)
        }
    }

    // AR 라이브 보조 버튼
    private var secondaryCTAButton: some View {
        Button { router.goTo(.arLive) } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(red: 0.92, green: 0.86, blue: 0.94))
                        .frame(width: 40, height: 40)
                    Image(systemName: "arkit")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Color(red: 0.55, green: 0.20, blue: 0.65))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("AR 실시간 메이크업")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(red: 0.18, green: 0.10, blue: 0.22))
                    Text("카메라에서 바로 체험")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(red: 0.50, green: 0.40, blue: 0.55))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(red: 0.70, green: 0.55, blue: 0.75))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(red: 0.97, green: 0.95, blue: 0.97))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .strokeBorder(Color(red: 0.82, green: 0.74, blue: 0.86), lineWidth: 1)
                    )
            )
        }
    }

    // ──────────────────────────────
    // MARK: Animations
    // ──────────────────────────────
    private func startAnimations() {
        // 펄스 링
        withAnimation(.easeOut(duration: 2.0).repeatForever(autoreverses: false)) {
            pulseScale = 1.35
        }
        // 스캔 라인
        withAnimation(.linear(duration: 2.4).repeatForever(autoreverses: true)) {
            scanLineY = 1
        }
        // 도트 위상
        withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
            dotPhase = .pi * 2
        }
    }
}

// ──────────────────────────────
// MARK: - Mesh Dots Background
// ──────────────────────────────
private struct MeshDotsView: View {
    let phase: CGFloat

    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                let cols = 12, rows = 18
                let cellW = size.width / CGFloat(cols)
                let cellH = size.height * 0.65 / CGFloat(rows)

                for row in 0..<rows {
                    for col in 0..<cols {
                        let x = CGFloat(col) * cellW + cellW * 0.5
                        let y = CGFloat(row) * cellH + cellH * 0.5
                        let dist = hypot(x - size.width * 0.5, y - size.height * 0.3)
                        let wave = sin(dist * 0.04 - phase) * 0.5 + 0.5
                        let r = CGFloat(1.2 + wave * 1.0)
                        let alpha = 0.3 + wave * 0.5

                        ctx.fill(
                            Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r*2, height: r*2)),
                            with: .color(.white.opacity(alpha))
                        )
                    }
                }
            }
        }
    }
}

// ──────────────────────────────
// MARK: - Crosshair Shape
// ──────────────────────────────
private struct Crosshair: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let m = rect.width * 0.35
        // 상단
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.minY + m))
        // 좌측
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.minX + m, y: rect.midY))
        return p
    }
}
