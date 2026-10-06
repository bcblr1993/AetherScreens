import XCTest
@testable import AetherScreensCore

@MainActor
final class RemoteDictationTests: XCTestCase {
    func testDeniedSpeechDoesNotRequestMicrophoneOrStartRecording() async {
        var microphoneRequests = 0
        let dictation = RemoteDictation(speechAuthorization: { false }, microphoneAuthorization: {
            microphoneRequests += 1
            return true
        })
        await dictation.start(locale: Locale(identifier: "en-US"))
        XCTAssertEqual(microphoneRequests, 0)
        XCTAssertEqual(dictation.phase, .failed)
        XCTAssertEqual(dictation.errorKey, "Allow Speech Recognition in system settings to use Dictation.")
        XCTAssertEqual(dictation.transcript, "")
    }

    func testDeniedMicrophoneProducesRecoverableErrorAndCancelClearsPreview() async {
        let dictation = RemoteDictation(speechAuthorization: { true }, microphoneAuthorization: { false })
        await dictation.start(locale: Locale(identifier: "zh-CN"))
        XCTAssertEqual(dictation.phase, .failed)
        XCTAssertEqual(dictation.errorKey, "Allow Microphone access in system settings to use Dictation.")
        dictation.transcript = "unsent QA preview"
        dictation.cancel()
        XCTAssertEqual(dictation.phase, .idle)
        XCTAssertNil(dictation.errorKey)
        XCTAssertEqual(dictation.transcript, "")
        await dictation.start(locale: Locale(identifier: "zh-CN"))
        XCTAssertEqual(dictation.phase, .failed)
    }

    func testCancelledSpeechPermissionReplyCannotRequestMicrophone() async {
        var reply: CheckedContinuation<Bool, Never>?
        let requested = expectation(description: "Speech permission requested")
        var microphoneRequests = 0
        let dictation = RemoteDictation(speechAuthorization: {
            await withCheckedContinuation { continuation in
                reply = continuation
                requested.fulfill()
            }
        }, microphoneAuthorization: { microphoneRequests += 1; return true })
        let start = Task { await dictation.start(locale: Locale(identifier: "en-US")) }
        await fulfillment(of: [requested], timeout: 2)
        XCTAssertEqual(dictation.phase, .requesting)
        dictation.cancel()
        reply?.resume(returning: true)
        await start.value
        XCTAssertEqual(microphoneRequests, 0)
        XCTAssertEqual(dictation.phase, .idle)
        XCTAssertNil(dictation.errorKey)
    }

    func testCancelledMicrophoneReplyCannotStartCaptureOrOverwriteNewAttempt() async {
        var firstReply: CheckedContinuation<Bool, Never>?
        let requested = expectation(description: "Microphone permission requested")
        var requests = 0
        let dictation = RemoteDictation(speechAuthorization: { true }, microphoneAuthorization: {
            requests += 1
            if requests > 1 { return false }
            return await withCheckedContinuation { continuation in
                firstReply = continuation
                requested.fulfill()
            }
        })
        let first = Task { await dictation.start(locale: Locale(identifier: "en-US")) }
        await fulfillment(of: [requested], timeout: 2)
        dictation.cancel()
        await dictation.start(locale: Locale(identifier: "zh-CN"))
        firstReply?.resume(returning: true)
        await first.value
        XCTAssertEqual(requests, 2)
        XCTAssertEqual(dictation.phase, .failed)
        XCTAssertEqual(dictation.errorKey, "Allow Microphone access in system settings to use Dictation.")
        XCTAssertEqual(dictation.transcript, "")
    }
}
