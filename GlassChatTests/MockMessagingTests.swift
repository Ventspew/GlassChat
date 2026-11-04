import XCTest
@testable import GlassChat

final class MockMessagingTests: XCTestCase {
    func testSendAppendsOutgoingMessage() async throws {
        let service = MockMessagingService()
        let chat = ChatID("chat-emma")

        let stream = await service.observeMessages(in: chat)
        var iterator = stream.makeAsyncIterator()
        let initial = await iterator.next()
        XCTAssertEqual(initial?.isEmpty, false)

        try await service.send(text: "Hallo daar", to: chat, replyTo: nil)
        let updated = await iterator.next()
        XCTAssertEqual(updated?.last?.body.plainText, "Hallo daar")
        XCTAssertEqual(updated?.last?.direction, .outgoing)
    }

    func testPinReordersConversations() async throws {
        let service = MockMessagingService()
        let stream = await service.observeConversations()
        var iterator = stream.makeAsyncIterator()
        _ = await iterator.next()

        try await service.setPinned(true, chatID: ChatID("chat-lucas"))
        let updated = await iterator.next()
        XCTAssertEqual(updated?.first(where: { $0.id == ChatID("chat-lucas") })?.isPinned, true)
    }

    func testConnectionLabel() async {
        let service = MockMessagingService()
        let state = await service.connectionState
        guard case .connected(let label) = state else {
            return XCTFail("Expected connected mock state")
        }
        XCTAssertFalse(label.isEmpty)
    }
}
