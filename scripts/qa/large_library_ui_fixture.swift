// Included only in the generated QA app, never the production app source.
import UIKit

@MainActor
private enum LargeLibraryUIFixture {
    private static let count = 64
    static func prepare() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let token = environment["AETHERSCREENS_LIBRARY_QA_TOKEN"], UUID(uuidString: token) != nil else { return }
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let journal = caches.appendingPathComponent("large-library-qa-owned.json")
        var owned = FileManager.default.fileExists(atPath: journal.path)
            ? try JSONDecoder().decode([String: [UUID]].self, from: Data(contentsOf: journal)) : [:]
        let action = environment["AETHERSCREENS_LIBRARY_QA_ACTION"]
        let store = DeviceStore.shared
        if action == "cleanup" {
            for (index, id) in (owned[token] ?? []).enumerated() {
                let name = "QA Scroll " + token + String(format: " %03d", index + 1)
                if let device = store.devices.first(where: { $0.id == id }) {
                    guard device.name == name, store.deleteDevice(device) else { throw CocoaError(.fileWriteUnknown) }
                }
                ThumbnailStore.shared.removeThumbnail(for: id)
                for suffix in ["jpg", "png"] {
                    let file = caches.appendingPathComponent("AetherScreens/DesktopThumbnails/\(id).\(suffix)")
                    guard !FileManager.default.fileExists(atPath: file.path) else { throw CocoaError(.fileWriteUnknown) }
                }
            }
            owned.removeValue(forKey: token)
            try JSONEncoder().encode(owned).write(to: journal, options: .atomic)
            return
        }
        guard action == "seed", owned[token] == nil else { return }
        let ids = (0..<count).map { _ in UUID() }
        owned[token] = ids
        try JSONEncoder().encode(owned).write(to: journal, options: .atomic)
        for (index, id) in ids.enumerated() {
            let name = "QA Scroll " + token + String(format: " %03d", index + 1)
            store.addDevice(RemoteDevice(id: id, name: name, host: "preview-qa.invalid", authMethod: .none, isOnline: false))
            guard let context = CGContext(data: nil, width: 480, height: 300, bitsPerComponent: 8,
                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw CocoaError(.fileWriteUnknown) }
            for row in 0..<6 {
                for column in 0..<8 {
                    context.setFillColor(CGColor(red: 0.12 + Double(index % 5) * 0.025,
                        green: 0.2 + Double(row) * 0.1, blue: 0.25 + Double(column) * 0.07, alpha: 1))
                    context.fill(CGRect(x: column * 60, y: row * 50, width: 60, height: 50))
                }
            }
            guard let image = context.makeImage() else { throw CocoaError(.fileWriteUnknown) }
            ThumbnailStore.shared.saveThumbnail(image, for: id)
        }
    }
}
