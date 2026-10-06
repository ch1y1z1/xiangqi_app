#if DEBUG
import Foundation
import ImageIO
import SwiftUI

/// Focused, offline checks. Uses a dummy key and intercepts every HTTP request.
enum ImageImportCheck {
    static func run() -> Never {
        Task.detached {
            do {
                try await check()
                print("IMAGE_IMPORT_CHECK_PASSED: coordinates, photo orientation, DeepSeek/custom formats, thinking, incomplete output, file upload, result recovery, cancellation and interrupted job")
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
        // Check every intersection against rendering, hit-testing and independent corner anchors.
        for bottom in Side.allCases {
            let layout = BoardLayout(size: CGSize(width: 390, height: 430), bottom: bottom)
            for row in 0...9 {
                for column in 0...8 {
                    let input = "{\"bottom_side\":\"\(bottom.rawValue)\",\"pieces\":[{\"side\":\"red\",\"kind\":\"rook\",\"column\":\(column),\"row\":\(row)}]}"
                    let square = try RecognizedSetup.parse(input).chessPieces[0].square
                    let point = CGPoint(x: layout.origin.x + CGFloat(column) * layout.unit, y: layout.origin.y + CGFloat(row) * layout.unit)
                    try require(layout.point(square).x == point.x && layout.point(square).y == point.y && layout.square(point) == square,
                                "Image/render/hit-test coordinate mismatch")
                    if column == 0 && row == 0 { try require(square.uci == (bottom == .red ? "a9" : "i0"), "Top-left anchor") }
                    if column == 8 && row == 9 { try require(square.uci == (bottom == .red ? "i0" : "a9"), "Bottom-right anchor") }
                }
            }
        }
        let initial = ChessPosition.pieces(fen: ChessPosition.initialFEN)
        try require(initial.filter { $0.side == .red && $0.kind == .pawn }.allSatisfy { $0.square.rank == 3 }
                    && initial.filter { $0.side == .black && $0.kind == .pawn }.allSatisfy { $0.square.rank == 6 }, "FEN rank anchors")
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
        try require((body["thinking"] as? [String: String])?["type"] == "enabled" && body["reasoning_effort"] as? String == "high", "Default high thinking")
        for level in RecognitionThinking.allCases {
            let request = try DeepSeekRecognizer.request(jpeg: jpeg, key: "dummy-key", thinking: level)
            let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            try require((body["thinking"] as? [String: String])?["type"] == (level == .off ? "disabled" : "enabled"), "Thinking toggle")
            try require(body["reasoning_effort"] as? String == (level == .off ? nil : level.rawValue), "Official effort setting")
            try require(body["max_tokens"] as? Int == level.maxTokens && request.timeoutInterval == level.timeout, "Thinking output/time budget")
            try require(level == .off ? body["temperature"] != nil : body["temperature"] == nil, "Temperature only applies without thinking")
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockDeepSeek.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        MockDeepSeek.data = try JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": redBottom], "finish_reason": "stop"]]])
        let result = try await DeepSeekRecognizer(session: session).recognize(jpeg: jpeg, key: "dummy-key")
        try require(result.chessPieces.count == 3 && result.name == "单车残局", "HTTP response imports structured board")
        MockDeepSeek.data = try JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": ""], "finish_reason": "length"]]])
        do {
            _ = try await DeepSeekRecognizer(session: session).recognize(jpeg: jpeg, key: "dummy-key")
            throw NSError(domain: "ImageImportCheck", code: 3, userInfo: [NSLocalizedDescriptionKey: "Truncated reasoning was accepted"])
        } catch let error as ImageImportError {
            try require(error.message.contains("不完整"), "Thinking budget exhausted before final JSON")
        }
        MockDeepSeek.status = 401
        do {
            _ = try await DeepSeekRecognizer(session: session).recognize(jpeg: jpeg, key: "dummy-key")
            throw NSError(domain: "ImageImportCheck", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid API key was accepted"])
        } catch let error as ImageImportError {
            try require(error.message.contains("密钥无效"), "Actionable invalid-key message")
        }

        var custom = RecognitionSettings()
        custom.provider = .custom
        custom.model = "vision-model"
        custom.address = "https://example.com/v1/"
        try require(RecognitionProvider.deepSeek.keychainSuffix != RecognitionProvider.custom.keychainSuffix, "Provider keys stay separate")
        for api in RecognitionAPI.allCases {
            custom.api = api
            custom.address = "https://example.com/v1/"
            try require(try custom.endpoint().absoluteString == "https://example.com/v1" + api.path, "Base URL resolution")
            custom.address = "https://example.com/v1/chat/completions?version=1"
            try require(try custom.endpoint().absoluteString == "https://example.com/v1" + api.path + "?version=1", "Full endpoint and format switching")
            custom.address = "http://127.0.0.1:8000/v1"
            let anonymous = try ImageRecognizer.request(jpeg: jpeg, key: "", settings: custom)
            try require(anonymous.value(forHTTPHeaderField: "Authorization") == nil && anonymous.url?.scheme == "http", "Keyless local HTTP service")
            let request = try ImageRecognizer.request(jpeg: jpeg, key: "custom-dummy", settings: custom)
            let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            try require(request.value(forHTTPHeaderField: "Authorization") == "Bearer custom-dummy", "Custom bearer authentication")
            try require(body["model"] as? String == "vision-model" && body["thinking"] == nil && body["temperature"] == nil, "Custom model without vendor extensions")
            try require(body["reasoning_effort"] == nil && body["reasoning"] == nil && body["max_completion_tokens"] == nil && body["max_output_tokens"] == nil, "Service-default reasoning")
            if api == .chatCompletions {
                let messages = body["messages"] as! [[String: Any]]
                let parts = messages[1]["content"] as! [[String: Any]]
                try require((parts[1]["image_url"] as? [String: String])?["url"] == image["url"], "Completions image wire format")
                try require((body["response_format"] as? [String: String])?["type"] == "json_object" && body["input"] == nil, "Completions JSON wire format")
            } else {
                let input = body["input"] as! [[String: Any]]
                let parts = input[0]["content"] as! [[String: Any]]
                let text = body["text"] as! [String: [String: String]]
                try require(parts[1]["type"] as? String == "input_image" && parts[1]["image_url"] as? String == image["url"], "Responses image wire format")
                try require(text["format"]?["type"] == "json_object" && body["store"] as? Bool == false && body["messages"] == nil, "Responses JSON format and stateless request")
            }
            custom.customThinking = .max
            let thinkingRequest = try ImageRecognizer.request(jpeg: jpeg, key: "custom-dummy", settings: custom)
            let thinkingBody = try JSONSerialization.jsonObject(with: thinkingRequest.httpBody!) as! [String: Any]
            let effort = api == .chatCompletions ? thinkingBody["reasoning_effort"] as? String : (thinkingBody["reasoning"] as? [String: String])?["effort"]
            try require(effort == "xhigh" && thinkingRequest.timeoutInterval == 360, "Standard custom reasoning effort")
            custom.customThinking = nil
            MockDeepSeek.status = 200
            let output: [[String: Any]] = [
                ["type": "reasoning", "summary": [["type": "summary_text", "text": "Ignore reasoning text"]]],
                ["type": "message", "role": "assistant", "status": "completed", "content": [["type": "output_text", "text": blackBottom]]]
            ]
            let payload: [String: Any]
            if api == .chatCompletions {
                payload = ["choices": [["message": ["content": blackBottom], "finish_reason": "stop"]]]
            } else { payload = ["status": "completed", "output": output] }
            MockDeepSeek.data = try JSONSerialization.data(withJSONObject: payload)
            let imported = try await ImageRecognizer(session: session).recognize(jpeg: jpeg, key: "", settings: custom)
            try require(ChessPosition.fen(pieces: imported.chessPieces, side: .red) == fen, "Custom HTTP import and black-bottom coordinates")
            if api == .responses {
                MockDeepSeek.data = try JSONSerialization.data(withJSONObject: ["status": "incomplete", "output": output])
                do {
                    _ = try await ImageRecognizer(session: session).recognize(jpeg: jpeg, key: "", settings: custom)
                    throw NSError(domain: "ImageImportCheck", code: 4, userInfo: [NSLocalizedDescriptionKey: "Incomplete Responses output was accepted"])
                } catch let error as ImageImportError { try require(error.message.contains("不完整"), "Incomplete Responses output rejected") }
            }
        }
        for invalid in ["", "ftp://example.com", "https:///", "https://user:password@example.com/v1"] {
            custom.address = invalid
            do {
                _ = try custom.endpoint()
                throw NSError(domain: "ImageImportCheck", code: 5, userInfo: [NSLocalizedDescriptionKey: "Invalid custom endpoint was accepted"])
            } catch is ImageImportError { /* Expected. */ }
        }
        custom.address = "https://example.com/v1"
        custom.customThinking = .off
        let restored = try JSONDecoder().decode(RecognitionSettings.self, from: JSONEncoder().encode(custom))
        try require(restored.provider == .custom && restored.api == .responses && restored.customThinking == .off, "Custom settings persistence")
        try await checkJob(jpeg: jpeg, content: blackBottom)
    }

    @MainActor private static func checkJob(jpeg: Data, content: String) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("recognition-check-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockDeepSeek.self]
        let job = ImageRecognitionJob(directory: directory, configuration: configuration)
        var settings = RecognitionSettings()
        settings.provider = .custom
        settings.address = "https://example.com/v1"
        settings.model = "vision-model"
        func waitForFinish(_ job: ImageRecognitionJob) async throws {
            let deadline = Date().addingTimeInterval(4)
            while job.isRunning, Date() < deadline { try await Task.sleep(nanoseconds: 20_000_000) }
            try require(!job.isRunning, "Recognition job did not finish")
        }
        for api in RecognitionAPI.allCases {
            settings.api = api
            MockDeepSeek.status = 200
            let payload: [String: Any] = api == .chatCompletions
                ? ["choices": [["message": ["content": content], "finish_reason": "stop"]]]
                : ["status": "completed", "output": [["type": "message", "role": "assistant", "status": "completed",
                    "content": [["type": "output_text", "text": content]]]]]
            MockDeepSeek.data = try JSONSerialization.data(withJSONObject: payload)
            let id = try job.start(jpeg: jpeg, key: "dummy-job-secret", settings: settings)
            let storedRequest = try Data(contentsOf: directory.appendingPathComponent("request.json"))
            try require(!String(decoding: storedRequest, as: UTF8.self).contains("dummy-job-secret"), "Credential written to request file")
            try await waitForFinish(job)
            try require(job.record?.id == id && job.record?.status == .ready, "File upload did not produce a result")
            let expected = try RecognizedSetup.parse(content)
            try require(job.record?.result?.chessPieces.map(\.square) == expected.chessPieces.map(\.square), "Uploaded response changed coordinates")
            let recovered = ImageRecognitionJob(directory: directory, configuration: configuration)
            try require(recovered.record?.id == id && recovered.record?.result?.pieces.count == expected.pieces.count,
                        "Completed result was not restored")
            for name in ["request.json", "response.json"] {
                try require(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path), "Transfer file retained after completion")
            }
            job.discard()
        }
        // Cancel before delegate events run; late callbacks must not recreate files or import a result.
        _ = try job.start(jpeg: jpeg, key: "", settings: settings)
        job.discard()
        try await Task.sleep(nanoseconds: 100_000_000)
        try require(job.record == nil && !FileManager.default.fileExists(atPath: directory.path), "Cancelled result reappeared")

        MockDeepSeek.status = 401
        _ = try job.start(jpeg: jpeg, key: "dummy-job-secret", settings: settings)
        try await waitForFinish(job)
        try require(job.record?.status == .failed && job.record?.message?.contains("密钥") == true, "HTTP error was not preserved")

        // Restore a pending record without a corresponding system task, as after a force quit.
        _ = try job.start(jpeg: jpeg, key: "", settings: settings)
        let pending = try Data(contentsOf: directory.appendingPathComponent("job.json"))
        job.discard()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try pending.write(to: directory.appendingPathComponent("job.json"))
        try jpeg.write(to: directory.appendingPathComponent("image.jpg"))
        let interrupted = ImageRecognitionJob(directory: directory, configuration: configuration)
        try await waitForFinish(interrupted)
        try require(interrupted.record?.status == .failed && interrupted.imageData == jpeg,
                    "Interrupted job stayed busy or lost its retry image")
        interrupted.discard()
    }

    #if os(macOS)
    private static func auditArgument(_ flag: String) -> String? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
    private static var auditFolder: URL {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        return URL(fileURLWithPath: auditArgument("--audit-output") ?? "build/recognition-audit", relativeTo: root).standardizedFileURL
    }

    /// Prepares local image/request fixtures only. No keychain access or network requests.
    @MainActor static func prepareAudit() -> Never {
        do {
            let folder = auditFolder
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var custom: RecognitionSettings?
            if auditArgument("--audit-endpoint") != nil || auditArgument("--audit-model") != nil {
                guard let endpoint = auditArgument("--audit-endpoint"), let model = auditArgument("--audit-model"),
                      let api = RecognitionAPI(rawValue: auditArgument("--audit-api") ?? "responses") else {
                    throw ImageImportError(message: "自定义审计需同时提供端点和模型，接口类型为 responses 或 chatCompletions。")
                }
                var settings = RecognitionSettings()
                settings.provider = .custom
                settings.address = endpoint
                settings.model = model
                settings.api = api
                if let level = auditArgument("--audit-thinking"), level != "default" {
                    guard let thinking = RecognitionThinking(rawValue: level) else {
                        throw ImageImportError(message: "审计思考强度应为 default、off、low、high 或 max。")
                    }
                    settings.customThinking = thinking
                }
                try settings.validate(key: "")
                custom = settings
            }
            if let input = auditArgument("--audit-input") {
                let fixtures = try JSONDecoder().decode([[String: String]].self,
                    from: Data(contentsOf: URL(fileURLWithPath: input)))
                var manifest: [[String: String]] = []
                for fixture in fixtures {
                    guard let name = fixture["test"], let path = fixture["image"],
                          let fen = fixture["expected_fen"], let bottom = fixture["expected_bottom_side"] else {
                        throw ImageImportError(message: "图片审计样例需包含名称、图片路径、预期 FEN 和朝向。")
                    }
                    let image = try RecognitionImage(data: Data(contentsOf: URL(fileURLWithPath: path)))
                    let levels: [RecognitionThinking?] = custom != nil ? [custom!.customThinking] : RecognitionThinking.allCases.map { Optional($0) }
                    for level in levels {
                        let thinking = level?.rawValue ?? "default"
                        let test = name + "-" + thinking
                        let request: URLRequest
                        if let custom { request = try ImageRecognizer.request(jpeg: image.jpeg, key: "", settings: custom) }
                        else { request = try DeepSeekRecognizer.request(jpeg: image.jpeg, key: "audit-dummy", thinking: level!) }
                        try request.httpBody!.write(to: folder.appendingPathComponent(test + "-request.json"))
                        manifest.append(["test": test, "thinking": thinking, "expected_fen": fen,
                                         "expected_bottom_side": bottom, "timeout": String(request.timeoutInterval),
                                         "endpoint": request.url!.absoluteString, "api": custom?.api.rawValue ?? "chatCompletions",
                                         "model": custom?.model ?? DeepSeekRecognizer.model])
                    }
                }
                try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
                    .write(to: folder.appendingPathComponent("manifest.json"))
                print("Prepared \(manifest.count) supplied-image requests; no credentials stored.")
                exit(0)
            }
            var black = Study.examples[1]
            black.bottomSide = .black
            var fixtures: [(String, Study)] = [("editor-red-5", Study.examples[1]), ("editor-black-5", black),
                                               ("editor-red-32", Study(name: "初始盘", pieces: ChessPosition.pieces(fen: ChessPosition.initialFEN)))]
            if custom != nil {
                var initial = fixtures[2].1
                initial.bottomSide = .black
                fixtures.append(("editor-black-32", initial))
            }
            var manifest: [[String: String]] = []
            for (name, study) in fixtures {
                try DevelopmentCheck.renderScreen(EditorView(study: study, onSave: { _, _ in }), name: name, folder: folder)
                let image = try RecognitionImage(data: Data(contentsOf: folder.appendingPathComponent(name + ".png")))
                if let custom {
                    let thinking = custom.customThinking?.rawValue ?? "default"
                    let test = name + "-" + thinking
                    let request = try ImageRecognizer.request(jpeg: image.jpeg, key: "", settings: custom)
                    try request.httpBody!.write(to: folder.appendingPathComponent(test + "-request.json"))
                    manifest.append(["test": test, "thinking": thinking, "expected_fen": study.initialFEN,
                                     "expected_bottom_side": study.bottomSide.rawValue,
                                     "timeout": String(request.timeoutInterval), "endpoint": request.url!.absoluteString,
                                     "api": custom.api.rawValue, "model": custom.model])
                    continue
                }
                let levels: [RecognitionThinking] = name == "editor-red-32" ? [.high] : name == "editor-red-5" ? [.off, .high, .max] : [.off, .high]
                for level in levels {
                    let test = name + "-" + level.rawValue
                    let request = try DeepSeekRecognizer.request(jpeg: image.jpeg, key: "audit-dummy", thinking: level)
                    try request.httpBody!.write(to: folder.appendingPathComponent(test + "-request.json"))
                    manifest.append(["test": test, "thinking": level.rawValue, "expected_fen": study.initialFEN,
                                     "timeout": String(level.timeout)])
                }
            }
            try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
                .write(to: folder.appendingPathComponent("manifest.json"))
            print("Prepared \(manifest.count) real-API request fixtures; no credentials stored.")
            exit(0)
        } catch { fputs("AUDIT_PREPARE_FAILED: \(error.localizedDescription)\n", stderr); exit(1) }
    }

    static func auditResponses() -> Never {
        do {
            let folder = auditFolder
            let manifest = try JSONDecoder().decode([[String: String]].self, from: Data(contentsOf: folder.appendingPathComponent("manifest.json")))
            var report: [[String: Any]] = []
            func identities(_ pieces: [ChessPiece]) -> Set<String> { Set(pieces.map { "\($0.side.rawValue):\($0.kind.rawValue):\($0.square.uci)" }) }
            for fixture in manifest {
                let name = fixture["test"]!
                let expected = identities(ChessPosition.pieces(fen: fixture["expected_fen"]!))
                var entry: [String: Any] = ["test": name, "expected": expected.count]
                do {
                    let content = try String(contentsOf: folder.appendingPathComponent(name + "-content.json"), encoding: .utf8)
                    let result: RecognizedSetup
                    do {
                        result = try RecognizedSetup.parse(content)
                        entry["import_valid"] = true
                    } catch {
                        // Preserve piece metrics when a response decodes but violates import limits.
                        entry["import_valid"] = false
                        entry["error"] = error.localizedDescription
                        result = try JSONDecoder().decode(RecognizedSetup.self, from: Data(content.utf8))
                    }
                    let actual = identities(result.chessPieces)
                    entry["recognized"] = actual.count
                    entry["correct"] = expected.intersection(actual).count
                    entry["missing"] = expected.subtracting(actual).sorted()
                    entry["extra"] = actual.subtracting(expected).sorted()
                    entry["bottom_side"] = result.bottomSide.rawValue
                    entry["exact_position"] = expected == actual && result.pieces.count == expected.count
                    entry["import_success"] = entry["import_valid"] as? Bool == true && expected == actual && result.pieces.count == expected.count
                    if let bottom = fixture["expected_bottom_side"] {
                        entry["orientation_correct"] = result.bottomSide.rawValue == bottom
                    }
                } catch { entry["error"] = error.localizedDescription }
                report.append(entry)
            }
            let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: folder.appendingPathComponent("swift-results.json"))
            print(String(decoding: data, as: UTF8.self))
            exit(0)
        } catch { fputs("AUDIT_RESPONSES_FAILED: \(error.localizedDescription)\n", stderr); exit(1) }
    }
    #endif
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
