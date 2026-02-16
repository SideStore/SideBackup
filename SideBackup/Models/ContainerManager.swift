//
//  ContainerManager.swift
//  SideBackup
//
//  Created by ny on 2/9/26.
//

actor ContainerManager {
    let root: URL
    private(set) var allFiles: Set<URL>
    
    var tmpFiles: Set<URL> { allFiles.filter { $0.path.hasPrefix("\(root.path)/tmp/") } }
    var libFiles: Set<URL> { allFiles.filter { $0.path.hasPrefix("\(root.path)/Library/") } }
    var docFiles: Set<URL> { allFiles.filter { $0.path.hasPrefix("\(root.path)/Documents/") } }
    
    
    init(_ filter: Set<String>? = nil) {
        let root = URL.documentsDirectory.deletingLastPathComponent()
        self.root = root
        self.allFiles = ContainerManager.getAllFiles(root, filter: filter)
    }
    
    @discardableResult
    func getAllFiles(filter: Set<String>? = nil) -> Set<URL> {
        allFiles = ContainerManager.getAllFiles(root, filter: filter)
        return allFiles
    }
    
    static func getAllFiles(_ root: URL, filter: Set<String>? = nil) -> Set<URL> {
        let fm: FileManager = .default
        var allFiles: Set<URL> = []
        if let files = fm.enumerator(atPath: root.path) {
            for case let f as String in files {
                let file = URL(file: f, relative: root)
                if let filter {
                    
                    if filter.allSatisfy({ !f.contains($0) }) && fm.isArchivableFile(atPath: file.path) {
                        allFiles.insert(file)
                    }
                } else {
                    if fm.isArchivableFile(atPath: file.path) {
                        allFiles.insert(file)
                    }
                }
            }
        }
        return allFiles
    }
    
    func printAll() {
        print(root.path)
        print("Total files: \(getAllFiles().count)")
        print("Library:")
        libFiles.forEach { print($0.relativeString) }
        print("tmp:")
        tmpFiles.forEach { print($0.relativeString) }
        print("Documents:")
        docFiles.forEach { print($0.relativeString) }
    }
    
    func removeAll() {
        // rm -r Library/\* Documents tmp
        var filt: Set<URL> = [
            URL(file: "Documents", isDir: true, relative: root),
            URL(file: "tmp", isDir: true, relative: root)
        ]
        try? FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("Library", isDirectory: true), includingPropertiesForKeys: nil)
            .forEach { filt.insert($0) }
        filt.forEach { try? $0.delete() }
    }
    
    func createArchive(at: URL, from: Set<URL>) async throws {
        try autoreleasepool {
            try? at.delete()
            try "".write(to: at, atomically: true, encoding: .utf8)
            let handle = try FileHandle(forWritingTo: at)
            var writer = TarWriter(fileHandle: handle)
            try from.forEach {
                do {
                    try writer.append($0)
                } catch {
                    print(error.localizedDescription)
                    throw error
                }
            }
            try writer.finalize()
            try handle.close()
        }
    }
    
    func backup() throws -> URL {
        let filt: Set<String> = [
            "tmp/side",
            "tmp/side.tar",
            "side/tmp.tar",
            "side/lib.tar",
            "side/doc.tar",
        ]
        getAllFiles(filter: filt)
        let tmp = URL(file: "tmp", isDir: true, relative: root)
        let side = URL(file: "side", isDir: true, relative: tmp)
        let sideback = URL(file: "side.tar", relative: tmp)
        let tmpback = URL(file: "tmp.tar", relative: side)
        let docback = URL(file: "doc.tar", relative: side)
        let libback = URL(file: "lib.tar", relative: side)

        let fm: FileManager = .default
        try? fm.createDirectory(at: side, withIntermediateDirectories: true)
        Task {
            try await createArchive(at: tmpback, from: tmpFiles)
            try await createArchive(at: docback, from: docFiles)
            try await createArchive(at: libback, from: libFiles)
            try await createArchive(at: sideback, from: [tmpback, docback, libback])
            try fm.removeItem(at: side)
        }
        return sideback
    }
    
    func extractArchive(from tarFile: URL, to: URL, overwrite: Bool = true) async throws {
        guard let handle = try? FileHandle(forReadingFrom: tarFile) else {
            throw NSError(domain: "FileError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Cannot open tar at \(tarFile.path)"])
        }
        defer {
            try? handle.close()
        }
        var reader = TarReader(fileHandle: handle)
        var isFinished = false
        while !isFinished {
            isFinished = try reader.process { (entry: TarEntry?) -> Bool in
                guard let entry else { return true }
                try entry.write(to: to, overwrite: overwrite)
                return false
            }
        }
    }
    
    func restore(from tar: URL) async throws {
        guard tar.startAccessingSecurityScopedResource() else {
            throw NSError(domain: "FileError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Cannot open tar at \(tar.path)"])
        }
        defer { tar.stopAccessingSecurityScopedResource() }
        let fm: FileManager = .default
        let tmp = URL(file: "tmp", isDir: true, relative: root)
        let side = URL(file: "side", isDir: true, relative: tmp)
        let sideback = URL(file: "side.tar", relative: tmp)
        let tmpback = URL(file: "tmp.tar", relative: side)
        let docback = URL(file: "doc.tar", relative: side)
        let libback = URL(file: "lib.tar", relative: side)
        try? fm.createDirectory(at: side, withIntermediateDirectories: true)
        try? fm.removeItem(at: sideback)
        try fm.copyItem(at: tar, to: sideback)
        try await extractArchive(from: sideback, to: side)
        try await extractArchive(from: tmpback, to: root)
        try await extractArchive(from: docback, to: root)
        try await extractArchive(from: libback, to: root)
        try? fm.removeItem(at: side)
        try? fm.removeItem(at: sideback)
    }
}
