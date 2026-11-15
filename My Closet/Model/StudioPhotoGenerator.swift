import UIKit

/// Turns a rough cutout of a worn piece (ragged edges, bits hidden by arms or a phone) into a
/// clean e-commerce product photo with a cloud image model, then lifts it off its white
/// background so it works as a cutout and sticker like every other piece.
///
/// Only the cutout is uploaded, never the photo it came from. Settings live in the bundled,
/// git-ignored `Secrets.plist`: `StudioProvider` ("gemini" or "openai"), the matching
/// `GeminiAPIKey` / `OpenAIAPIKey`, and optionally `StudioModel` and `StudioQuality` (OpenAI only).
/// Prototype only: a key shipped inside the app can be extracted, so a release build should
/// call a small backend that holds the key instead.
nonisolated enum StudioPhotoGenerator {
    struct Output: Sendable {
        let cutout: UIImage
        let sticker: UIImage
        var aspect: Double { cutout.size.width / max(cutout.size.height, 1) }
    }

    enum StudioError: LocalizedError {
        case notConfigured
        case server(status: Int, message: String)
        case unreadableResponse

        var errorDescription: String? {
            switch self {
            case .notConfigured: "Studio photos aren't set up (no API key in Secrets.plist)."
            case .server(let status, let message): "Studio photo failed (\(status)): \(message)"
            case .unreadableResponse: "Studio photo came back in a form we couldn't read."
            }
        }
    }

    private enum Provider { case gemini, openAI }

    private struct Settings {
        let provider: Provider
        let apiKey: String
        let model: String
        let quality: String
    }

    private static let settings: Settings? = {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let values = NSDictionary(contentsOf: url) as? [String: Any]
        else { return nil }
        func value(_ key: String) -> String? {
            (values[key] as? String).flatMap { $0.isEmpty ? nil : $0 }
        }
        if value("StudioProvider")?.lowercased() == "openai" {
            guard let key = value("OpenAIAPIKey") else { return nil }
            return Settings(provider: .openAI, apiKey: key, model: value("StudioModel") ?? "gpt-image-1-mini",
                            quality: value("StudioQuality") ?? "medium")
        }
        guard let key = value("GeminiAPIKey") else { return nil }
        return Settings(provider: .gemini, apiKey: key, model: value("StudioModel") ?? "gemini-nano-banana-2.1",
                        quality: "")
    }()

    static var isConfigured: Bool { settings != nil }

    /// A ready-to-send request: everything a background upload task needs.
    struct Job: Sendable {
        let request: URLRequest
        let body: Data
    }

    /// Builds the upload for one piece. Sent by `StudioUploader`, which keeps going in the
    /// background; the reply is turned into images by `output(from:status:)`.
    static func job(for cutout: UIImage, category: String) throws -> Job {
        guard let settings else { throw StudioError.notConfigured }
        guard let upload = squareOnWhite(cutout, side: 1024).pngData() else { throw StudioError.unreadableResponse }
        switch settings.provider {
        case .gemini:
            var request = URLRequest(url: URL(string:
                "https://generativelanguage.googleapis.com/v1beta/models/\(settings.model):generateContent")!)
            request.httpMethod = "POST"
            request.setValue(settings.apiKey, forHTTPHeaderField: "x-goog-api-key")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let body: [String: Any] = [
                "contents": [["parts": [
                    ["text": prompt(for: category, transparent: false)],
                    ["inline_data": ["mime_type": "image/png", "data": upload.base64EncodedString()]],
                ]]],
                "generationConfig": [
                    "responseModalities": ["IMAGE"],
                    "imageConfig": ["aspectRatio": "1:1"],
                ],
            ]
            return Job(request: request, body: try JSONSerialization.data(withJSONObject: body))
        case .openAI:
            var request = URLRequest(url: URL(string: "https://api.openai.com/v1/images/edits")!)
            request.httpMethod = "POST"
            request.setValue("Bearer \(settings.apiKey)", forHTTPHeaderField: "Authorization")
            var form = MultipartForm()
            form.add("model", settings.model)
            form.add("prompt", prompt(for: category, transparent: true))
            form.add("size", "1024x1024")
            form.add("quality", settings.quality)
            form.add("n", "1")
            form.add("background", "transparent")
            form.add("output_format", "png")
            form.addFile("image[]", filename: "piece.png", type: "image/png", data: upload)
            request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
            return Job(request: request, body: form.finished)
        }
    }

    /// Turns the provider's reply into a cutout and sticker.
    static func output(from data: Data, status: Int) throws -> Output {
        guard let settings else { throw StudioError.notConfigured }
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard status == 200 else {
            let message = (json?["error"] as? [String: Any])?["message"] as? String ?? "no details"
            throw StudioError.server(status: status, message: message)
        }
        let imageData: Data?
        switch settings.provider {
        case .gemini:
            // REST responses use camelCase; accept snake_case too.
            let parts = ((json?["candidates"] as? [[String: Any]])?.first?["content"] as? [String: Any])?["parts"]
                as? [[String: Any]] ?? []
            imageData = parts.lazy.compactMap { part -> Data? in
                let inline = (part["inlineData"] ?? part["inline_data"]) as? [String: Any]
                return (inline?["data"] as? String).flatMap { Data(base64Encoded: $0) }
            }.first
        case .openAI:
            imageData = ((json?["data"] as? [[String: Any]])?.first?["b64_json"] as? String)
                .flatMap { Data(base64Encoded: $0) }
        }
        // OpenAI returns a transparent PNG; Gemini's white background is lifted off here.
        guard let photo = imageData.flatMap({ UIImage(data: $0)?.cgImage }),
              let lifted = settings.provider == .openAI
                ? trimmedToContent(photo)
                : ClothingAnalyzer.liftLargestSubject(photo) ?? removeWhiteBackground(photo),
              let sticker = ClothingAnalyzer.sticker(for: lifted)
        else { throw StudioError.unreadableResponse }
        return Output(cutout: UIImage(cgImage: lifted), sticker: UIImage(cgImage: sticker))
    }

    // MARK: - Prompt

    private static func prompt(for category: String, transparent: Bool) -> String {
        let (item, pose): (String, String) = switch category {
        case "shoes": ("pair of shoes", "both shoes side by side in a three-quarter side view")
        case "bags": ("bag", "standing upright, front view, handles or strap neatly arranged")
        case "bottoms": ("bottoms", "front view, as a neat ghost-mannequin shot with natural volume")
        case "dresses": ("dress", "front view, as a neat ghost-mannequin shot with natural volume")
        case "outerwear": ("jacket or coat", "front view, as a neat ghost-mannequin shot with natural volume")
        default: ("top", "front view, as a neat ghost-mannequin shot with natural volume")
        }
        return """
        The image is a \(item) cut out of a photo of someone wearing it, so parts may be ragged, \
        cropped or hidden, and stray background colour may show at the edges. Create a \
        professional e-commerce product photo of this exact \(item). Keep it faithful: the same \
        colour, fabric, texture, trims and proportions. Only include a logo, print, text or \
        graphic if one is clearly visible on the garment itself; never invent one, and treat \
        colour at the ragged edges as background, not part of the \(item). Show it alone, \(pose), \
        complete and neatly shaped, filling in hidden or missing parts naturally. No person, skin, \
        hair, hands, phone, hanger, mannequin or props. Centred with a generous margin, soft even \
        studio lighting, on \(transparent ? "a fully transparent background" : "a plain pure white (#FFFFFF) background") \
        with no shadow.
        """
    }

    // MARK: - Images

    /// The cutout centred on a white square, so the model sees the whole piece with margin.
    private static func squareOnWhite(_ image: UIImage, side: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: side, height: side))
            let inner = side * 0.86
            let scale = min(inner / image.size.width, inner / image.size.height)
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            image.draw(in: CGRect(x: (side - size.width) / 2, y: (side - size.height) / 2,
                                  width: size.width, height: size.height))
        }
    }

    /// Crops a transparent image to its visible pixels.
    private static func trimmedToContent(_ image: CGImage) -> CGImage? {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where pixels[(y * width + x) * 4 + 3] > 8 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX else { return nil }
        return image.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))
    }

    /// Fallback when Vision can't lift (the Simulator): clears the near-white background by
    /// flooding in from the edges, so white areas inside the piece survive, then crops tight.
    static func removeWhiteBackground(_ image: CGImage) -> CGImage? {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        func isBackground(_ i: Int) -> Bool {
            pixels[i * 4] > 238 && pixels[i * 4 + 1] > 238 && pixels[i * 4 + 2] > 238
        }
        var cleared = [Bool](repeating: false, count: width * height)
        var stack: [Int] = []
        for x in 0..<width { stack += [x, (height - 1) * width + x] }
        for y in 0..<height { stack += [y * width, y * width + width - 1] }
        while let i = stack.popLast() {
            guard !cleared[i], isBackground(i) else { continue }
            cleared[i] = true
            let x = i % width, y = i / width
            if x > 0 { stack.append(i - 1) }
            if x < width - 1 { stack.append(i + 1) }
            if y > 0 { stack.append(i - width) }
            if y < height - 1 { stack.append(i + width) }
        }
        var minX = width, minY = height, maxX = -1, maxY = -1
        for i in 0..<(width * height) {
            if cleared[i] {
                pixels[i * 4] = 0; pixels[i * 4 + 1] = 0; pixels[i * 4 + 2] = 0; pixels[i * 4 + 3] = 0
            } else {
                let x = i % width, y = i / width
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, let keyed = context.makeImage() else { return nil }
        return keyed.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))
    }
}

/// A minimal multipart/form-data body.
nonisolated private struct MultipartForm {
    private let boundary = "ClosetAi-\(UUID().uuidString)"
    private(set) var body = Data()

    var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    mutating func add(_ name: String, _ value: String) {
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
    }

    mutating func addFile(_ name: String, filename: String, type: String, data: Data) {
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\nContent-Type: \(type)\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n".utf8))
    }

    var finished: Data { body + Data("--\(boundary)--\r\n".utf8) }
}
