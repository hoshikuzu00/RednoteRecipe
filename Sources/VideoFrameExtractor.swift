import AVFoundation
import Foundation
import UIKit
import Vision

enum VideoFrameExtractorError: LocalizedError {
    case invalidVideo
    case frameExtractionFailed

    var errorDescription: String? {
        switch self {
        case .invalidVideo:
            return "The selected video could not be opened."
        case .frameExtractionFailed:
            return "The app could not extract usable frames from this video."
        }
    }
}

enum VideoFrameExtractor {
    private static let maxFrames = 50
    private static let sampleInterval = 0.3

    private struct FrameTextAnalysis {
        let text: String
        let signature: String
        let score: Double
    }

    static func extractFrames(fromVideoData data: Data) async throws -> [UIImage] {
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")

        try data.write(to: temporaryURL, options: .atomic)

        defer {
            try? FileManager.default.removeItem(at: temporaryURL)
        }

        return try await extractFrames(from: temporaryURL)
    }

    static func extractFrames(from url: URL) async throws -> [UIImage] {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        return try await Task.detached(priority: .userInitiated) {
            try extractFramesSynchronously(from: url)
        }.value
    }

    private static func extractFramesSynchronously(from url: URL) throws -> [UIImage] {
        let asset = AVURLAsset(url: url)
        let durationSeconds = CMTimeGetSeconds(asset.duration)

        guard durationSeconds.isFinite, durationSeconds > 0 else {
            throw VideoFrameExtractorError.invalidVideo
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1280, height: 1280)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.1, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.1, preferredTimescale: 600)

        let sampleTimes = makeSampleTimes(duration: durationSeconds)
        var acceptedImages: [UIImage] = []
        var currentBestImage: UIImage?
        var currentBestAnalysis: FrameTextAnalysis?

        for time in sampleTimes {
            guard let image = try? generateImage(at: time, with: generator),
                  let analysis = analyzeText(in: image) else {
                continue
            }

            if let currentBest = currentBestAnalysis {
                if analysis.signature == currentBest.signature {
                    if analysis.score > currentBest.score {
                        currentBestImage = image
                        currentBestAnalysis = analysis
                    }
                } else {
                    if let currentBestImage {
                        acceptedImages.append(currentBestImage)
                    }
                    currentBestImage = image
                    currentBestAnalysis = analysis
                }
            } else {
                currentBestImage = image
                currentBestAnalysis = analysis
            }
        }

        if let currentBestImage {
            acceptedImages.append(currentBestImage)
        }

        if acceptedImages.isEmpty,
           let fallbackImage = try? generateImage(at: CMTime(seconds: min(0.1, durationSeconds / 2), preferredTimescale: 600), with: generator),
           analyzeText(in: fallbackImage) != nil {
            acceptedImages = [fallbackImage]
        }

        guard !acceptedImages.isEmpty else {
            throw VideoFrameExtractorError.frameExtractionFailed
        }

        return evenlySample(acceptedImages, maxCount: maxFrames)
    }

    private static func generateImage(
        at time: CMTime,
        with generator: AVAssetImageGenerator
    ) throws -> UIImage {
        let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
        return UIImage(cgImage: cgImage)
    }

    private static func makeSampleTimes(duration: Double) -> [CMTime] {
        var seconds: [Double] = [0.1]
        var current = sampleInterval

        while current < duration {
            seconds.append(current)
            current += sampleInterval
        }

        let uniqueTimes = Array(Set(seconds))
            .sorted()
            .map { CMTime(seconds: $0, preferredTimescale: 600) }

        return uniqueTimes
    }

    private static func analyzeText(in image: UIImage) -> FrameTextAnalysis? {
        guard let cgImage = image.cgImage else { return nil }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.minimumTextHeight = 0.012
        request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        do {
            try handler.perform([request])
            let observations = request.results ?? []
            var lines: [String] = []
            var confidences: [Float] = []
            var totalArea: CGFloat = 0
            var maxArea: CGFloat = 0
            var maxWidth: CGFloat = 0

            for observation in observations {
                guard let candidate = observation.topCandidates(1).first else {
                    continue
                }

                let line = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !line.isEmpty else {
                    continue
                }

                lines.append(line)
                confidences.append(candidate.confidence)

                let box = observation.boundingBox
                let area = box.width * box.height
                totalArea += area
                maxArea = max(maxArea, area)
                maxWidth = max(maxWidth, box.width)
            }

            guard !lines.isEmpty else { return nil }

            let combinedText = lines.joined(separator: "\n")
            let signature = normalizedTextSignature(from: combinedText)

            guard isMeaningfulText(
                signature: signature,
                rawText: combinedText,
                lineCount: lines.count,
                totalArea: totalArea,
                maxArea: maxArea,
                maxWidth: maxWidth
            ) else {
                return nil
            }

            let averageConfidence = confidences.isEmpty
                ? 0
                : confidences.reduce(0, +) / Float(confidences.count)
            let score = Double(signature.count) + Double(averageConfidence) * 10 + Double(totalArea) * 200

            return FrameTextAnalysis(
                text: combinedText,
                signature: signature,
                score: score
            )
        } catch {
            return nil
        }
    }

    private static func normalizedTextSignature(from recognizedText: String) -> String {
        let normalized = recognizedText
            .lowercased()
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        return String(
            normalized.unicodeScalars.filter { scalar in
                CharacterSet.alphanumerics.contains(scalar)
            }
        )
    }

    private static func isMeaningfulText(
        signature: String,
        rawText: String,
        lineCount: Int,
        totalArea: CGFloat,
        maxArea: CGFloat,
        maxWidth: CGFloat
    ) -> Bool {
        guard !signature.isEmpty else { return false }

        let hanCount = rawText.unicodeScalars.filter { scalar in
            switch scalar.value {
            case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF:
                return true
            default:
                return false
            }
        }.count

        let hasEnoughCharacters = hanCount >= 2 || signature.count >= 4
        let hasEnoughVisualWeight = totalArea >= 0.004 || maxArea >= 0.0015 || maxWidth >= 0.16 || lineCount >= 2

        return hasEnoughCharacters && hasEnoughVisualWeight
    }

    private static func evenlySample(_ images: [UIImage], maxCount: Int) -> [UIImage] {
        guard images.count > maxCount else { return images }

        let lastIndex = images.count - 1
        let step = Double(lastIndex) / Double(maxCount - 1)
        var sampled: [UIImage] = []

        for index in 0..<maxCount {
            let candidateIndex = Int(round(Double(index) * step))
            sampled.append(images[min(candidateIndex, lastIndex)])
        }

        return sampled
    }
}
