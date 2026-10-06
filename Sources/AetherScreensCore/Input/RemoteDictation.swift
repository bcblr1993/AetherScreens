import AVFoundation
import Speech
import Combine

/// Captures only after an explicit start. Audio stays on this device and text
/// stays in the preview until the user confirms sending it.
@MainActor
final class RemoteDictation: ObservableObject {
    enum Phase: Equatable { case idle, requesting, listening, finishing, ready, failed }
    @Published private(set) var phase: Phase = .idle
    @Published var transcript = ""
    @Published private(set) var errorKey: String?
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognition: SFSpeechRecognitionTask?
    private var activeRecognizer: SFSpeechRecognizer?
    private var token = UUID()
    private var hasTap = false
    private var audioSessionActive = false
    private let speechAuthorization: () async -> Bool
    private let microphoneAuthorization: () async -> Bool

    init(speechAuthorization: (() async -> Bool)? = nil,
         microphoneAuthorization: (() async -> Bool)? = nil) {
        self.speechAuthorization = speechAuthorization ?? {
            await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
            }
        }
        self.microphoneAuthorization = microphoneAuthorization ?? {
            await AVCaptureDevice.requestAccess(for: .audio)
        }
    }

    func start(locale: Locale) async {
        guard phase != .requesting && phase != .listening && phase != .finishing else { return }
        cancel()
        phase = .requesting
        let current = token
        let speech = await speechAuthorization()
        guard token == current else { return }
        guard speech else { fail("Allow Speech Recognition in system settings to use Dictation."); return }
        let microphone = await microphoneAuthorization()
        guard token == current else { return }
        guard microphone else { fail("Allow Microphone access in system settings to use Dictation."); return }
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable,
              recognizer.supportsOnDeviceRecognition else {
            fail("On-device Dictation is unavailable for this language."); return
        }
        do {
            activeRecognizer = recognizer
            #if canImport(UIKit)
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [])
            try session.setActive(true)
            audioSessionActive = true
            #endif
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0 && format.channelCount > 0 else {
                fail("The microphone is unavailable. Try again."); return
            }
            let bufferRequest = SFSpeechAudioBufferRecognitionRequest()
            bufferRequest.requiresOnDeviceRecognition = true
            bufferRequest.shouldReportPartialResults = true
            request = bufferRequest
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                bufferRequest.append(buffer)
            }
            hasTap = true
            recognition = recognizer.recognitionTask(with: bufferRequest) { [weak self] result, error in
                let text = result?.bestTranscription.formattedString
                let final = result?.isFinal == true
                let failed = error != nil
                Task { @MainActor [weak self] in
                    guard let self, self.token == current else { return }
                    if let text { self.transcript = text }
                    if final { self.complete() }
                    else if failed {
                        if self.phase == .finishing && !self.transcript.isEmpty { self.complete() }
                        else { self.fail("Dictation stopped. Try again.") }
                    }
                }
            }
            engine.prepare()
            try engine.start()
            phase = .listening
        } catch { fail("The microphone is unavailable. Try again.") }
    }

    func stop() {
        guard phase == .listening else { return }
        phase = .finishing
        stopCapture()
        request?.endAudio()
        let current = token
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, self.token == current, self.phase == .finishing else { return }
            self.complete()
        }
    }

    func cancel() {
        token = UUID()
        stopCapture()
        request?.endAudio()
        recognition?.cancel()
        recognition = nil
        activeRecognizer = nil
        request = nil
        transcript = ""
        errorKey = nil
        phase = .idle
    }

    private func stopCapture() {
        engine.stop()
        if hasTap { engine.inputNode.removeTap(onBus: 0); hasTap = false }
        #if canImport(UIKit)
        if audioSessionActive {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            audioSessionActive = false
        }
        #endif
    }

    private func complete() {
        token = UUID()
        stopCapture()
        request?.endAudio()
        recognition?.cancel()
        recognition = nil
        activeRecognizer = nil
        request = nil
        phase = .ready
    }

    private func fail(_ key: String) {
        complete()
        errorKey = key
        phase = .failed
    }
}
