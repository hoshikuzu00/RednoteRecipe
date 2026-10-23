import Foundation
import UIKit

enum RecipeBackendImporterError: LocalizedError {
    case invalidResponse
    case backendError(String)
    case noRecipeContent

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Your Mac backend returned an invalid response."
        case .backendError(let message):
            return message
        case .noRecipeContent:
            return "Your Mac backend did not return enough recipe text or images yet."
        }
    }
}

struct RecipeBackendImporter {
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 90
        return URLSession(configuration: configuration)
    }()

    func importRecipe(from rawInput: String, backendBaseURL: URL) async throws -> RecipeLinkImportResult {
        let endpoint = backendBaseURL
            .appendingPathComponent("imports", isDirectory: false)
            .appendingPathComponent("link", isDirectory: false)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["input": rawInput])

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RecipeBackendImporterError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw RecipeBackendImporterError.backendError(
                backendErrorMessage(from: data) ??
                "Your Mac backend returned HTTP \(httpResponse.statusCode)."
            )
        }

        let payload = try BackendRecipePayload(data: data)

        let images = payload.inlineImages.isEmpty
            ? await downloadImages(from: Array(payload.imageURLs.prefix(50)))
            : payload.inlineImages
        let sourceURL = payload.sourceURL ?? RecipeLinkImporter.firstURLString(in: rawInput).flatMap(URL.init(string:))
        let resolvedURL = payload.resolvedURL ?? sourceURL ?? endpoint
        let sourceText = makeSourceText(
            resolvedURL: resolvedURL,
            title: payload.title,
            description: payload.description,
            sourceText: payload.sourceText,
            bodyText: payload.bodyText
        )
        let analysisText = makeAnalysisText(
            title: payload.title,
            description: payload.description,
            sourceText: payload.sourceText,
            bodyText: payload.bodyText
        )

        guard !analysisText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !images.isEmpty else {
            throw RecipeBackendImporterError.noRecipeContent
        }

        return RecipeLinkImportResult(
            originalURL: sourceURL ?? resolvedURL,
            resolvedURL: resolvedURL,
            pageTitle: payload.title,
            bodyText: payload.bodyText,
            sourceText: sourceText,
            analysisText: analysisText,
            images: images,
            mediaKind: payload.mediaKind,
            videoURL: resolveVideoURL(from: payload, backendBaseURL: backendBaseURL),
            noteType: payload.noteType
        )
    }

    private func makeSourceText(
        resolvedURL: URL,
        title: String,
        description: String,
        sourceText: String,
        bodyText: String
    ) -> String {
        let trimmedSourceText = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSourceText.isEmpty {
            return trimmedSourceText
        }

        var lines: [String] = ["Source URL: \(resolvedURL.absoluteString)"]

        if !title.isEmpty {
            lines.append("Page Title: \(title)")
        }

        if !description.isEmpty {
            lines.append("Page Description: \(description)")
        }

        if !bodyText.isEmpty {
            lines.append(bodyText)
        }

        return deduplicatedTextBlocks(lines).joined(separator: "\n")
    }

    private func makeAnalysisText(
        title: String,
        description: String,
        sourceText: String,
        bodyText: String
    ) -> String {
        deduplicatedTextBlocks([title, bodyText, description, sourceText])
            .joined(separator: "\n")
    }

    private func deduplicatedTextBlocks(_ blocks: [String]) -> [String] {
        var seen: Set<String> = []
        var results: [String] = []

        for block in blocks {
            let trimmed = block.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let normalized = trimmed
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard seen.insert(normalized).inserted else { continue }
            results.append(trimmed)
        }

        return results
    }

    private func downloadImages(from urls: [URL]) async -> [UIImage] {
        var images: [UIImage] = []

        for url in urls {
            guard let image = await downloadImage(from: url) else { continue }
            images.append(image)
        }

        return images
    }

    private func downloadImage(from url: URL) async -> UIImage? {
        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<400).contains(httpResponse.statusCode),
                  let image = UIImage(data: data) else {
                return nil
            }

            return image
        } catch {
            return nil
        }
    }

    private func backendErrorMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        for key in ["error", "message", "detail"] {
            if let message = object[key] as? String,
               !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return message
            }
        }

        return nil
    }

    private func resolveVideoURL(
        from payload: BackendRecipePayload,
        backendBaseURL: URL
    ) -> URL? {
        if let assetPath = payload.videoAssetPath,
           let resolvedURL = URL(string: assetPath, relativeTo: backendBaseURL)?.absoluteURL {
            return resolvedURL
        }

        if let videoURL = payload.videoURL {
            return videoURL
        }

        return nil
    }
}

private struct BackendRecipePayload {
    let sourceURL: URL?
    let resolvedURL: URL?
    let title: String
    let description: String
    let sourceText: String
    let bodyText: String
    let imageURLs: [URL]
    let inlineImages: [UIImage]
    let mediaKind: RecipeLinkMediaKind
    let videoURL: URL?
    let videoAssetPath: String?
    let noteType: String

    init(data: Data) throws {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RecipeBackendImporterError.invalidResponse
        }

        sourceURL = Self.urlValue(in: object, keys: ["source_url", "sourceURL", "url"])
        resolvedURL = Self.urlValue(in: object, keys: ["resolved_url", "resolvedURL", "canonical_url", "canonicalURL"])
        title = Self.stringValue(in: object, keys: ["title"])
        description = Self.stringValue(in: object, keys: ["description", "summary"])
        sourceText = Self.stringValue(in: object, keys: ["source_text", "sourceText", "raw_text", "rawText"])
        bodyText = Self.stringValue(in: object, keys: ["body_text", "bodyText", "content", "text", "description_text"])
        imageURLs = Self.imageURLValues(in: object)
        inlineImages = Self.inlineImageValues(in: object)
        mediaKind = Self.mediaKindValue(in: object, inlineImages: inlineImages, imageURLs: imageURLs)
        videoURL = Self.urlValue(in: object, keys: ["video_url", "videoURL"])
        videoAssetPath = Self.stringValueOrNil(in: object, keys: ["video_asset_path", "videoAssetPath"])
        noteType = Self.stringValue(in: object, keys: ["note_type", "noteType"])
    }

    private static func stringValue(in object: [String: Any], keys: [String]) -> String {
        for key in keys {
            if let value = object[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }

        return ""
    }

    private static func urlValue(in object: [String: Any], keys: [String]) -> URL? {
        for key in keys {
            if let value = object[key] as? String,
               let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return url
            }
        }

        return nil
    }

    private static func stringValueOrNil(in object: [String: Any], keys: [String]) -> String? {
        let value = stringValue(in: object, keys: keys)
        return value.isEmpty ? nil : value
    }

    private static func mediaKindValue(
        in object: [String: Any],
        inlineImages: [UIImage],
        imageURLs: [URL]
    ) -> RecipeLinkMediaKind {
        let rawValue = stringValue(in: object, keys: ["media_kind", "mediaKind"]).lowercased()
        if let parsed = RecipeLinkMediaKind(rawValue: rawValue) {
            return parsed
        }

        if stringValueOrNil(in: object, keys: ["video_asset_path", "videoAssetPath", "video_url", "videoURL"]) != nil {
            return .video
        }

        if !inlineImages.isEmpty || !imageURLs.isEmpty {
            return .images
        }

        return .text
    }

    private static func imageURLValues(in object: [String: Any]) -> [URL] {
        let candidateKeys = ["image_urls", "imageURLs", "images"]
        var urls: [URL] = []

        for key in candidateKeys {
            guard let rawValue = object[key] else { continue }

            if let stringArray = rawValue as? [String] {
                urls.append(contentsOf: stringArray.compactMap(URL.init(string:)))
                continue
            }

            if let dictionaries = rawValue as? [[String: Any]] {
                for dictionary in dictionaries {
                    for urlKey in ["url", "src", "image_url", "imageURL"] {
                        if let value = dictionary[urlKey] as? String,
                           let url = URL(string: value) {
                            urls.append(url)
                            break
                        }
                    }
                }
            }
        }

        var seen: Set<String> = []
        return urls.filter { url in
            seen.insert(url.absoluteString).inserted
        }
    }

    private static func inlineImageValues(in object: [String: Any]) -> [UIImage] {
        let candidateKeys = ["image_data_urls", "imageDataURLs", "images"]
        var images: [UIImage] = []

        for key in candidateKeys {
            guard let rawValue = object[key] else { continue }

            if let stringArray = rawValue as? [String] {
                images.append(contentsOf: stringArray.compactMap(decodeDataURLImage))
                continue
            }

            if let dictionaries = rawValue as? [[String: Any]] {
                for dictionary in dictionaries {
                    if let dataURL = dictionary["data_url"] as? String ?? dictionary["dataURL"] as? String,
                       let image = decodeDataURLImage(dataURL) {
                        images.append(image)
                    }
                }
            }
        }

        return images
    }

    private static func decodeDataURLImage(_ dataURLString: String) -> UIImage? {
        guard let range = dataURLString.range(of: "base64,") else {
            return nil
        }

        let base64Value = String(dataURLString[range.upperBound...])
        guard let data = Data(base64Encoded: base64Value) else {
            return nil
        }

        return UIImage(data: data)
    }
}
