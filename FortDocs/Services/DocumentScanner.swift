import Foundation
import VisionKit
import Vision
import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

class DocumentScanner: ObservableObject {
    
    @Published var isProcessing = false
    @Published var processingProgress: Double = 0.0
    
    private let imageProcessor = ImageProcessor()
    private let ocrEngine = OCREngine()
    private let documentClassifier = DocumentClassifier()
    
    init() {}
    
    // MARK: - Public Methods
    
    func processScannedImages(_ images: [UIImage], completion: @escaping (Result<[ProcessedDocument], DocumentScannerError>) -> Void) {
        isProcessing = true
        processingProgress = 0.0
        
        Task {
            do {
                var processedDocuments: [ProcessedDocument] = []
                let totalImages = images.count
                
                for (index, image) in images.enumerated() {
                    await MainActor.run {
                        self.processingProgress = Double(index) / Double(totalImages)
                    }
                    
                    let processedDocument = try await processImage(image, pageNumber: index + 1)
                    processedDocuments.append(processedDocument)
                }
                
                await MainActor.run {
                    self.isProcessing = false
                    self.processingProgress = 1.0
                    completion(.success(processedDocuments))
                }
                
            } catch {
                await MainActor.run {
                    self.isProcessing = false
                    self.processingProgress = 0.0
                    completion(.failure(error as? DocumentScannerError ?? .processingFailed))
                }
            }
        }
    }
    
    func performOCR(on image: UIImage, completion: @escaping (Result<OCRResult, DocumentScannerError>) -> Void) {
        Task {
            do {
                let result = try await ocrEngine.extractText(from: image)
                await MainActor.run {
                    completion(.success(result))
                }
            } catch {
                await MainActor.run {
                    completion(.failure(.ocrFailed))
                }
            }
        }
    }
    
    func enhanceImage(_ image: UIImage, completion: @escaping (Result<UIImage, DocumentScannerError>) -> Void) {
        Task {
            do {
                let enhancedImage = try await imageProcessor.enhanceDocument(image)
                await MainActor.run {
                    completion(.success(enhancedImage))
                }
            } catch {
                await MainActor.run {
                    completion(.failure(.imageProcessingFailed))
                }
            }
        }
    }
    
    func detectDocumentType(from ocrText: String, image: UIImage? = nil) -> DocumentClassification {
        return documentClassifier.classify(text: ocrText, image: image)
    }
    
    func generateThumbnail(from image: UIImage, size: CGSize = CGSize(width: 200, height: 200)) -> UIImage? {
        return imageProcessor.generateThumbnail(from: image, size: size)
    }
    
    // MARK: - Private Methods
    
    private func processImage(_ image: UIImage, pageNumber: Int) async throws -> ProcessedDocument {
        // Step 1: Enhance image quality
        let enhancedImage = try await imageProcessor.enhanceDocument(image)
        
        // Step 2: Perform OCR
        let ocrResult = try await ocrEngine.extractText(from: enhancedImage)
        
        // Step 3: Classify document type
        let classification = documentClassifier.classify(text: ocrResult.text, image: enhancedImage)
        
        // Step 4: Generate thumbnail
        let thumbnail = imageProcessor.generateThumbnail(from: enhancedImage)
        
        // Step 5: Extract metadata
        let metadata = extractMetadata(from: ocrResult, classification: classification)
        
        return ProcessedDocument(
            id: UUID(),
            originalImage: image,
            enhancedImage: enhancedImage,
            thumbnail: thumbnail,
            ocrResult: ocrResult,
            classification: classification,
            metadata: metadata,
            pageNumber: pageNumber
        )
    }
    
    private func extractMetadata(from ocrResult: OCRResult, classification: DocumentClassification) -> DocumentMetadata {
        var metadata = DocumentMetadata()
        
        // Extract common metadata based on document type
        switch classification.type {
        case .invoice:
            metadata = extractInvoiceMetadata(from: ocrResult.text)
        case .receipt:
            metadata = extractReceiptMetadata(from: ocrResult.text)
        case .identity:
            metadata = extractIdentityMetadata(from: ocrResult.text)
        case .certificate:
            metadata = extractCertificateMetadata(from: ocrResult.text)
        case .contract:
            metadata = extractContractMetadata(from: ocrResult.text)
        case .general:
            metadata = extractGeneralMetadata(from: ocrResult.text)
        }
        
        return metadata
    }
    
    private func extractInvoiceMetadata(from text: String) -> DocumentMetadata {
        var metadata = DocumentMetadata()
        
        // Extract invoice number
        if let invoiceNumber = extractPattern(from: text, pattern: #"(?:Invoice|INV)[\s#:]*([A-Z0-9-]+)"#) {
            metadata.invoiceNumber = invoiceNumber
        }
        
        // Extract amount
        if let amount = extractPattern(from: text, pattern: #"(?:Total|Amount|Due)[\s:$]*([0-9,]+\.?[0-9]*)"#) {
            metadata.amount = amount
        }
        
        // Extract date
        if let date = extractDate(from: text) {
            metadata.date = date
        }
        
        // Extract vendor
        if let vendor = extractVendor(from: text) {
            metadata.vendor = vendor
        }
        
        return metadata
    }
    
    private func extractReceiptMetadata(from text: String) -> DocumentMetadata {
        var metadata = DocumentMetadata()
        
        // Extract merchant name (usually at the top)
        let lines = text.components(separatedBy: .newlines)
        if let firstLine = lines.first, !firstLine.isEmpty {
            metadata.merchant = firstLine.trimmingCharacters(in: .whitespacesAndPunctuationMarks)
        }
        
        // Extract total amount
        if let total = extractPattern(from: text, pattern: #"(?:Total|TOTAL)[\s:$]*([0-9,]+\.?[0-9]*)"#) {
            metadata.amount = total
        }
        
        // Extract date
        if let date = extractDate(from: text) {
            metadata.date = date
        }
        
        return metadata
    }
    
    private func extractIdentityMetadata(from text: String) -> DocumentMetadata {
        var metadata = DocumentMetadata()
        
        // Extract name
        if let name = extractPattern(from: text, pattern: #"(?:Name|NAME)[\s:]*([A-Za-z\s]+)"#) {
            metadata.fullName = name
        }
        
        // Extract ID number
        if let idNumber = extractPattern(from: text, pattern: #"(?:ID|Number|No)[\s:#]*([A-Z0-9-]+)"#) {
            metadata.idNumber = idNumber
        }
        
        // Extract expiration date
        if let expiration = extractPattern(from: text, pattern: #"(?:Exp|Expires|Expiration)[\s:]*([0-9/\-]+)"#) {
            metadata.expirationDate = expiration
        }
        
        return metadata
    }
    
    private func extractCertificateMetadata(from text: String) -> DocumentMetadata {
        var metadata = DocumentMetadata()
        
        // Extract certificate title
        let lines = text.components(separatedBy: .newlines)
        for line in lines.prefix(5) {
            if line.lowercased().contains("certificate") {
                metadata.title = line.trimmingCharacters(in: .whitespacesAndPunctuationMarks)
                break
            }
        }
        
        // Extract recipient name
        if let name = extractPattern(from: text, pattern: #"(?:awarded to|presented to|this certifies that)[\s:]*([A-Za-z\s]+)"#) {
            metadata.recipientName = name
        }
        
        // Extract date
        if let date = extractDate(from: text) {
            metadata.date = date
        }
        
        return metadata
    }
    
    private func extractContractMetadata(from text: String) -> DocumentMetadata {
        var metadata = DocumentMetadata()
        
        // Extract contract title
        let lines = text.components(separatedBy: .newlines)
        if let titleLine = lines.first(where: { $0.lowercased().contains("agreement") || $0.lowercased().contains("contract") }) {
            metadata.title = titleLine.trimmingCharacters(in: .whitespacesAndPunctuationMarks)
        }
        
        // Extract parties
        if let parties = extractPattern(from: text, pattern: #"(?:between|parties)[\s:]*([A-Za-z\s,&]+)"#) {
            metadata.parties = parties
        }
        
        // Extract date
        if let date = extractDate(from: text) {
            metadata.date = date
        }
        
        return metadata
    }
    
    private func extractGeneralMetadata(from text: String) -> DocumentMetadata {
        var metadata = DocumentMetadata()
        
        // Extract title (first non-empty line)
        let lines = text.components(separatedBy: .newlines)
        if let titleLine = lines.first(where: { !$0.trimmingCharacters(in: .whitespacesAndPunctuationMarks).isEmpty }) {
            metadata.title = titleLine.trimmingCharacters(in: .whitespacesAndPunctuationMarks)
        }
        
        // Extract date
        if let date = extractDate(from: text) {
            metadata.date = date
        }
        
        return metadata
    }
    
    private func extractPattern(from text: String, pattern: String) -> String? {
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            let range = NSRange(text.startIndex..., in: text)
            
            if let match = regex.firstMatch(in: text, options: [], range: range),
               let matchRange = Range(match.range(at: 1), in: text) {
                return String(text[matchRange]).trimmingCharacters(in: .whitespacesAndPunctuationMarks)
            }
        } catch {
            print("Regex error: \(error)")
        }
        
        return nil
    }
    
    private func extractDate(from text: String) -> String? {
        let datePatterns = [
            #"([0-9]{1,2}[/\-][0-9]{1,2}[/\-][0-9]{2,4})"#,
            #"([0-9]{1,2}\s+[A-Za-z]+\s+[0-9]{2,4})"#,
            #"([A-Za-z]+\s+[0-9]{1,2},?\s+[0-9]{2,4})"#
        ]
        
        for pattern in datePatterns {
            if let date = extractPattern(from: text, pattern: pattern) {
                return date
            }
        }
        
        return nil
    }
    
    private func extractVendor(from text: String) -> String? {
        // Look for vendor name in the first few lines
        let lines = text.components(separatedBy: .newlines)
        
        for line in lines.prefix(5) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndPunctuationMarks)
            if !trimmed.isEmpty && trimmed.count > 3 && !trimmed.contains(where: { $0.isNumber }) {
                return trimmed
            }
        }
        
        return nil
    }
}

// MARK: - Image Processor

private class ImageProcessor {
    
    func enhanceDocument(_ image: UIImage) async throws -> UIImage {
        guard let ciImage = CIImage(image: image) else {
            throw DocumentScannerError.imageProcessingFailed
        }
        
        let context = CIContext()
        
        // Apply document enhancement filters
        var processedImage = ciImage
        
        // 1. Perspective correction (if needed)
        processedImage = try correctPerspective(processedImage)
        
        // 2. Noise reduction
        processedImage = try reduceNoise(processedImage)
        
        // 3. Contrast and brightness adjustment
        processedImage = try adjustContrastAndBrightness(processedImage)
        
        // 4. Sharpen text
        processedImage = try sharpenText(processedImage)
        
        // Convert back to UIImage
        guard let cgImage = context.createCGImage(processedImage, from: processedImage.extent) else {
            throw DocumentScannerError.imageProcessingFailed
        }
        
        return UIImage(cgImage: cgImage)
    }
    
    func generateThumbnail(from image: UIImage, size: CGSize = CGSize(width: 200, height: 200)) -> UIImage? {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
    
    private func correctPerspective(_ image: CIImage) throws -> CIImage {
        // Use CIRectangleDetector to find document bounds
        let detector = CIDetector(ofType: CIDetectorTypeRectangle, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        
        guard let features = detector?.features(in: image) as? [CIRectangleFeature],
              let rectangle = features.first else {
            return image // Return original if no rectangle detected
        }
        
        // Apply perspective correction
        let perspectiveCorrection = CIFilter.perspectiveCorrection()
        perspectiveCorrection.inputImage = image
        perspectiveCorrection.topLeft = rectangle.topLeft
        perspectiveCorrection.topRight = rectangle.topRight
        perspectiveCorrection.bottomLeft = rectangle.bottomLeft
        perspectiveCorrection.bottomRight = rectangle.bottomRight
        
        return perspectiveCorrection.outputImage ?? image
    }
    
    private func reduceNoise(_ image: CIImage) throws -> CIImage {
        let noiseReduction = CIFilter.noiseReduction()
        noiseReduction.inputImage = image
        noiseReduction.noiseLevel = 0.02
        noiseReduction.sharpness = 0.4
        
        return noiseReduction.outputImage ?? image
    }
    
    private func adjustContrastAndBrightness(_ image: CIImage) throws -> CIImage {
        let colorControls = CIFilter.colorControls()
        colorControls.inputImage = image
        colorControls.contrast = 1.2
        colorControls.brightness = 0.1
        colorControls.saturation = 0.8
        
        return colorControls.outputImage ?? image
    }
    
    private func sharpenText(_ image: CIImage) throws -> CIImage {
        let sharpen = CIFilter.sharpenLuminance()
        sharpen.inputImage = image
        sharpen.sharpness = 0.4
        
        return sharpen.outputImage ?? image
    }
}

// MARK: - OCR Engine

private class OCREngine {
    
    func extractText(from image: UIImage) async throws -> OCRResult {
        guard let cgImage = image.cgImage else {
            throw DocumentScannerError.ocrFailed
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(throwing: DocumentScannerError.ocrFailed)
                    return
                }
                
                let result = self.processOCRObservations(observations)
                continuation.resume(returning: result)
            }
            
            // Configure OCR request for better accuracy
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["en-US"]
            request.usesLanguageCorrection = true
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    private func processOCRObservations(_ observations: [VNRecognizedTextObservation]) -> OCRResult {
        var fullText = ""
        var textBlocks: [TextBlock] = []
        var confidence: Float = 0.0
        
        for observation in observations {
            guard let topCandidate = observation.topCandidates(1).first else { continue }
            
            let text = topCandidate.string
            let boundingBox = observation.boundingBox
            
            fullText += text + "\n"
            confidence += topCandidate.confidence
            
            let textBlock = TextBlock(
                text: text,
                boundingBox: boundingBox,
                confidence: topCandidate.confidence
            )
            textBlocks.append(textBlock)
        }
        
        // Calculate average confidence
        if !observations.isEmpty {
            confidence /= Float(observations.count)
        }
        
        return OCRResult(
            text: fullText.trimmingCharacters(in: .whitespacesAndNewlines),
            textBlocks: textBlocks,
            confidence: confidence
        )
    }
}

// MARK: - Document Classifier

private class DocumentClassifier {
    
    func classify(text: String, image: UIImage? = nil) -> DocumentClassification {
        let lowercasedText = text.lowercased()
        
        // Define classification rules
        let classifications: [(DocumentType, [String], Double)] = [
            (.invoice, ["invoice", "bill", "billing", "payment due", "amount due", "inv#"], 0.8),
            (.receipt, ["receipt", "thank you", "total", "subtotal", "tax", "change"], 0.7),
            (.identity, ["driver license", "passport", "id card", "identification", "date of birth"], 0.9),
            (.certificate, ["certificate", "diploma", "award", "completion", "achievement"], 0.8),
            (.contract, ["agreement", "contract", "terms", "conditions", "parties", "whereas"], 0.8)
        ]
        
        var bestMatch: DocumentClassification?
        var highestScore = 0.0
        
        for (type, keywords, baseScore) in classifications {
            let matchCount = keywords.reduce(0) { count, keyword in
                return count + (lowercasedText.contains(keyword) ? 1 : 0)
            }
            
            if matchCount > 0 {
                let score = baseScore * (Double(matchCount) / Double(keywords.count))
                
                if score > highestScore {
                    highestScore = score
                    bestMatch = DocumentClassification(
                        type: type,
                        confidence: score,
                        suggestedTitle: generateTitle(for: type, from: text),
                        suggestedFolder: type.defaultFolderName,
                        extractedKeywords: keywords.filter { lowercasedText.contains($0) }
                    )
                }
            }
        }
        
        // Default to general document if no specific type detected
        return bestMatch ?? DocumentClassification(
            type: .general,
            confidence: 0.5,
            suggestedTitle: generateTitle(for: .general, from: text),
            suggestedFolder: "Documents",
            extractedKeywords: []
        )
    }
    
    private func generateTitle(for type: DocumentType, from text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndPunctuationMarks) }
            .filter { !$0.isEmpty }
        
        switch type {
        case .invoice:
            // Look for invoice number or company name
            for line in lines.prefix(5) {
                if line.lowercased().contains("invoice") {
                    return line
                }
            }
            return "Invoice - \(Date().formatted(date: .abbreviated, time: .omitted))"
            
        case .receipt:
            // Use merchant name if available
            if let firstLine = lines.first, firstLine.count > 3 {
                return "Receipt - \(firstLine)"
            }
            return "Receipt - \(Date().formatted(date: .abbreviated, time: .omitted))"
            
        case .identity:
            return "ID Document - \(Date().formatted(date: .abbreviated, time: .omitted))"
            
        case .certificate:
            // Look for certificate title
            for line in lines.prefix(3) {
                if line.lowercased().contains("certificate") {
                    return line
                }
            }
            return "Certificate - \(Date().formatted(date: .abbreviated, time: .omitted))"
            
        case .contract:
            // Look for agreement title
            for line in lines.prefix(3) {
                if line.lowercased().contains("agreement") || line.lowercased().contains("contract") {
                    return line
                }
            }
            return "Contract - \(Date().formatted(date: .abbreviated, time: .omitted))"
            
        case .general:
            // Use first meaningful line
            if let firstLine = lines.first, firstLine.count > 3 {
                return firstLine
            }
            return "Document - \(Date().formatted(date: .abbreviated, time: .omitted))"
        }
    }
}

// MARK: - Supporting Types

struct ProcessedDocument {
    let id: UUID
    let originalImage: UIImage
    let enhancedImage: UIImage
    let thumbnail: UIImage?
    let ocrResult: OCRResult
    let classification: DocumentClassification
    let metadata: DocumentMetadata
    let pageNumber: Int
}

struct OCRResult {
    let text: String
    let textBlocks: [TextBlock]
    let confidence: Float
}

struct TextBlock {
    let text: String
    let boundingBox: CGRect
    let confidence: Float
}

struct DocumentClassification {
    let type: DocumentType
    let confidence: Double
    let suggestedTitle: String
    let suggestedFolder: String
    let extractedKeywords: [String]
}

enum DocumentType {
    case invoice
    case receipt
    case identity
    case certificate
    case contract
    case general
    
    var defaultFolderName: String {
        switch self {
        case .invoice:
            return "Invoices"
        case .receipt:
            return "Receipts"
        case .identity:
            return "IDs"
        case .certificate:
            return "Certificates"
        case .contract:
            return "Documents"
        case .general:
            return "Documents"
        }
    }
}

struct DocumentMetadata {
    var title: String?
    var date: String?
    var amount: String?
    var vendor: String?
    var merchant: String?
    var invoiceNumber: String?
    var fullName: String?
    var idNumber: String?
    var expirationDate: String?
    var recipientName: String?
    var parties: String?
}

enum DocumentScannerError: LocalizedError {
    case processingFailed
    case ocrFailed
    case imageProcessingFailed
    case noDocumentDetected
    
    var errorDescription: String? {
        switch self {
        case .processingFailed:
            return "Failed to process document"
        case .ocrFailed:
            return "Failed to extract text from document"
        case .imageProcessingFailed:
            return "Failed to enhance document image"
        case .noDocumentDetected:
            return "No document detected in image"
        }
    }
}

