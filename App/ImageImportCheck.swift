#if DEBUG
import Foundation
import ImageIO

/// Focused, offline checks. Uses a dummy key and intercepts every HTTP request.
enum ImageImportCheck {
    static func run() -> Never {
        Task.detached {
            do {
                try await check()
                print("IMAGE_IMPORT_CHECK_PASSED: board orientation, response validation, request format, HTTP import and invalid key")
                exit(0)
            } catch {
                fputs("IMAGE_IMPORT_CHECK_FAILED: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
        }
        dispatchMain()
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw ImageImportError(message: message) }
    }
    private static func check() async throws {
        // A photo's EXIF rotation must be applied before showing or uploading it.
        let context = CGContext(data: nil, width: 80, height: 120, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 80, height: 120))
        let photo = NSMutableData()
        let destination = CGImageDestinationCreateWithData(photo, "public.jpeg" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, [kCGImagePropertyOrientation: 6] as CFDictionary)
        try require(CGImageDestinationFinalize(destination), "Photo fixture encoding")
        let prepared = try RecognitionImage(data: photo as Data)
        try require(prepared.preview.width == 120 && prepared.preview.height == 80 && prepared.jpeg.prefix(2) == Data([0xff, 0xd8]),
                    "Photo orientation and upload JPEG conversion")
        let redBottom = """
        {"name":"单车残局","bottom_side":"red","side_to_move":"black","pieces":[
          {"side":"black","kind":"king","column":3,"row":0},
          {"side":"red","kind":"king","column":4,"row":9},
          {"side":"red","kind":"rook","column":0,"row":8}],"notes":null}
        """
        let blackBottom = """
        {"bottom_side":"black","side_to_move":null,"pieces":[
          {"side":"black","kind":"king","column":5,"row":9},
          {"side":"red","kind":"king","column":4,"row":0},
          {"side":"red","kind":"rook","column":8,"row":1}]}
        """
        let recognized = try RecognizedSetup.parse(redBottom)
        let flipped = try RecognizedSetup.parse(blackBottom)
        let fen = ChessPosition.fen(pieces: recognized.chessPieces, side: .red)
        try require(fen == "3k5/9/9/9/9/9/9/9/R8/4K4 w - - 0 1", "Red-bottom image coordinates")
        try require(ChessPosition.fen(pieces: flipped.chessPieces, side: .red) == fen, "Black-bottom image rotates both axes")
        try require(recognized.sideToMove == .black && flipped.sideToMove == nil && flipped.reviewMessage.contains("暂选红先"), "First-side recognition and manual review")
        for invalid in [
            redBottom.replacingOccurrences(of: "\"column\":0", with: "\"column\":9"),
            redBottom.replacingOccurrences(of: "\"row\":8", with: "\"row\":10"),
            redBottom.replacingOccurrences(of: "\"column\":0,\"row\":8", with: "\"column\":4,\"row\":9"),
            redBottom.replacingOccurrences(of: "\"rook\"", with: "\"dragon\""),
            "{\"bottom_side\":\"red\",\"pieces\":[]}",
            "not json"
        ] {
            do {
                _ = try RecognizedSetup.parse(invalid)
                throw NSError(domain: "ImageImportCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid model response was accepted"])
            } catch is ImageImportError { /* Expected. */ }
        }

        let jpeg = prepared.jpeg
        let request = try DeepSeekRecognizer.request(jpeg: jpeg, key: "dummy-key")
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        let messages = body["messages"] as! [[String: Any]]
        let parts = messages[1]["content"] as! [[String: Any]]
        let image = parts[1]["image_url"] as! [String: String]
        try require(request.url == DeepSeekRecognizer.endpoint && request.httpMethod == "POST", "Official endpoint")
        try require(body["model"] as? String == "deepseek-v4-flash" && (body["response_format"] as? [String: String])?["type"] == "json_object", "Model and structured output")
        try require(image["url"] == "data:image/jpeg;base64," + jpeg.base64EncodedString(), "Inline image request")

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockDeepSeek.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        MockDeepSeek.data = try JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": redBottom], "finish_reason": "stop"]]])
        let result = try await DeepSeekRecognizer(session: session).recognize(jpeg: jpeg, key: "dummy-key")
        try require(result.chessPieces.count == 3 && result.name == "单车残局", "HTTP response imports structured board")
        MockDeepSeek.status = 401
        do {
            _ = try await DeepSeekRecognizer(session: session).recognize(jpeg: jpeg, key: "dummy-key")
            throw NSError(domain: "ImageImportCheck", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid API key was accepted"])
        } catch let error as ImageImportError {
            try require(error.message.contains("密钥无效"), "Actionable invalid-key message")
        }
    }
}

private final class MockDeepSeek: URLProtocol {
    static var status = 200
    static var data = Data()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
#endif
