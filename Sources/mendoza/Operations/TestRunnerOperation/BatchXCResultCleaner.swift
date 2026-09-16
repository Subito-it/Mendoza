import Foundation

/// Batch cleanup follows every test's attachment references and fails closed on unreadable metadata.
/// Reading the object JSON directly also supports empty arrays omitted by newer xcresult versions.
struct BatchXCResultCleaner {
    let path: String

    static func references(in value: Any) -> (objects: Set<String>, attachments: Set<String>) {
        var objects = Set<String>()
        var attachments = Set<String>()
        func visit(_ value: Any) {
            if let dictionary = value as? [String: Any] {
                for (key, child) in dictionary {
                    if let reference = child as? [String: Any], let id = reference["id"] as? [String: Any], let identifier = id["_value"] as? String {
                        if ["testsRef", "summaryRef"].contains(key) {
                            objects.insert(identifier)
                        }
                        if key == "payloadRef" {
                            attachments.insert(identifier)
                        }
                    }
                    visit(child)
                }
            } else if let values = value as? [Any] {
                values.forEach(visit)
            }
        }
        visit(value)
        return (objects, attachments)
    }

    func clean(minimumSizeKB: Int) throws {
        guard minimumSizeKB > 1, minimumSizeKB <= Int.max / 1_024 else { throw Error("Invalid xcresult cleanup threshold") }
        let executer = LocalExecuter()
        let quote = BatchTestExecutor.quote
        func object(_ identifier: String? = nil) throws -> Any {
            let selection = identifier.map { " --id " + quote($0) } ?? ""
            let output = try executer.execute("xcrun xcresulttool get object --legacy --format json --path " + quote(path) + selection)
            return try JSONSerialization.jsonObject(with: Data(output.utf8))
        }
        let root = try Self.references(in: object())
        guard !root.objects.isEmpty else { throw Error("No test references in batch xcresult; preserving all blobs") }
        var pending = root.objects
        var visited = Set<String>()
        var protected = root.attachments
        while let identifier = pending.first {
            pending.remove(identifier)
            guard visited.insert(identifier).inserted else { continue }
            let references = try Self.references(in: object(identifier))
            pending.formUnion(references.objects.subtracting(visited))
            protected.formUnion(references.attachments)
        }
        protected.formUnion(visited)
        // No mutation happens until every referenced test summary has been read successfully.
        let dataURL = URL(fileURLWithPath: path).appendingPathComponent("Data")
        guard let enumerator = FileManager.default.enumerator(at: dataURL, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]) else {
            throw Error("Cannot enumerate xcresult data")
        }
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true, let size = values.fileSize, size > minimumSizeKB * 1_024,
                  !protected.contains(where: { url.lastPathComponent.contains($0) }) else { continue }
            try Data("content replaced by mendoza because original file was larger than \(minimumSizeKB)KB".utf8).write(to: url, options: .atomic)
        }
    }
}
