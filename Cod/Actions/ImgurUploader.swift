import UIKit

/// Anonymous Imgur upload. Requires the user's own Client ID (Settings →
/// Integrations) — Cod ships without credentials on purpose.
enum ImgurUploader {
    enum UploadError: LocalizedError {
        case missingClientID
        case encodingFailed
        case server(String)

        var errorDescription: String? {
            switch self {
            case .missingClientID: return "Add your Imgur Client ID in Settings → Integrations."
            case .encodingFailed: return "Couldn't encode that image."
            case let .server(message): return message
            }
        }
    }

    static func upload(_ image: UIImage, clientID: String) async throws -> String {
        let trimmed = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw UploadError.missingClientID }
        guard let data = image.pngData() ?? image.jpegData(compressionQuality: 0.9) else {
            throw UploadError.encodingFailed
        }

        var request = URLRequest(url: URL(string: "https://api.imgur.com/3/image")!)
        request.httpMethod = "POST"
        request.setValue("Client-ID \(trimmed)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "image": data.base64EncodedString(),
            "type": "base64",
        ])

        let (responseData, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw UploadError.server("No response from Imgur.")
        }

        let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any]

        guard http.statusCode == 200 else {
            let message = ((json?["data"] as? [String: Any])?["error"] as? String)
                ?? "Imgur returned \(http.statusCode)."
            throw UploadError.server(message)
        }

        guard let link = (json?["data"] as? [String: Any])?["link"] as? String else {
            throw UploadError.server("Imgur didn't return a link.")
        }
        return link
    }
}
