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
    
    nonisolated static var sideGroupContainer: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: getAppGroups().first ?? "")
    }
    
    nonisolated static var groupContainers: [String: URL] {
        Dictionary(uniqueKeysWithValues: getAppGroups().map { ($0, FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0)!) })
    }
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

extension TarEntry {
    nonisolated init(_ url: URL) throws {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let isDirectory = (attrs[.type] as? FileAttributeType) == .typeDirectory
        var info = TarEntryInfo(name: url.relativeString, type: isDirectory ? .directory : .regular)
        if let permissions = attrs[.posixPermissions] as? UInt32 {
            info.permissions = Permissions(rawValue: permissions)
        }
        if let mod = attrs[.modificationDate] as? Date {
            info.modificationTime = mod
        }
        let data = isDirectory ? Data() : try Data(contentsOf: url, options: .alwaysMapped)
        self = .init(info: info, data: data)
    }
    
    nonisolated func write(to: URL, overwrite: Bool = true) throws {
        let fm: FileManager = .default
        let entryPath = URL(file: info.name, isDir: info.type == .directory, relative: to)
        switch info.type {
        case .directory:
            try? fm.createDirectory(at: entryPath.absoluteURL, withIntermediateDirectories: true)
            if let attrs = [FileAttributeKey: Any](info) {
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
            
            if let data {
                try data.write(to: entryPath.absoluteURL, options: .atomic)
            }
            
        case .symbolicLink:
            if overwrite && fm.isDeletableFile(atPath: entryPath.absoluteURL.path) {
                try fm.removeItem(at: entryPath.absoluteURL)
            }
            try fm.createSymbolicLink(atPath: entryPath.absoluteURL.path, withDestinationPath: info.linkName)
            
        default:
            print("Skipping entry of type: \(info.type) for \(info.name)")
        }
        if let attrs = [FileAttributeKey: Any](info) {
            try fm.setAttributes(attrs, ofItemAtPath: entryPath.absoluteURL.path)
        }

    }
}

extension TarWriter {
    mutating func append(_ url: URL) throws {
        try append(TarEntry(url))
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

typealias SecTaskRef = OpaquePointer

@_silgen_name("SecTaskCopyValueForEntitlement")
func SecTaskCopyValueForEntitlement(
    _ task: SecTaskRef,
    _ entitlement: NSString,
    _ error: NSErrorPointer
) -> CFTypeRef?

@_silgen_name("SecTaskCopyTeamIdentifier")
func SecTaskCopyTeamIdentifier(
    _ task: SecTaskRef,
    _ error: NSErrorPointer
) -> NSString?

@_silgen_name("SecTaskCreateFromSelf")
func SecTaskCreateFromSelf(
    _ allocator: CFAllocator?
) -> SecTaskRef?

@_silgen_name("CFRelease")
func CFRelease(_ cf: CFTypeRef)

@_silgen_name("SecTaskCopyValuesForEntitlements")
func SecTaskCopyValuesForEntitlements(
    _ task: SecTaskRef,
    _ entitlements: CFArray,
    _ error: UnsafeMutablePointer<Unmanaged<CFError>?>?
) -> CFDictionary?

func withSecTask(_ block: @escaping (SecTaskRef) -> Void) {
    guard let task = SecTaskCreateFromSelf(nil) else { return }
    block(task)
    CFRelease(unsafeBitCast(task, to: CFTypeRef.self))

}

func withSecEntitlements(for entitlements: [String], _ block: @escaping (CFDictionary) -> Void) {
    withSecTask { task in
        if let entitlements = SecTaskCopyValuesForEntitlements(task, entitlements as CFArray, nil) {
            block(entitlements)
        }
    }
}

func withSecEntitlement(for entitlement: String, _ block: @escaping (CFTypeRef) -> Void) {
    withSecTask { task in
        if let entitlement = SecTaskCopyValueForEntitlement(task, entitlement as NSString, nil) {
            block(entitlement)
        }
    }
}

func checkAppEntitlements(_ ents: [String]) -> [String: Any] {
    var ret: [String: Any] = [:]
    withSecEntitlements(for: ents) { entitlements in
        ret = (entitlements as NSDictionary) as? [String: Any] ?? [:]
    }
    return ret
}

func checkAppEntitlement(_ ent: String) -> Bool {
    var ret: Bool = false
    withSecEntitlement(for: ent) { entitlement in
        if let num = entitlement as? NSNumber {
            ret = num.boolValue
        } else if let bool = entitlement as? Bool {
            ret = bool
        }
    }
    return ret
}

func getEntitlement(_ ent: String) -> String {
    var ret: String = ""
    withSecEntitlement(for: ent) { entitlement in
        if let entitlement = entitlement as? String {
            ret = entitlement
        } else if let entitlement = entitlement as? NSString as? String {
            ret = entitlement
        }
    }
    return ret
}

func getAppGroups() -> [String] {
    var ret: [String] = []
    withSecEntitlement(for: "com.apple.security.application-groups") { groups in
        if let groups = groups as? [String] {
            ret = groups
        } else if let groups = groups as? NSArray as? [String] {
            ret = groups
        } else if CFGetTypeID(groups) == CFArrayGetTypeID() {
            ret = groups as! CFArray as NSArray as? [String] ?? []
        }
    }
    return ret
}
