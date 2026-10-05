import Foundation
import Combine

@MainActor
final class StudyStore: ObservableObject {
    @Published var studies: [Study] = []
    @Published var errorMessage: String?
    let directory: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(directory: URL? = nil, seedExamples: Bool = true) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.chiyizi.xiangqi/Studies", isDirectory: true)
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
            let files = try FileManager.default.contentsOfDirectory(at: self.directory, includingPropertiesForKeys: nil)
            for file in files where file.pathExtension == "json" {
                do { studies.append(try decoder.decode(Study.self, from: Data(contentsOf: file))) }
                catch { errorMessage = "有一个残局无法读取：\(file.lastPathComponent)" }
            }
            let marker = self.directory.appendingPathComponent(".initialized")
            if seedExamples && !FileManager.default.fileExists(atPath: marker.path) {
                for example in Study.examples { try save(example) }
                try Data().write(to: marker, options: .atomic)
            }
            sort()
        } catch { errorMessage = "残局库读取失败：\(error.localizedDescription)" }
    }
    func save(_ study: Study) throws {
        try encoder.encode(study).write(to: directory.appendingPathComponent(study.id.uuidString + ".json"), options: .atomic)
        if let index = studies.firstIndex(where: { $0.id == study.id }) { studies[index] = study }
        else { studies.append(study) }
        sort()
    }
    func delete(_ study: Study) {
        do {
            try FileManager.default.removeItem(at: directory.appendingPathComponent(study.id.uuidString + ".json"))
            studies.removeAll { $0.id == study.id }
        } catch { errorMessage = "删除失败：\(error.localizedDescription)" }
    }
    func copy(_ study: Study) {
        do { try save(study.duplicate()) }
        catch { errorMessage = "复制失败：\(error.localizedDescription)" }
    }
    private func sort() { studies.sort { $0.modifiedAt > $1.modifiedAt } }
}
