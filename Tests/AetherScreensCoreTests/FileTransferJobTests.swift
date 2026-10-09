import XCTest
@testable import AetherScreensCore

final class FileTransferJobTests: XCTestCase {
    func testCancelRejectsLateProgressCompletionAndFailure() throws {
        var job = FileTransferJob(direction: .upload, filename: "example.txt", totalBytes: 10)
        let attempt = try XCTUnwrap(job.start())
        XCTAssertTrue(job.recordProgress(10, attempt: attempt))
        XCTAssertEqual(job.state, .transferring)
        XCTAssertTrue(job.cancel())
        XCTAssertFalse(job.recordProgress(10, attempt: attempt))
        XCTAssertFalse(job.finish(attempt: attempt, transferSucceeded: true, destinationFinalized: true))
        XCTAssertFalse(job.fail("Late failure", attempt: attempt))
        XCTAssertNil(job.start())
        XCTAssertEqual(job.state, .cancelled)
    }

    func testReconnectRequiresConfirmedOffsetAndRejectsOldTransport() throws {
        var job = FileTransferJob(direction: .download, filename: "example.mov", totalBytes: 100)
        let old = try XCTUnwrap(job.start())
        XCTAssertTrue(job.recordProgress(60, attempt: old))
        XCTAssertTrue(job.pause(attempt: old))
        XCTAssertNil(job.resume(confirmedOffset: 61))
        let resumed = try XCTUnwrap(job.resume(confirmedOffset: 40))
        XCTAssertEqual(job.transferredBytes, 40)
        XCTAssertFalse(job.recordProgress(100, attempt: old))
        XCTAssertFalse(job.fail("Old socket closed", attempt: old))
        XCTAssertTrue(job.recordProgress(100, attempt: resumed))
        XCTAssertTrue(job.finish(attempt: resumed, transferSucceeded: true, destinationFinalized: true))
        XCTAssertEqual(job.state, .completed)
    }

    func testOverwriteRequiresExplicitDecisionAndDoesNotOpenEarly() throws {
        var job = FileTransferJob(direction: .upload, filename: "report.pdf", totalBytes: 1)
        XCTAssertTrue(job.awaitOverwriteDecision())
        XCTAssertNil(job.start())
        let token = try XCTUnwrap(job.start(overwriteApproved: true))
        XCTAssertFalse(job.finish(attempt: token, transferSucceeded: true, destinationFinalized: true))
        XCTAssertFalse(job.recordProgress(2, attempt: token))
        XCTAssertTrue(job.recordProgress(1, attempt: token))
        XCTAssertFalse(job.recordProgress(0, attempt: token))
        XCTAssertTrue(job.finish(attempt: token, transferSucceeded: true, destinationFinalized: true))
        XCTAssertFalse(job.cancel())
    }

    func testCompleteBytesRequireBothSessionSuccessAndDestinationFinalization() throws {
        var job = FileTransferJob(direction: .download, filename: "report", totalBytes: 5)
        let token = try XCTUnwrap(job.start())
        XCTAssertTrue(job.recordProgress(5, attempt: token))
        for (success, saved) in [(false, false), (true, false), (false, true)] {
            XCTAssertFalse(job.finish(attempt: token, transferSucceeded: success, destinationFinalized: saved))
            XCTAssertEqual(job.state, .transferring)
            XCTAssertEqual(job.attempt, token)
        }
        XCTAssertTrue(job.finish(attempt: token, transferSucceeded: true, destinationFinalized: true))
        XCTAssertFalse(job.finish(attempt: token, transferSucceeded: true, destinationFinalized: true))
    }

    func testRenamedDestinationIsRetainedOnlyOnValidFinalCompletion() throws {
        var job = FileTransferJob(direction: .upload, filename: "fixture.bin", totalBytes: 512)
        let token = try XCTUnwrap(job.start())
        let actual = Data("fixture 2.bin".utf8)
        XCTAssertTrue(job.recordProgress(512, attempt: token))
        XCTAssertFalse(job.finish(attempt: token, transferSucceeded: true,
                                  destinationFinalized: false, destinationNameBytes: actual))
        XCTAssertNil(job.destinationNameBytes)
        for invalid in [Data([65, 0]), Data(repeating: 65, count: 1024)] {
            XCTAssertFalse(job.finish(attempt: token, transferSucceeded: true,
                                      destinationFinalized: true, destinationNameBytes: invalid))
            XCTAssertEqual(job.state, .transferring)
            XCTAssertNil(job.destinationNameBytes)
        }
        XCTAssertTrue(job.finish(attempt: token, transferSucceeded: true,
                                 destinationFinalized: true, destinationNameBytes: actual))
        XCTAssertEqual(job.filename, "fixture.bin")
        XCTAssertEqual(job.destinationNameBytes, actual)
        XCTAssertFalse(job.finish(attempt: token, transferSucceeded: true,
                                  destinationFinalized: true, destinationNameBytes: Data("wrong".utf8)))
        XCTAssertEqual(job.destinationNameBytes, actual)
    }

    func testDestinationResultFromObsoleteAttemptCannotMutateResumedOrCancelledJob() throws {
        var job = FileTransferJob(direction: .upload, filename: "A", totalBytes: 0)
        let old = try XCTUnwrap(job.start())
        XCTAssertTrue(job.pause(attempt: old))
        let fresh = try XCTUnwrap(job.resume(confirmedOffset: 0))
        XCTAssertFalse(job.finish(attempt: old, transferSucceeded: true,
                                  destinationFinalized: true, destinationNameBytes: Data([0xff])))
        XCTAssertNil(job.destinationNameBytes)
        XCTAssertTrue(job.cancel())
        XCTAssertFalse(job.finish(attempt: fresh, transferSucceeded: true,
                                  destinationFinalized: true, destinationNameBytes: Data([0xff])))
        XCTAssertNil(job.destinationNameBytes)
    }

    func testDisplayUsesVerifiedEncodingAndFallsBackWithoutReplacementDecoding() throws {
        for actual in [Data("测试-屏幕😀 2.bin".utf8), Data([0xff]), Data()] {
            var job = FileTransferJob(direction: .upload, filename: "requested.bin", totalBytes: 0)
            let token = try XCTUnwrap(job.start())
            XCTAssertTrue(job.finish(attempt: token, transferSucceeded: true,
                destinationFinalized: true, destinationNameBytes: actual))
            XCTAssertEqual(job.displayFilename(), "requested.bin")
            let decoded = String(data: actual, encoding: .utf8)
            XCTAssertEqual(job.displayFilename(destinationEncoding: .utf8),
                           decoded.flatMap { $0.isEmpty ? nil : $0 } ?? "requested.bin")
            XCTAssertEqual(job.destinationNameBytes, actual)
        }
    }

    func testEmptyAndVeryLargeFilesHaveFiniteProgress() throws {
        var empty = FileTransferJob(direction: .download, filename: "empty", totalBytes: 0)
        XCTAssertEqual(empty.fractionCompleted, 0)
        let token = try XCTUnwrap(empty.start())
        XCTAssertTrue(empty.finish(attempt: token, transferSucceeded: true, destinationFinalized: true))
        XCTAssertEqual(empty.fractionCompleted, 1)
        var large = FileTransferJob(direction: .upload, filename: "large", totalBytes: .max)
        let largeToken = try XCTUnwrap(large.start())
        XCTAssertTrue(large.recordProgress(UInt64.max / 2, attempt: largeToken))
        XCTAssertEqual(large.fractionCompleted, 0.5, accuracy: 0.0001)
    }
}
