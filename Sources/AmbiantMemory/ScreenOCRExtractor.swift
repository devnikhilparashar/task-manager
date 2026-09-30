import Foundation
import ScreenCaptureKit
import Vision

struct ScreenOCRExtractor: ScreenTextExtracting {
    enum CaptureError: Error { case windowUnavailable, imageUnavailable }

    func extract(window context: ActiveWindowContext) async throws -> OCRSnapshot {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        guard let window = content.windows.first(where: {
            $0.owningApplication?.processID == context.pid &&
            (context.windowTitle.isEmpty || $0.title == context.windowTitle)
        }) ?? content.windows.first(where: { $0.owningApplication?.processID == context.pid }) else {
            throw CaptureError.windowUnavailable
        }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        configuration.width = max(1, Int(window.frame.width * 2))
        configuration.height = max(1, Int(window.frame.height * 2))
        configuration.showsCursor = false
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let request = VNRecognizeTextRequest { request, error in
                    if let error { continuation.resume(throwing: error); return }
                    let results = (request.results as? [VNRecognizedTextObservation]) ?? []
                    let candidates = results.compactMap { $0.topCandidates(1).first }
                    let confidence = candidates.isEmpty ? 0 : candidates.reduce(0) { $0 + Double($1.confidence) } / Double(candidates.count)
                    continuation.resume(returning: OCRSnapshot(text: candidates.map(\.string), averageConfidence: confidence))
                }
                request.recognitionLevel = .accurate
                request.automaticallyDetectsLanguage = true
                request.usesLanguageCorrection = true
                do { try VNImageRequestHandler(cgImage: image).perform([request]) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }
}
