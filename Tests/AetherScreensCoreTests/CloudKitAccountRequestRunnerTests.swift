import XCTest
import CloudKit
@testable import AetherScreensCore

final class CloudKitAccountRequestRunnerTests: XCTestCase {
    func testProviderFailureIsPreserved() async {
        do {
            let _: Int = try await CloudKitAccountRequestRunner.run { $0(.failure(CKError(.notAuthenticated))) }
            XCTFail("Provider failure must propagate")
        } catch { XCTAssertEqual((error as? CKError)?.code, .notAuthenticated) }
    }

    func testImmediateAndRepeatedCallbackPreserveFirstResult() async throws {
        let value: Int = try await CloudKitAccountRequestRunner.run {
            $0(.success(42))
            $0(.success(99))
        }
        XCTAssertEqual(value, 42)
    }

    func testMissingCallbackTimesOutWithoutWaitingForSDK() async {
        let clock = ContinuousClock()
        let began = clock.now
        do {
            let _: Int = try await CloudKitAccountRequestRunner.run(timeout: .milliseconds(20)) { _ in }
            XCTFail("A missing callback must time out")
        } catch { XCTAssertEqual(error as? CloudKitAccountRequestRunner.Failure, .timedOut) }
        XCTAssertLessThan(began.duration(to: clock.now), .seconds(2))
    }

    func testPreCancelledTaskDoesNotStartRequest() async {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            let _: Int = try await CloudKitAccountRequestRunner.run { _ in XCTFail("Cancelled request started") }
        }
        do { try await task.value; XCTFail("Cancellation must fail") }
        catch { XCTAssertTrue(error is CancellationError) }
    }

    func testCancellationReturnsBeforeCallbackAndLateReplyIsIgnored() async throws {
        let started = expectation(description: "request started")
        let callback = CallbackBox()
        let task = Task {
            try await CloudKitAccountRequestRunner.run(timeout: .seconds(10)) {
                callback.store($0); started.fulfill()
            }
        }
        await fulfillment(of: [started], timeout: 2)
        task.cancel()
        do { let _ = try await task.value; XCTFail("Cancellation must fail") }
        catch { XCTAssertTrue(error is CancellationError) }
        callback.reply(.success(7))
        let next: Int = try await CloudKitAccountRequestRunner.run { $0(.success(8)) }
        XCTAssertEqual(next, 8)
    }

    func testLateReplyAfterTimeoutCannotResumeAgain() async throws {
        let callback = CallbackBox()
        do {
            let _: Int = try await CloudKitAccountRequestRunner.run(timeout: .milliseconds(20)) { callback.store($0) }
            XCTFail("A missing callback must time out")
        } catch { XCTAssertEqual(error as? CloudKitAccountRequestRunner.Failure, .timedOut) }
        callback.reply(.success(7))
        callback.reply(.failure(CancellationError()))
        let next: Int = try await CloudKitAccountRequestRunner.run { $0(.success(8)) }
        XCTAssertEqual(next, 8)
    }

    func testExpiredDeadlineDoesNotStartRequest() async {
        do {
            let _: Int = try await CloudKitAccountRequestRunner.run(timeout: .zero) { _ in XCTFail("Expired request started") }
            XCTFail("Expired deadline must fail")
        } catch { XCTAssertEqual(error as? CloudKitAccountRequestRunner.Failure, .timedOut) }
    }

    private final class CallbackBox: @unchecked Sendable {
        private let lock = NSLock()
        private var completion: (@Sendable (Result<Int, Error>) -> Void)?
        func store(_ completion: @escaping @Sendable (Result<Int, Error>) -> Void) {
            lock.lock(); self.completion = completion; lock.unlock()
        }
        func reply(_ result: Result<Int, Error>) {
            lock.lock(); let callback = completion; lock.unlock()
            callback?(result)
        }
    }
}
