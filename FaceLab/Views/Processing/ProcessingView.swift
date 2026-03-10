import SwiftUI

// ============================================================
// MARK: - ProcessingView
// 얼굴 분석 → 3D 모델 생성 로딩 화면
// scanData가 이미 캡처된 상태에서 UX용 로딩 애니메이션 표시
// ============================================================
struct ProcessingView: View {
    @EnvironmentObject var router: AppRouter
    @State private var currentStep = 0
    @State private var progress: Double = 0

    private let steps = [
        ("얼굴 분석 중...", "faceid"),
        ("랜드마크 추출 중...", "point.3.filled.connected.trianglepath.dotted"),
        ("3D 모델 생성 중...", "cube.transparent"),
        ("메이크업 레이어 준비 중...", "paintbrush.pointed"),
    ]

    var body: some View {
        VStack(spacing: 40) {
            Spacer()

            // 3D 큐브 애니메이션
            ZStack {
                Circle()
                    .fill(.accent.opacity(0.08))
                    .frame(width: 140, height: 140)

                Image(systemName: steps[currentStep].1)
                    .font(.system(size: 48))
                    .foregroundStyle(.accent)
                    .contentTransition(.symbolEffect(.replace))
            }

            // 단계 텍스트
            VStack(spacing: 12) {
                Text(steps[currentStep].0)
                    .font(.title3.bold())
                    .contentTransition(.numericText())

                // 프로그레스 바
                ProgressView(value: progress)
                    .tint(.accent)
                    .frame(width: 200)

                Text("\(Int(progress * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Spacer()
            Spacer()
        }
        .animation(.easeInOut(duration: 0.3), value: currentStep)
        .animation(.easeInOut(duration: 0.2), value: progress)
        .task {
            await runProcessingAnimation()
        }
    }

    private func runProcessingAnimation() async {
        let stepDuration: UInt64 = 400_000_000 // 0.4초

        for i in 0..<steps.count {
            currentStep = i
            progress = Double(i + 1) / Double(steps.count + 1)
            try? await Task.sleep(nanoseconds: stepDuration)
        }

        progress = 1.0
        try? await Task.sleep(nanoseconds: 200_000_000)

        // 에디터로 이동
        router.goTo(.editor)
    }
}
