//
//  Helpers.swift
//  SideBackup
//
//  Created by ny on 2/9/26.
//


@_exported import SwiftUI
@_exported import Security
@_exported import UniformTypeIdentifiers

@_exported import SWCompression

struct DirectoryIterator: Sequence {
    let enumerator: FileManager.DirectoryEnumerator
    
    func makeIterator() -> AnyIterator<Any> {
        AnyIterator {
            enumerator.nextObject()
        }
    }
}

extension URL {
    @available(iOS, introduced: 14.0, deprecated: 16.0, message: "use init(file:isDir:relative:) instead")
    nonisolated init(file: String, isDir: Bool = false, relative to: URL? = nil) {
        if #available(iOS 16.0, *) {
            self = URL(file: file, isDir: isDir ? .isDirectory : .checkFileSystem, relative: to)
        } else {
            self = URL(fileURLWithPath: file, isDirectory: isDir, relativeTo: to)
        }
    }

    @available(iOS 16.0, *)
    nonisolated init(file: String, isDir: URL.DirectoryHint = .checkFileSystem, relative to: URL? = nil) {
        self = URL(filePath: file, directoryHint: isDir, relativeTo: to)
    }
    
    @available(iOS, introduced: 14.0, deprecated: 16.0)
    nonisolated static var documentsDirectory: URL { try! FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false) }
    
    @available(iOS, introduced: 14.0, deprecated: 16.0)
    nonisolated static var temporaryDirectory: URL { FileManager.default.temporaryDirectory }
    
    nonisolated func delete() throws { try FileManager.default.removeItem(at: self) }
}

extension FileManager {
    // We can only archive files we can delete and overwrite
    nonisolated func isArchivableFile(atPath at: String) -> Bool {
        isReadableFile(atPath: at) && isWritableFile(atPath: at) && isDeletableFile(atPath: at)
    }
}

extension Optional {
    mutating func clearIf(_ block: @escaping (Wrapped) throws -> Void) rethrows {
        if let s = self {
            try block(s)
            self = nil
        }
    }
}

extension [FileAttributeKey: Any] {
    nonisolated init?(_ info: TarEntryInfo) {
        var attrs: [FileAttributeKey: Any] = [:]
        if let mod = info.modificationTime {
            attrs[.modificationDate] = mod
        }
        if let perms = info.permissions {
            attrs[.posixPermissions] = perms.rawValue
        }
        guard !attrs.isEmpty else { return nil }
        self = attrs
    }
}
