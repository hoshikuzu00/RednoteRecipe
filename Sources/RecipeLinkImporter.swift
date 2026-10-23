import Foundation
import UIKit

enum RecipeLinkMediaKind: String {
    case text
    case images
    case video
}

struct RecipeLinkImportResult {
    let originalURL: URL
    let resolvedURL: URL
    let pageTitle: String
    let bodyText: String
    let sourceText: String
    let analysisText: String
    let images: [UIImage]
    let mediaKind: RecipeLinkMediaKind
    let videoURL: URL?
    let noteType: String
}

enum RecipeLinkImporterError: LocalizedError {
    case invalidURL
    case invalidResponse
    case pageUnavailable
    case noRecipeContent

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The pasted text does not contain a usable recipe link."
        case .invalidResponse:
            return "The linked page returned an invalid response."
        case .pageUnavailable:
            return "The linked page could not be opened."
        case .noRecipeContent:
            return "The linked page did not expose enough recipe text or images yet."
        }
    }
}

struct RecipeLinkImporter {
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 45
        configuration.timeoutIntervalForResource = 60
        configuration.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        ]
        return URLSession(configuration: configuration)
    }()

    static func firstURLString(in text: String) -> String? {
        extractFirstURL(from: text)?.absoluteString
    }

    func importRecipe(from rawInput: String) async throws -> RecipeLinkImportResult {
        guard let originalURL = Self.extractFirstURL(from: rawInput) else {
            throw RecipeLinkImporterError.invalidURL
        }

        var request = URLRequest(url: originalURL)
        request.httpMethod = "GET"

        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse,
              (200..<400).contains(response.statusCode),
              let resolvedURL = response.url else {
            throw RecipeLinkImporterError.invalidResponse
        }

        guard !data.isEmpty else {
            throw RecipeLinkImporterError.pageUnavailable
        }

        let html = decodedHTML(from: data)
        let metadata = pageMetadata(from: html, baseURL: resolvedURL)
        let images = await downloadImages(from: Array(metadata.imageURLs.prefix(50)))
        let analysisText = makeAnalysisText(
            title: metadata.title,
            description: metadata.description,
            bodyLines: metadata.bodyLines
        )
        let sourceText = makeSourceText(
            resolvedURL: resolvedURL,
            title: metadata.title,
            description: metadata.description,
            bodyLines: metadata.bodyLines
        )

        guard !analysisText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !images.isEmpty else {
            throw RecipeLinkImporterError.noRecipeContent
        }

        return RecipeLinkImportResult(
            originalURL: originalURL,
            resolvedURL: resolvedURL,
            pageTitle: metadata.title,
            bodyText: metadata.bodyLines.joined(separator: "\n"),
            sourceText: sourceText,
            analysisText: analysisText,
            images: images,
            mediaKind: metadata.videoURLs.isEmpty ? (images.isEmpty ? .text : .images) : .video,
            videoURL: metadata.videoURLs.first,
            noteType: ""
        )
    }

    private static func extractFirstURL(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        guard let matchedURL = detector?.firstMatch(in: trimmed, options: [], range: range)?.url else {
            return nil
        }

        return normalizedEntryURL(matchedURL)
    }

    private static func normalizedEntryURL(_ url: URL) -> URL {
        guard url.scheme?.lowercased() == "http",
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }

        components.scheme = "https"
        return components.url ?? url
    }

    private func decodedHTML(from data: Data) -> String {
        if let html = String(data: data, encoding: .utf8) {
            return html
        }

        if let html = String(data: data, encoding: .unicode) {
            return html
        }

        return String(decoding: data, as: UTF8.self)
    }

    private func pageMetadata(from html: String, baseURL: URL) -> RecipePageMetadata {
        let metaTags = htmlMatches(in: html, pattern: #"<meta\b[^>]*>"#, options: [.caseInsensitive])
        var metaValues: [String: [String]] = [:]

        for tag in metaTags {
            let attributes = htmlAttributes(in: tag)
            let key = (attributes["property"] ?? attributes["name"] ?? "").lowercased()
            let content = decodeHTMLEntities(attributes["content"] ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !key.isEmpty, !content.isEmpty else { continue }
            metaValues[key, default: []].append(content)
        }

        let title = firstNonEmpty([
            metaValues["og:title"]?.first,
            metaValues["twitter:title"]?.first,
            firstCapture(in: html, pattern: #"<title[^>]*>(.*?)</title>"#, options: [.caseInsensitive, .dotMatchesLineSeparators])
        ]) ?? ""

        let description = firstNonEmpty([
            metaValues["og:description"]?.first,
            metaValues["description"]?.first,
            metaValues["twitter:description"]?.first
        ]) ?? ""

        var imageCandidates: [URL] = []

        let metaImageKeys = ["og:image", "og:image:url", "twitter:image", "twitter:image:src"]
        for key in metaImageKeys {
            for value in metaValues[key] ?? [] {
                if let url = normalizedURL(from: value, baseURL: baseURL) {
                    imageCandidates.append(url)
                }
            }
        }

        let imgTags = htmlMatches(in: html, pattern: #"<img\b[^>]*>"#, options: [.caseInsensitive])
        for tag in imgTags {
            let attributes = htmlAttributes(in: tag)
            for key in ["src", "data-src", "data-original"] {
                if let rawValue = attributes[key],
                   let url = normalizedURL(from: rawValue, baseURL: baseURL) {
                    imageCandidates.append(url)
                    break
                }
            }
        }

        for rawURL in htmlMatches(in: html, pattern: #"https?://[^"'\\s<>]+(?:png|jpg|jpeg|webp|gif)(?:\?[^"'\\s<>]*)?"#, options: [.caseInsensitive]) {
            if let url = URL(string: rawURL) {
                imageCandidates.append(url)
            }
        }

        let bodyLines = cleanedBodyLines(from: html)
        let videoURLs = videoURLs(from: html, baseURL: baseURL, metaValues: metaValues)
        return RecipePageMetadata(
            title: cleanPageText(title),
            description: cleanPageText(description),
            imageURLs: uniqueURLs(imageCandidates),
            videoURLs: uniqueURLs(videoURLs),
            bodyLines: bodyLines
        )
    }

    private func makeSourceText(
        resolvedURL: URL,
        title: String,
        description: String,
        bodyLines: [String]
    ) -> String {
        var lines: [String] = ["Source URL: \(resolvedURL.absoluteString)"]

        if !title.isEmpty {
            lines.append("Page Title: \(title)")
        }

        if !description.isEmpty {
            lines.append("Page Description: \(description)")
        }

        let filteredBodyLines = bodyLines
            .filter { line in
                !line.contains(resolvedURL.absoluteString) &&
                !line.hasPrefix("Page Title:") &&
                !line.hasPrefix("Page Description:")
            }
            .prefix(24)

        if !filteredBodyLines.isEmpty {
            lines.append("Visible Page Text:")
            lines.append(contentsOf: filteredBodyLines)
        }

        return lines.joined(separator: "\n")
    }

    private func makeAnalysisText(
        title: String,
        description: String,
        bodyLines: [String]
    ) -> String {
        var lines: [String] = []

        if !title.isEmpty {
            lines.append(title)
        }

        if !description.isEmpty {
            lines.append(description)
        }

        lines.append(contentsOf: bodyLines.prefix(24))
        return lines.joined(separator: "\n")
    }

    private func cleanedBodyLines(from html: String) -> [String] {
        var body = html
        let patterns = [
            #"<script\b[^>]*>.*?</script>"#,
            #"<style\b[^>]*>.*?</style>"#,
            #"<noscript\b[^>]*>.*?</noscript>"#
        ]

        for pattern in patterns {
            body = body.replacingOccurrences(
                of: pattern,
                with: " ",
                options: [.regularExpression, .caseInsensitive]
            )
        }

        let newlinePatterns = [
            #"<br\s*/?>"#,
            #"</(p|div|section|article|li|ul|ol|h1|h2|h3|h4|h5|h6)>"#
        ]

        for pattern in newlinePatterns {
            body = body.replacingOccurrences(
                of: pattern,
                with: "\n",
                options: [.regularExpression, .caseInsensitive]
            )
        }

        body = body.replacingOccurrences(
            of: #"<[^>]+>"#,
            with: " ",
            options: [.regularExpression]
        )
        body = decodeHTMLEntities(body)

        let noisePhrases = [
            "open app", "download", "sign in", "log in", "cookie", "privacy",
            "xiaohongshu", "rednote", "小红书", "打开app", "下载app", "登录", "注册",
            "copyright", "terms", "service"
        ]

        var results: [String] = []

        for line in body.components(separatedBy: .newlines) {
            let cleaned = cleanPageText(line)
            guard cleaned.count >= 4, cleaned.count <= 180 else { continue }

            let lowercased = cleaned.lowercased()
            guard !noisePhrases.contains(where: { lowercased.contains($0) }) else { continue }
            guard !results.contains(cleaned) else { continue }
            results.append(cleaned)
        }

        return results
    }

    private func downloadImages(from urls: [URL]) async -> [UIImage] {
        var images: [UIImage] = []

        for url in urls {
            guard images.count < 6 else { break }

            do {
                var request = URLRequest(url: url)
                request.setValue("image/*", forHTTPHeaderField: "Accept")
                let (data, response) = try await session.data(for: request)

                guard let response = response as? HTTPURLResponse,
                      (200..<300).contains(response.statusCode),
                      let image = UIImage(data: data) else {
                    continue
                }

                images.append(image)
            } catch {
                continue
            }
        }

        return images
    }

    private func htmlMatches(
        in value: String,
        pattern: String,
        options: NSRegularExpression.Options = []
    ) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return []
        }

        let range = NSRange(value.startIndex..., in: value)
        return regex.matches(in: value, options: [], range: range).compactMap { match in
            guard let matchRange = Range(match.range, in: value) else { return nil }
            return String(value[matchRange])
        }
    }

    private func firstCapture(
        in value: String,
        pattern: String,
        options: NSRegularExpression.Options = []
    ) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return nil
        }

        let range = NSRange(value.startIndex..., in: value)
        guard let match = regex.firstMatch(in: value, options: [], range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: value) else {
            return nil
        }

        return String(value[captureRange])
    }

    private func htmlAttributes(in tag: String) -> [String: String] {
        guard let regex = try? NSRegularExpression(
            pattern: #"([A-Za-z_:][-A-Za-z0-9_:.]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#,
            options: []
        ) else {
            return [:]
        }

        let range = NSRange(tag.startIndex..., in: tag)
        var attributes: [String: String] = [:]

        for match in regex.matches(in: tag, options: [], range: range) {
            guard let keyRange = Range(match.range(at: 1), in: tag) else { continue }

            let key = String(tag[keyRange]).lowercased()
            let valueRangeIndex = [2, 3, 4].first { match.range(at: $0).location != NSNotFound }
            guard let valueRangeIndex,
                  let valueRange = Range(match.range(at: valueRangeIndex), in: tag) else {
                continue
            }

            attributes[key] = String(tag[valueRange])
        }

        return attributes
    }

    private func normalizedURL(from rawValue: String, baseURL: URL) -> URL? {
        let cleaned = decodeHTMLEntities(rawValue)
            .replacingOccurrences(of: #"\\/"#, with: "/", options: .regularExpression)
            .replacingOccurrences(of: #"\\u002F"#, with: "/", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty else { return nil }

        if cleaned.hasPrefix("//") {
            return URL(string: baseURL.scheme.map { "\($0):" + cleaned } ?? "https:" + cleaned)
        }

        if let absoluteURL = URL(string: cleaned), absoluteURL.scheme != nil {
            return absoluteURL
        }

        return URL(string: cleaned, relativeTo: baseURL)?.absoluteURL
    }

    private func uniqueURLs(_ urls: [URL]) -> [URL] {
        var seen: Set<String> = []
        var results: [URL] = []

        for url in urls {
            let key = url.absoluteString
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            results.append(url)
        }

        return results
    }

    private func videoURLs(
        from html: String,
        baseURL: URL,
        metaValues: [String: [String]]
    ) -> [URL] {
        var candidates: [URL] = []

        let metaVideoKeys = [
            "og:video",
            "og:video:url",
            "og:video:secure_url",
            "twitter:player:stream"
        ]

        for key in metaVideoKeys {
            for value in metaValues[key] ?? [] {
                if let url = normalizedURL(from: value, baseURL: baseURL) {
                    candidates.append(url)
                }
            }
        }

        let rawPatterns = [
            #"https?://[^"'\\s<>]+(?:mp4|m3u8)(?:\?[^"'\\s<>]*)?"#,
            #"https?:\\\/\\\/[^"'\\s<>]+(?:mp4|m3u8)(?:\?[^"'\\s<>]*)?"#
        ]

        for pattern in rawPatterns {
            for match in htmlMatches(in: html, pattern: pattern, options: [.caseInsensitive]) {
                if let url = normalizedURL(from: match, baseURL: baseURL) {
                    candidates.append(url)
                }
            }
        }

        let keyedPatterns = [
            #""(?:masterUrl|playUrl|h264Url|h265Url|videoUrl|originVideoKey|url)"\s*:\s*"([^"]+?(?:mp4|m3u8)[^"]*)""#,
            #"'(?:masterUrl|playUrl|h264Url|h265Url|videoUrl|originVideoKey|url)'\s*:\s*'([^']+?(?:mp4|m3u8)[^']*)'"#
        ]

        for pattern in keyedPatterns {
            if let capture = firstCapture(in: html, pattern: pattern, options: [.caseInsensitive]),
               let url = normalizedURL(from: capture, baseURL: baseURL) {
                candidates.append(url)
            }
        }

        return candidates
    }

    private func firstNonEmpty(_ values: [String?]) -> String? {
        values
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    private func cleanPageText(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func decodeHTMLEntities(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }
}

private struct RecipePageMetadata {
    let title: String
    let description: String
    let imageURLs: [URL]
    let videoURLs: [URL]
    let bodyLines: [String]
}
