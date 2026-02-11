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
        let fm: FileManager = .default
        try autoreleasepool {
            try? at.delete()
            try "".write(to: at, atomically: true, encoding: .utf8)
            let handle = try FileHandle(forWritingTo: at)
            var writer = TarWriter(fileHandle: handle)
            try from.forEach {
                let attrs = try fm.attributesOfItem(atPath: $0.path)
                let isDirectory = (attrs[.type] as? FileAttributeType) == .typeDirectory
                var info = TarEntryInfo(name: $0.relativeString, type: isDirectory ? .directory : .regular)
                if let permissions = attrs[.posixPermissions] as? UInt32 {
                    info.permissions = Permissions(rawValue: permissions)
                }
                if let mod = attrs[.modificationDate] as? Date {
                    info.modificationTime = mod
                }
                let data = isDirectory ? Data() : try Data(contentsOf: $0, options: .alwaysMapped)
                do {
                    try writer.append(TarEntry(info: info, data: data))
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
//            "SplashBoard",
//            "Saved Application State",
//            "com.apple.metalfe",
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
        let fm: FileManager = .default
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
                let entryPath = URL(file: entry.info.name, isDir: entry.info.type == .directory, relative: to)
                switch entry.info.type {
                case .directory:
                    try? fm.createDirectory(at: entryPath.absoluteURL, withIntermediateDirectories: true)
                    if let attrs = [FileAttributeKey: Any](entry.info) {
                        try fm.setAttributes(attrs, ofItemAtPath: entryPath.path)
                    }
                    
                case .regular:
                    let parent = entryPath.absoluteURL.deletingLastPathComponent()
                    do {
                        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
                    } catch {
                        print(error.localizedDescription)
                    }
                    
                    if overwrite && fm.fileExists(atPath: entryPath.path) {
                        try fm.removeItem(at: entryPath.absoluteURL)
                    }
                    
                    if let data = entry.data {
                        do {
                            try data.write(to: entryPath.absoluteURL, options: .atomic)
                        } catch {
                            print(error.localizedDescription)
                            return false
                        }
                    }
                    
                    if let attrs = [FileAttributeKey: Any](entry.info) {
                        try fm.setAttributes(attrs, ofItemAtPath: entryPath.absoluteURL.path)
                    }
                    
                case .symbolicLink:
                    if overwrite && fm.isDeletableFile(atPath: entryPath.absoluteURL.path) {
                        try fm.removeItem(at: entryPath.absoluteURL)
                    }
                    try fm.createSymbolicLink(atPath: entryPath.absoluteURL.path, withDestinationPath: entry.info.linkName)
                    
                default:
                    print("Skipping entry of type: \(entry.info.type) for \(entry.info.name)")
                }
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
    
    
    
    nonisolated func getKeychain() {
        let query: [String: Any] = [kSecClass as String: kSecClassInternetPassword, // change the kSecClass for your needs
                                    kSecMatchLimit as String: kSecMatchLimitAll,
                                    kSecReturnAttributes as String: true,
                                    kSecReturnRef as String: true]
        var items_ref: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &items_ref)
        guard status != errSecItemNotFound else { return }
        guard status == errSecSuccess else { return }
        let items = items_ref as! Array<Dictionary<String, Any>>

        // Now loop over the items and do something with each item
        for item in items {
            // Sample code: prints the account name
            print(item[kSecAttrAccount as String] as? String ?? "Couldn't convert to String")
        }
    }
}

