import UIKit
import Vision

struct OCRService {
    static func recognize(_ image: UIImage) async throws -> String {
        guard let cg = image.cgImage else { return "" }
        return try await withCheckedThrowingContinuation { cont in
            let req = VNRecognizeTextRequest { request, error in
                if let error { cont.resume(throwing: error); return }
                let text = (request.results as? [VNRecognizedTextObservation])?.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n") ?? ""
                cont.resume(returning: text)
            }
            req.recognitionLevel = .accurate; req.usesLanguageCorrection = true; req.recognitionLanguages = ["cs-CZ","en-US"]
            DispatchQueue.global(qos:.userInitiated).async { do { try VNImageRequestHandler(cgImage: cg).perform([req]) } catch { cont.resume(throwing:error) } }
        }
    }
}
