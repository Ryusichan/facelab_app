import SwiftUI

struct ContentView: View {
    @EnvironmentObject var authViewModel: AuthViewModel

    var body: some View {
        Group {
            if authViewModel.isAuthenticated {
                MainTabView()
            } else {
                LoginView()
            }
        }
        .task {
            await authViewModel.checkSession()
        }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            ARFaceView()
                .tabItem {
                    Label("Face Scan", systemImage: "faceid")
                }

            MakeupStudioView()
                .tabItem {
                    Label("Studio", systemImage: "paintbrush.pointed")
                }

            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person.circle")
                }
        }
    }
}

// MARK: - Placeholder for Profile
struct ProfileView: View {
    @EnvironmentObject var authViewModel: AuthViewModel

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
            }
            .navigationTitle("Profile")
        }
    }
}
