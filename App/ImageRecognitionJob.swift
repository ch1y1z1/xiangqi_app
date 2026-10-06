import Foundation
import Combine
#if os(iOS)
import UIKit
#endif

/// One user-initiated recognition, independent of the sheet that started it.
@MainActor
final class ImageRecognitionJob: NSObject, ObservableObject {
    enum Status: String, Codable { case running, ready, failed }
    struct Record: Codable {
        let id: UUID
        let service: String
        let summary: String
        let api: RecognitionAPI
        var status: Status = .running
        var httpStatus: Int?
        var result: RecognizedSetup?
        var message: String?
    }

    static let shared = ImageRecognitionJob()
    static let sessionIdentifier = "com.chiyizi.xiangqi.image-recognition"
    @Published private(set) var record: Record?
    var isRunning: Bool { record?.status == .running }
    var imageData: Data? { try? Data(contentsOf: file("image.jpg")) }

    private let directory: URL
    private var session: URLSession!
    private var upload: URLSessionTask?
    private var backgroundCompletion: (() -> Void)?
    private var recoveringCompletion = false

    init(directory: URL? = nil, configuration: URLSessionConfiguration? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.chiyizi.xiangqi/ImageRecognition", isDirectory: true)
        super.init()
        if let data = try? Data(contentsOf: file("job.json")) {
            record = try? JSONDecoder().decode(Record.self, from: data)
        }
        session = URLSession(configuration: configuration ?? Self.configuration(), delegate: self, delegateQueue: .main)
        if let restored = record, restored.status == .running {
            recoveringCompletion = true
            session.getAllTasks { tasks in
                DispatchQueue.main.async {
                    guard self.record?.id == restored.id, self.isRunning else { return }
                    if let task = tasks.first(where: { $0.taskDescription == restored.id.uuidString }) {
                        self.upload = task
                        if task.state == .suspended { task.resume() }
                    } else {
                        // A completed transfer may still have queued delegate events.
                        self.fail("上次识别已中断，请重新识别。强制关闭 App、网络断开或服务超时都可能导致中断。", clean: false)
                    }
                }
            }
        }
    }

    private static func configuration() -> URLSessionConfiguration {
        #if os(iOS)
        let configuration = URLSessionConfiguration.background(withIdentifier: sessionIdentifier)
        configuration.isDiscretionary = false
        configuration.sessionSendsLaunchEvents = true
        #else
        let configuration = URLSessionConfiguration.ephemeral
        #endif
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 360
        configuration.timeoutIntervalForResource = 360
        return configuration
    }

    @discardableResult
    func start(jpeg: Data, key: String, settings: RecognitionSettings) throws -> UUID {
        guard !isRunning else { throw ImageImportError(message: "已有图片正在识别，请等待完成或先取消。") }
        var request = try ImageRecognizer.request(jpeg: jpeg, key: key, settings: settings)
        guard let body = request.httpBody else { throw ImageImportError(message: "无法准备识别请求。") }
        discard()
        let next = Record(id: UUID(), service: settings.serviceName, summary: settings.description,
                          api: settings.provider == .deepSeek ? .chatCompletions : settings.api)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var folder = directory
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try folder.setResourceValues(values)
            try write(body, to: file("request.json"))
            try write(jpeg, to: file("image.jpg"))
            try write(Data(), to: file("response.json"))
            try persist(next)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw ImageImportError(message: "无法保存识别任务：\(error.localizedDescription)")
        }
        // Background sessions support file uploads, not an in-memory HTTP body.
        // Authorization stays in the URLRequest and is never written to our files.
        request.httpBody = nil
        let task = session.uploadTask(with: request, fromFile: file("request.json"))
        task.taskDescription = next.id.uuidString
        record = next
        upload = task
        task.resume()
        return next.id
    }

    /// Also used after importing. Clearing the ID makes late callbacks harmless.
    func discard() {
        let id = record?.id.uuidString
        record = nil
        recoveringCompletion = false
        upload?.cancel()
        upload = nil
        if let id {
            session.getAllTasks { tasks in
                for task in tasks where task.taskDescription == id { task.cancel() }
            }
        }
        try? FileManager.default.removeItem(at: directory)
    }

    func handleBackgroundEvents(identifier: String, completion: @escaping () -> Void) {
        guard identifier == Self.sessionIdentifier else { completion(); return }
        backgroundCompletion = completion
    }

    private func file(_ name: String) -> URL { directory.appendingPathComponent(name) }
    private func write(_ data: Data, to url: URL) throws {
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: .atomic)
        #endif
    }
    private func persist(_ record: Record) throws { try write(JSONEncoder().encode(record), to: file("job.json")) }
    private func belongs(_ task: URLSessionTask) -> Bool {
        guard let record else { return false }
        return task.taskDescription == record.id.uuidString
    }
    private func cleanTransferFiles() {
        for name in ["request.json", "response.json"] { try? FileManager.default.removeItem(at: file(name)) }
    }
    private func fail(_ message: String, clean: Bool = true) {
        guard var current = record else { return }
        current.status = .failed
        current.result = nil
        current.message = message
        try? persist(current)
        record = current
        if clean { recoveringCompletion = false; cleanTransferFiles() }
    }
    private func receive(_ data: Data, task: URLSessionTask) {
        guard belongs(task), isRunning || recoveringCompletion else { return }
        do {
            let handle = try FileHandle(forWritingTo: file("response.json"))
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            fail("无法保存识别响应：\(error.localizedDescription)")
            task.cancel()
        }
    }
    private func finish(_ task: URLSessionTask, error: Error?) {
        guard belongs(task), isRunning || recoveringCompletion, var current = record else { return }
        upload = nil
        if let error {
            fail("识别请求未完成：\(error.localizedDescription) 请检查网络后重试。")
            return
        }
        do {
            guard let status = (task.response as? HTTPURLResponse)?.statusCode ?? current.httpStatus else {
                throw ImageImportError(message: "\(current.service)未返回有效响应。")
            }
            current.result = try ImageRecognizer.result(from: Data(contentsOf: file("response.json")),
                                                        statusCode: status, api: current.api, service: current.service)
            current.status = .ready
            current.message = nil
            try persist(current)
            record = current
            recoveringCompletion = false
            cleanTransferFiles()
        } catch { fail(error.localizedDescription) }
    }
}

extension ImageRecognitionJob: URLSessionDataDelegate {
    nonisolated func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                               didReceive response: URLResponse,
                               completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        DispatchQueue.main.async {
            if self.belongs(dataTask), var current = self.record {
                current.httpStatus = (response as? HTTPURLResponse)?.statusCode
                do { try self.persist(current); self.record = current }
                catch { self.fail("无法保存识别任务：\(error.localizedDescription)"); dataTask.cancel() }
            }
            completionHandler(.allow)
        }
    }
    nonisolated func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        DispatchQueue.main.async { self.receive(data, task: dataTask) }
    }
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        DispatchQueue.main.async { self.finish(task, error: error) }
    }
    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async {
            let completion = self.backgroundCompletion
            self.backgroundCompletion = nil
            self.recoveringCompletion = false
            if self.record?.status == .failed { self.cleanTransferFiles() }
            completion?()
        }
    }
}

#if os(iOS)
final class RecognitionAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        ImageRecognitionJob.shared.handleBackgroundEvents(identifier: identifier, completion: completionHandler)
    }
}
#endif
