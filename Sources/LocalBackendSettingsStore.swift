import Foundation

@MainActor
final class LocalBackendSettingsStore: ObservableObject {
    @Published private(set) var baseURLString = ""
    @Published private(set) var discoveredBaseURLString = ""
    @Published private(set) var discoveryStatusMessage = ""
    @Published private(set) var isDiscovering = false

    private let defaults: UserDefaults
    private let storageKey = "com.chonggu.RednoteOCR.local-backend-base-url"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let storedValue = defaults.string(forKey: storageKey)
        let defaultValue = LocalSecrets.defaultLocalBackendBaseURL
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let storedValue,
           let normalizedValue = Self.normalizedBaseURLString(from: storedValue) {
            baseURLString = normalizedValue
        } else if let normalizedDefault = Self.normalizedBaseURLString(from: defaultValue) {
            baseURLString = normalizedDefault
            defaults.set(normalizedDefault, forKey: storageKey)
        } else {
            baseURLString = ""
        }
    }

    var configuredBaseURL: URL? {
        guard let normalizedValue = Self.normalizedBaseURLString(from: baseURLString) else {
            return nil
        }

        return URL(string: normalizedValue)
    }

    var isConfigured: Bool {
        configuredBaseURL != nil
    }

    var isUsingDiscoveredBackend: Bool {
        false
    }

    var effectiveBaseURLString: String {
        Self.normalizedBaseURLString(from: baseURLString) ?? ""
    }

    func saveBaseURL(_ newValue: String) throws {
        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            clearBaseURL()
            return
        }

        guard let normalizedValue = Self.normalizedBaseURLString(from: trimmed) else {
            throw LocalBackendSettingsError.invalidURL
        }

        defaults.set(normalizedValue, forKey: storageKey)
        baseURLString = normalizedValue
    }

    func clearBaseURL() {
        defaults.removeObject(forKey: storageKey)
        if let normalizedDefault = Self.normalizedBaseURLString(from: LocalSecrets.defaultLocalBackendBaseURL) {
            defaults.set(normalizedDefault, forKey: storageKey)
            baseURLString = normalizedDefault
        } else {
            baseURLString = ""
        }
    }

    func refreshDiscovery() {
        isDiscovering = false
        discoveryStatusMessage = "Automatic Mac backend discovery is turned off. The app will use your saved backend URL."
    }

    private static func normalizedBaseURLString(from rawValue: String) -> String? {
        var candidate = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return nil }

        if !candidate.contains("://") {
            candidate = "http://\(candidate)"
        }

        guard var components = URLComponents(string: candidate),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              components.host != nil else {
            return nil
        }

        components.scheme = scheme

        let normalizedPath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = normalizedPath.isEmpty ? "" : "/\(normalizedPath)"

        var normalizedValue = components.string ?? candidate
        while normalizedValue.hasSuffix("/") {
            normalizedValue.removeLast()
        }

        return normalizedValue
    }
}

enum LocalBackendSettingsError: LocalizedError {
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Enter a valid backend URL such as http://10.0.0.12:8080."
        }
    }
}
