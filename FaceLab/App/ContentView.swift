import SwiftUI

// ============================================================
// MARK: - AppRouter
// 화면 전환 관리 + 캡처된 얼굴 데이터 보관
// ============================================================
@MainActor
class AppRouter: ObservableObject {
    enum Screen {
        case inputMethod
        case faceCapture
        case photoPicker
        case processing
        case editor
        case arLive       // AR 실시간 모드 (기존 MakeupStudioView)
        case profile
    }

    @Published var screen: Screen = .inputMethod
    @Published var scanData: FaceScanData?

    func goTo(_ screen: Screen) {
        withAnimation(.easeInOut(duration: 0.25)) {
            self.screen = screen
        }
    }
}

// ============================================================
// MARK: - ContentView
// 인증 체크 → 메인 플로우 라우팅
// ============================================================
struct ContentView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var router = AppRouter()

    var body: some View {
        Group {
            if authViewModel.isAuthenticated {
                mainFlow
            } else {
                LoginView()
            }
        }
        .task {
            await authViewModel.checkSession()
        }
    }

    @ViewBuilder
    private var mainFlow: some View {
        switch router.screen {
        case .inputMethod:
            InputMethodView()
                .environmentObject(router)

        case .faceCapture:
            FaceCaptureView()
                .environmentObject(router)

        case .photoPicker:
            PhotoPickerView()
                .environmentObject(router)

        case .processing:
            ProcessingView()
                .environmentObject(router)

        case .editor:
            if let scanData = router.scanData {
                Face3DEditorView(scanData: scanData)
                    .environmentObject(router)
            } else {
                // fallback: scanData 없으면 입력 화면으로
                InputMethodView()
                    .environmentObject(router)
                    .onAppear { router.goTo(.inputMethod) }
            }

        case .arLive:
            ZStack {
                MakeupStudioView()
                // 뒤로가기 버튼
                VStack {
                    HStack {
                        Button {
                            router.goTo(.inputMethod)
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.title3.bold())
                                .foregroundStyle(.white)
                                .padding(10)
                                .background(.black.opacity(0.4), in: Circle())
                        }
                        .padding(.leading, 20)
                        .padding(.top, 60)
                        Spacer()
                    }
                    Spacer()
                }
            }

        case .profile:
            ProfileView()
                .environmentObject(router)
        }
    }
}

// MARK: - ProfileView
struct ProfileView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var router: AppRouter

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.secondary)

                Text("My Profile")
                    .font(.title2)

                Button("Sign Out", role: .destructive) {
                    Task { await authViewModel.signOut() }
                }
                .buttonStyle(.bordered)

                Button("Back") {
                    router.goTo(.inputMethod)
                }
            }
            .navigationTitle("Profile")
        }
    }
}
