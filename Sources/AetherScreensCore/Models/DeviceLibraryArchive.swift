import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Portable, non-secret JSON archive of saved computer configurations.
public struct DeviceLibraryArchive: Codable, Sendable {
    public enum ArchiveError: LocalizedError, Sendable {
        case unsupportedVersion(Int)
        case invalidEndpoint(String)

        public var errorDescription: String? {
            switch self {
            case .unsupportedVersion(let v):
                return "Unsupported archive schema version \(v)."
            case .invalidEndpoint(let host):
                return "Invalid computer host or port in archive: \(host)"
            }
        }
    }

    public let schemaVersion: Int
    public let exportedAt: Date
    public let computers: [RemoteDevice]

    public init(schemaVersion: Int = 1, exportedAt: Date = Date(), computers: [RemoteDevice]) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.computers = computers
    }

    /// Exports the given devices into pretty-printed, sorted-key JSON data.
    /// Private key references are stripped to avoid dangling Keychain UUIDs across machines.
    public static func export(devices: [RemoteDevice], exportedAt: Date = Date()) throws -> Data {
        let sanitized = devices.map { dev -> RemoteDevice in
            var copy = dev
            if case .privateKey = copy.ssh?.authentication, let ssh = copy.ssh {
                copy.ssh = SSHConnectionSettings(
                    server: ssh.server,
                    username: ssh.username,
                    authentication: .password,
                    remoteHost: ssh.remoteHost
                )
            }
            return copy
        }
        let archive = DeviceLibraryArchive(schemaVersion: 1, exportedAt: exportedAt, computers: sanitized)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(archive)
    }

    /// Decodes and validates a `DeviceLibraryArchive` from JSON data.
    public static func decode(_ data: Data) throws -> [RemoteDevice] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let archive = try decoder.decode(DeviceLibraryArchive.self, from: data)
        guard archive.schemaVersion == 1 else {
            throw ArchiveError.unsupportedVersion(archive.schemaVersion)
        }
        for computer in archive.computers {
            guard ConnectionRequest(host: computer.host, port: String(computer.port)) != nil else {
                throw ArchiveError.invalidEndpoint("\(computer.host):\(computer.port)")
            }
        }
        return archive.computers
    }
}

public struct DeviceLibraryDocument: FileDocument {
    public static var readableContentTypes: [UTType] { [.json] }
    public var data: Data

    public init(data: Data) {
        self.data = data
    }

    public init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }

    public func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
