import Foundation

public enum WidgetLaunchURL {
    public static let libraryURL = URL(string: "aetherscreens://library")!

    public static func url(for id: UUID) -> URL {
        URL(string: "aetherscreens://widget/" + id.uuidString)!
    }

    public static func parse(_ url: URL) -> UUID? {
        guard url.baseURL == nil,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "aetherscreens", components.percentEncodedHost == "widget",
              components.user == nil, components.password == nil, components.port == nil,
              components.query == nil, components.fragment == nil else { return nil }
        let path = components.percentEncodedPath
        guard path.hasPrefix("/"), path.utf8.count == 37, !path.contains("%") else { return nil }
        let identifier = String(path.dropFirst())
        let bytes = Array(identifier.utf8)
        let hyphens: Set<Int> = [8, 13, 18, 23]
        guard bytes.enumerated().allSatisfy({ index, byte in
            if hyphens.contains(index) { return byte == 45 }
            return (48...57).contains(byte) || (65...70).contains(byte) || (97...102).contains(byte)
        }), let id = UUID(uuidString: identifier),
              url.absoluteString == "aetherscreens://widget/" + identifier else { return nil }
        return id
    }
}
