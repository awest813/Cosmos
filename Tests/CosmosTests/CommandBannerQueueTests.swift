import XCTest
@testable import Cosmos

final class CommandBannerQueueTests: XCTestCase {
    func testEnqueueAndDismiss() {
        var queue = CommandBannerQueue()
        XCTAssertNil(queue.current)
        queue.enqueue(CommandBanner(kind: .info, message: "First"))
        XCTAssertEqual(queue.current?.message, "First")
        XCTAssertEqual(queue.pendingCount, 0)
        queue.enqueue(CommandBanner(kind: .success, message: "Second"))
        XCTAssertEqual(queue.pendingCount, 1)
        queue.dismissCurrent()
        XCTAssertEqual(queue.current?.message, "Second")
    }

    func testCoalesceDuplicateMessages() {
        var queue = CommandBannerQueue()
        queue.enqueue(CommandBanner(kind: .info, message: "Same"))
        queue.enqueue(CommandBanner(kind: .info, message: "Same"))
        XCTAssertEqual(queue.pendingCount, 0)
    }

    func testClearTransientKeepsFailures() {
        var queue = CommandBannerQueue()
        queue.enqueue(CommandBanner(kind: .failure, message: "Broken"))
        queue.enqueue(CommandBanner(kind: .success, message: "OK"))
        queue.clearTransient()
        XCTAssertEqual(queue.current?.kind, .failure)
        XCTAssertEqual(queue.pendingCount, 0)
    }
}
