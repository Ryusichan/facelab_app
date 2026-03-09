import Foundation
import Supabase

// MARK: - Supabase Client Singleton
final class SupabaseService {
    static let shared = SupabaseService()

    let client: SupabaseClient

    private init() {
        guard let path = Bundle.main.path(forResource: "Supabase", ofType: "plist"),
              let dict = NSDictionary(contentsOfFile: path),
              let url = dict["SUPABASE_URL"] as? String,
              let key = dict["SUPABASE_ANON_KEY"] as? String
        else {
            fatalError("Missing Supabase.plist configuration. Add SUPABASE_URL and SUPABASE_ANON_KEY.")
        }

        self.client = SupabaseClient(
            supabaseURL: URL(string: url)!,
            supabaseKey: key
        )
    }
}

// MARK: - Database Tables
extension SupabaseService {
    enum Table: String {
        case users = "users"
        case makeupLooks = "makeup_looks"
        case makeupLayers = "makeup_layers"
    }

    // Save a makeup look
    func saveMakeupLook(_ look: MakeupLook) async throws {
        try await client.from(Table.makeupLooks.rawValue)
            .insert(look)
            .execute()
    }

    // Fetch user's makeup looks
    func fetchMakeupLooks(userId: String) async throws -> [MakeupLook] {
        try await client.from(Table.makeupLooks.rawValue)
            .select()
            .eq("user_id", value: userId)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    // Delete a makeup look
    func deleteMakeupLook(id: UUID) async throws {
        try await client.from(Table.makeupLooks.rawValue)
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }
}

// MARK: - Storage
extension SupabaseService {
    private var storageBucket: String { "face-captures" }

    func uploadFaceCapture(imageData: Data, userId: String) async throws -> String {
        let fileName = "\(userId)/\(UUID().uuidString).jpg"

        try await client.storage
            .from(storageBucket)
            .upload(
                path: fileName,
                file: imageData,
                options: .init(contentType: "image/jpeg")
            )

        let publicURL = try client.storage
            .from(storageBucket)
            .getPublicURL(path: fileName)

        return publicURL.absoluteString
    }
}
