import SwiftUI

// ============================================================
// MARK: - InputMethodView
// 입력 방식 선택: 카메라 촬영 (ARKit) / 사진 선택
// ============================================================
struct InputMethodView: View {
    @EnvironmentObject var router: AppRouter

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // 헤더
            VStack(spacing: 8) {
                Image(systemName: "face.smiling")
                    .font(.system(size: 56))
                    .foregroundStyle(Color.accentColor)
                Text("얼굴을 스캔하세요")
                    .font(.title2.bold())
                Text("3D 얼굴 모델을 만들고 가상 메이크업을 적용해보세요")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer()

            // 입력 방식 카드
            VStack(spacing: 16) {
                // 카메라 촬영 (메인 CTA)
                InputMethodCard(
                    icon: "camera.fill",
                    title: "카메라로 촬영",
                    subtitle: "TrueDepth 카메라로 정밀한 3D 스캔",
                    isPrimary: true
                ) {
                    router.goTo(.faceCapture)
                }

                // 사진 선택 (보조)
                InputMethodCard(
                    icon: "photo.on.rectangle",
                    title: "사진에서 선택",
                    subtitle: "앨범의 사진으로 기본 3D 모델 생성",
                    isPrimary: false
                ) {
                    router.goTo(.photoPicker)
                }
            }
            .padding(.horizontal, 24)

            Spacer()

            // 안내 텍스트
            Text("카메라 촬영 시 더 정밀한 3D 모델이 생성됩니다")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 40)
        }
        .background(Color(.systemBackground))
    }
}

// MARK: - Input Method Card
private struct InputMethodCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let isPrimary: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.title2)
                    .frame(width: 48, height: 48)
                    .background(
                        isPrimary
                            ? Color.accentColor.opacity(0.15)
                            : Color.secondary.opacity(0.1),
                        in: RoundedRectangle(cornerRadius: 12)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(
                isPrimary
                    ? Color.accentColor.opacity(0.06)
                    : Color(.secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: 16)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        isPrimary ? Color.accentColor.opacity(0.3) : .clear,
                        lineWidth: 1
                    )
            )
        }
        .foregroundStyle(.primary)
    }
}
