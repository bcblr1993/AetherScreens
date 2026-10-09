import SwiftUI
import UniformTypeIdentifiers

/// Original key bytes for an explicitly requested native export; no defaults/log mirror.
struct SSHPrivateKeyDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText, .data] }
    static var writableContentTypes: [UTType] { [.plainText] }
    private let data: Data

    init(data: Data) throws {
        _ = try SSHPrivateKey.decode(data)
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw SSHPrivateKey.Failure.invalid }
        try self.init(data: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { makeFileWrapper() }

    func makeFileWrapper() -> FileWrapper {
        let wrapper = FileWrapper(regularFileWithContents: data)
        wrapper.fileAttributes = [
            FileAttributeKey.type.rawValue: FileAttributeType.typeRegular,
            FileAttributeKey.posixPermissions.rawValue: NSNumber(value: 0o600)
        ]
        return wrapper
    }
}
