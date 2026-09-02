import Vision
import UIKit
enum OCRService {
 static func recognize(_ image:UIImage) async throws -> String {guard let cg = image.cgImage else{return ""};return try await withCheckedThrowingContinuation{c in let r = VNRecognizeTextRequest{req,e in if let e{c.resume(throwing:e);return};let lines = (req.results as? [VNRecognizedTextObservation])?.compactMap{$0.topCandidates(1).first?.string} ?? [];c.resume(returning:lines.joined(separator:"\n"))};r.recognitionLevel = .accurate;r.usesLanguageCorrection = true;r.recognitionLanguages = ["ru-RU","cs-CZ","en-US"];do{try VNImageRequestHandler(cgImage:cg).perform([r])}catch{c.resume(throwing:error)}}}
}
