//
//  SideBack.swift
//  SideBackup
//
//  Created by ny on 2/9/26.
//

struct SideBackup: FileDocument {
    var data: Data
    init(_ data: Data) {
        self.data = data
    }
    init(_ url: URL?) {
        if let url,
           let data = try? Data(contentsOf: url) {
            self.data = data
        } else { self.data = Data() }
    }
    static let readableContentTypes: [UTType] = [.archive]
    
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
/**
 date.sbk/
   Info.plist // SideBackupMeta
   tmp.tar
   lib.tar
   doc.tar
 */

struct SideBackupMeta: Codable {
    let name: String
    let team: String
    let bundle: String
    let date: Date
    let size: UInt64
    static let version: UInt = 0
}
