import SwiftUI
import UniformTypeIdentifiers
import Foundation

struct EmptyFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.image] }
    
    init() {}
    
    init(configuration: ReadConfiguration) throws {}
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper()
    }
}