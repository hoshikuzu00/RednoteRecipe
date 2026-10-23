import Foundation
import Security

@MainActor
final class OpenAISettingsStore: ObservableObject {
    @Published private(set) var apiKey = ""

    private let keychainStore = OpenAIKeychainStore()
    private let testSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 45
        return URLSession(configuration: configuration)
    }()
    private let responsesEndpoint = URL(string: "https://api.openai.com/v1/responses")!
    private let recipeModel = "gpt-5.4-nano"

    init() {
        do {
            if let storedKey = try keychainStore.load()?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !storedKey.isEmpty {
                apiKey = storedKey
                return
            }

            let defaultKey = LocalSecrets.defaultOpenAIAPIKey
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if !defaultKey.isEmpty {
                try keychainStore.save(defaultKey)
                apiKey = defaultKey
                return
            }

            apiKey = ""
        } catch {
            apiKey = ""
            print("Failed to load OpenAI API key: \(error.localizedDescription)")
        }
    }

    var configuredAPIKey: String? {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var isConfigured: Bool {
        configuredAPIKey != nil
    }

    var maskedKeySuffix: String? {
        guard let configuredAPIKey else { return nil }
        return String(configuredAPIKey.suffix(6))
    }

    func saveAPIKey(_ newValue: String) throws {
        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            try clearAPIKey()
            return
        }

        try keychainStore.save(trimmed)
        apiKey = trimmed
    }

    func clearAPIKey() throws {
        try keychainStore.delete()
        apiKey = ""
    }

    func testConnection() async throws -> String {
        guard let configuredAPIKey else {
            return "No OpenAI API key is currently saved on this device."
        }

        var request = URLRequest(url: responsesEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(configuredAPIKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: [
                "model": recipeModel,
                "input": [
                    [
                        "role": "user",
                        "content": [
                            [
                                "type": "input_text",
                                "text": "Reply with OK."
                            ]
                        ]
                    ]
                ],
                "max_output_tokens": 20
            ],
            options: []
        )

        let (data, response) = try await testSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAISettingsError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if let apiError = try? JSONDecoder().decode(OpenAISettingsAPIErrorEnvelope.self, from: data),
               let message = apiError.error.message,
               !message.isEmpty {
                throw OpenAISettingsError.apiTestFailure(message)
            }

            throw OpenAISettingsError.apiTestFailure("HTTP \(httpResponse.statusCode)")
        }

        return "OpenAI connection looks good. The saved key can write to Responses API with \(recipeModel)."
    }
}

enum OpenAISettingsError: LocalizedError {
    case keychainFailure(OSStatus)
    case invalidResponse
    case apiTestFailure(String)

    var errorDescription: String? {
        switch self {
        case .keychainFailure(let status):
            return "Keychain error (\(status))."
        case .invalidResponse:
            return "OpenAI returned an invalid response."
        case .apiTestFailure(let message):
            return message
        }
    }
}

private struct OpenAIKeychainStore {
    private let service = "com.chonggu.RednoteOCR.openai-api-key"
    private let account = "default"

    func load() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        case errSecItemNotFound:
            return nil
        default:
            throw OpenAISettingsError.keychainFailure(status)
        }
    }

    func save(_ value: String) throws {
        let data = Data(value.utf8)

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)

        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var addQuery = baseQuery
            attributes.forEach { addQuery[$0.key] = $0.value }
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw OpenAISettingsError.keychainFailure(addStatus)
            }
        default:
            throw OpenAISettingsError.keychainFailure(updateStatus)
        }
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw OpenAISettingsError.keychainFailure(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

private struct OpenAISettingsAPIErrorEnvelope: Decodable {
    let error: OpenAISettingsAPIErrorBody
}

private struct OpenAISettingsAPIErrorBody: Decodable {
    let message: String?
}
