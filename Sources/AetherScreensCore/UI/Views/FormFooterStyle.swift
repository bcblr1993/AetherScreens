import SwiftUI

extension View {
    /// Grouped forms on macOS trail-align section footers; keep explanatory text flush with the rows above.
    func formFooterStyle() -> some View {
        multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
