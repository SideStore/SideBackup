//
//  ContentView.swift
//  SideBackup
//
//  Created by ny on 1/22/26.
//

struct ContentView: View {
    private let new = ContainerManager()
    @State private var isExporting: Bool = false
    @State private var isImporting: Bool = false
    @State private var fileToShare: URL?
    
    var body: some View {
        VStack {
            Button("Import Backup") {
                isImporting = true
            }
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [.archive]) { result in
                Task {
                    switch result {
                    case .success(let url):
                        print("Restore from \(url.path)")
                        Task {
                            do {
                                try await new.restore(from: url)
                            } catch { print(error.localizedDescription) }
                        }
                    case .failure(let error):
                        print("Failed to import: \(error.localizedDescription)")
                    }
                }
                isImporting = false
            }
            Button("Export Backup") {
                Task {
                    fileToShare = try await new.backup()
                    isExporting = true
                }
            }
            .fileExporter(isPresented: $isExporting, document: SideBackup(fileToShare), contentType: .archive, defaultFilename: "side.tar") { res in
                switch res {
                case .success(let url):
                    print("Saved to \(url.path)!")
                case .failure(let error):
                    print("Failed to export: \(error.localizedDescription)")
                }
                isExporting = false
                fileToShare.clearIf { f in
                    try? f.delete()
                }
            }
            Button("Print Files") {
                Task {
                    await new.printAll()
                }
            }
            Button("Nuke Files") {
                Task {
                    await new.removeAll()
                }
            }
        }
        .padding()
    }
}

#Preview {
    ContentView()
}

