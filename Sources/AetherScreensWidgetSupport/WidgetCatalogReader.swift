import Foundation

/// Each query reads the current projection, so removed IDs never use a cached alias.
public struct WidgetCatalogReader: Sendable {
    private let readData: @Sendable () -> Data?

    public init(readData: @escaping @Sendable () -> Data?) {
        self.readData = readData
    }

    public func read() -> WidgetCatalog {
        WidgetCatalog.decode(readData()) ?? WidgetCatalog()
    }

    public static func standard() -> WidgetCatalogReader {
        WidgetCatalogReader(readData: { WidgetSharedStorage.read() })
    }
}
