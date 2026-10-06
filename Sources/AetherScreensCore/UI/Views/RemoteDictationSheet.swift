import SwiftUI

struct RemoteDictationSheet: View {
    @ObservedObject var viewModel: SessionViewModel
    @StateObject private var dictation = RemoteDictation()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var language = AppLocalization.identifier(for: AppLocalization.language).hasPrefix("zh") ? "zh-CN" : "en-US"

    private var canSend: Bool {
        viewModel.canSendDictation && (dictation.phase == .ready || dictation.phase == .failed)
            && !dictation.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker(AppLocalization.string("Dictation Language"), selection: $language) {
                    Text("English").tag("en-US")
                    Text("简体中文").tag("zh-CN")
                }
                .disabled(dictation.phase == .requesting || dictation.phase == .listening || dictation.phase == .finishing)
                Section {
                    TextEditor(text: $dictation.transcript)
                        .frame(minHeight: 140)
                        .disabled(dictation.phase == .requesting || dictation.phase == .listening || dictation.phase == .finishing)
                        .accessibilityLabel(AppLocalization.string("Dictation Preview"))
                        .accessibilityIdentifier("dictation-preview")
                } footer: {
                    Text(AppLocalization.string("Review the recognized text before sending it to the remote computer."))
                }
                if let error = dictation.errorKey { Text(AppLocalization.string(error)).foregroundStyle(.secondary) }
                if dictation.phase == .requesting || dictation.phase == .finishing {
                    ProgressView(AppLocalization.string(dictation.phase == .requesting ? "Preparing Dictation…" : "Finishing Dictation…"))
                } else if dictation.phase == .listening {
                    Button { dictation.stop() } label: {
                        Label(AppLocalization.string("Stop Dictation"), systemImage: "stop.circle")
                    }.accessibilityIdentifier("dictation-stop")
                } else {
                    Button {
                        Task { await dictation.start(locale: Locale(identifier: language)) }
                    } label: { Label(AppLocalization.string("Start Dictation"), systemImage: "mic") }
                    .disabled(!viewModel.canSendDictation)
                    .accessibilityIdentifier("dictation-start")
                }
            }
            .navigationTitle(AppLocalization.string("Dictation"))
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalization.string("Cancel")) { dictation.cancel(); dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppLocalization.string("Send")) {
                        guard canSend else { return }
                        viewModel.sendDictation(dictation.transcript)
                        dictation.cancel()
                        dismiss()
                    }.disabled(!canSend).accessibilityIdentifier("dictation-send")
                }
            }
        }
        #if canImport(AppKit)
        .frame(minWidth: 420, minHeight: 360)
        #endif
        .onDisappear { dictation.cancel() }
        .onChange(of: viewModel.canSendDictation) { _, allowed in
            if !allowed { dictation.cancel(); dismiss() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { dictation.cancel(); dismiss() }
        }
    }
}
