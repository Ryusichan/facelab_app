import Foundation
import Supabase

@MainActor
class AuthViewModel: ObservableObject {
    @Published var isAuthenticated = false
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var supabase: SupabaseClient { SupabaseService.shared.client }

    // PROTOTYPE: bypass auth — always authenticated
    func checkSession() async {
        isAuthenticated = true
    }

    func signUp(email: String, password: String) async {
        isLoading = true
        isAuthenticated = true
        isLoading = false
    }

    func signIn(email: String, password: String) async {
        isLoading = true
        isAuthenticated = true
        isLoading = false
    }

    func signOut() async {
        isAuthenticated = false
    }
}
