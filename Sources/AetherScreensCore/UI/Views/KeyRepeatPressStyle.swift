import SwiftUI

/// Leaves tap/scroll recognition to Button. Repetition starts only after a hold.
@MainActor
final class KeyRepeatPress: ObservableObject {
    private var task: Task<Void, Never>?
    private var finish: (() -> Void)?
    private(set) var didRepeat = false

    func pressed(_ pressed: Bool, repeatAction: @escaping () -> Void, endAction: @escaping () -> Void, delayNanoseconds: UInt64 = 450_000_000, intervalNanoseconds: UInt64 = 65_000_000) {
        if !pressed { stop(); return }
        stop()
        didRepeat = false
        task = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: delayNanoseconds) } catch { return }
            guard let self, !Task.isCancelled else { return }
            self.didRepeat = true
            self.finish = endAction
            repeatAction()
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: intervalNanoseconds) } catch { return }
                guard !Task.isCancelled else { return }
                repeatAction()
            }
        }
    }

    func activate(_ tap: () -> Void) {
        let repeated = didRepeat
        didRepeat = false
        if !repeated { tap() }
    }

    func stop() {
        task?.cancel()
        task = nil
        let completion = finish
        finish = nil
        completion?()
    }
}

struct KeyRepeatPressStyle: ButtonStyle {
    @ObservedObject var press: KeyRepeatPress
    var repeatAction: () -> Void
    var endAction: () -> Void
    var enabled: Bool
    var mode: KeyboardToolbarConfiguration.KeyRepeat = .normal
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.78 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { pressed in
                press.pressed(pressed && enabled && scenePhase == .active, repeatAction: repeatAction, endAction: endAction, delayNanoseconds: mode.delayNanoseconds, intervalNanoseconds: mode.intervalNanoseconds)
            }
            .onChange(of: mode) { _ in press.stop() }
            .onChange(of: enabled) { value in if !value { press.stop() } }
            .onChange(of: scenePhase) { value in if value != .active { press.stop() } }
            .onDisappear { press.stop() }
    }
}
