import SwiftUI

/// iPad controls move locally; the drag handle never forwards pointer events.
struct FloatingKeyboardToolbar: View {
    @ObservedObject var viewModel: SessionViewModel
    @Binding var showingCustomization: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var collapsed = false
    @State private var showingQuickMenu = false
    @State private var offset = CGSize.zero
    @State private var height: CGFloat = 104
    @GestureState private var isDragging = false
    @State private var previousTranslation = CGSize.zero

    var body: some View {
        GeometryReader { geometry in
            let width = collapsed ? 56 : min(720, max(56, geometry.size.width - 32))
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    if !collapsed {
                        Capsule().fill(.secondary).frame(width: 40, height: 5)
                            .frame(maxWidth: .infinity).frame(height: 44)
                            .contentShape(Rectangle())
                            .accessibilityLabel(AppLocalization.string("Move Keyboard Toolbar"))
                            .accessibilityIdentifier("floating-toolbar-handle")
                            .gesture(moveGesture(size: geometry.size, width: width))
                    }
                    Button { if !showingQuickMenu { collapsed.toggle() } } label: {
                        Image(systemName: collapsed ? "chevron.right" : "chevron.left")
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(ControlPressStyle())
                    .accessibilityLabel(AppLocalization.string(collapsed ? "Expand Keyboard Toolbar" : "Collapse Keyboard Toolbar"))
                    .accessibilityIdentifier("floating-toolbar-collapse")
                    .highPriorityGesture(collapsed ? moveGesture(size: geometry.size, width: width) : nil)
                    .highPriorityGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in showingQuickMenu = true })
                    .popover(isPresented: $showingQuickMenu, arrowEdge: .top) {
                        VStack(alignment: .leading, spacing: 0) {
                            quickAction("esc") { viewModel.sendKeyTap(MacKeyMap.escape) }
                            Divider()
                            quickAction("tab") { viewModel.sendKeyTap(MacKeyMap.tab) }
                            Divider()
                            quickAction("Paste Text") { viewModel.syncClipboardToMac() }
                        }
                        .buttonStyle(.borderless)
                        .padding(12)
                        .frame(minWidth: 180)
                    }
                }
                // Keep the toolbar mounted so collapsing preserves Fn/text state.
                MacKeyboardToolbar(viewModel: viewModel, showingCustomization: $showingCustomization, isCollapsed: collapsed)
                    .frame(height: collapsed ? 0 : nil)
                    .opacity(collapsed ? 0 : 1)
                    .clipped()
                    .allowsHitTesting(!collapsed)
                    .accessibilityHidden(collapsed)
            }
            .frame(width: width)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.2), radius: 10, y: 3)
            .background(GeometryReader { size in
                Color.clear.preference(key: FloatingToolbarHeight.self, value: size.size.height)
            })
            .onPreferenceChange(FloatingToolbarHeight.self) { height = $0 }
            .position(x: FloatingToolbarGeometry.clamp(geometry.size.width / 2 + offset.width, half: width / 2, length: geometry.size.width),
                      y: FloatingToolbarGeometry.clamp(geometry.size.height * 0.75 + offset.height, half: height / 2, length: geometry.size.height))
            .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.9), value: collapsed)
        }
        .coordinateSpace(name: "floating-keyboard")
        .onChange(of: isDragging) { _, dragging in
            if !dragging { previousTranslation = .zero }
        }
    }

    private func quickAction(_ title: String, perform: @escaping () -> Void) -> some View {
        Button {
            perform(); showingQuickMenu = false
        } label: {
            Text(AppLocalization.string(title))
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
    }

    private func moveGesture(size: CGSize, width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .named("floating-keyboard"))
            .updating($isDragging) { _, state, _ in
                state = true
            }
            .onChanged { value in
                let delta = CGSize(width: value.translation.width - previousTranslation.width,
                                   height: value.translation.height - previousTranslation.height)
                previousTranslation = value.translation
                offset = FloatingToolbarGeometry.moving(offset: offset, delta: delta, size: size,
                                                         toolbar: CGSize(width: width, height: height))
            }
            .onEnded { _ in previousTranslation = .zero }
    }
}

private struct FloatingToolbarHeight: PreferenceKey {
    static let defaultValue: CGFloat = 104
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
