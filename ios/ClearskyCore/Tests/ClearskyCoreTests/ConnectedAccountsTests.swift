import XCTest
@testable import ClearskyCore

final class ConnectedAccountsTests: XCTestCase {

    // MARK: - ConnectedAccountKind is the closed three-case vocabulary from the prototype

    func testConnectedAccountKindHasExactlyThreeCases() {
        let expected: Set<ConnectedAccountKind> = [.mail, .calendar, .messaging]
        XCTAssertEqual(ConnectedAccountKind.allCases.count, 3)
        XCTAssertEqual(Set(ConnectedAccountKind.allCases), expected)
    }

    // MARK: - Zero accounts connected -> demo day

    func testZeroAccountsAndZeroInnerCircleIsDemoDay() {
        let state = ConnectedAccountsState(connectedAccountKinds: [], innerCircleCount: 0)
        XCTAssertEqual(state.presentationState, .demoDay)
    }

    func testEmptyConstantIsDemoDay() {
        XCTAssertEqual(ConnectedAccountsState.empty.presentationState, .demoDay)
    }

    // MARK: - One account connected -> real-data (live) state

    func testOneConnectedAccountIsLiveEvenWithNoInnerCircle() {
        let state = ConnectedAccountsState(connectedAccountKinds: [.mail], innerCircleCount: 0)
        XCTAssertEqual(state.presentationState, .live)
    }

    func testInnerCircleAloneWithoutAnyConnectedAccountIsAlsoLive() {
        // Decision 5's empty state only fires when BOTH inner circle and connected
        // accounts are empty; either one alone already leaves demo day.
        let state = ConnectedAccountsState(connectedAccountKinds: [], innerCircleCount: 3)
        XCTAssertEqual(state.presentationState, .live)
    }

    func testEveryAccountKindConnectedAloneIsLive() {
        for kind in ConnectedAccountKind.allCases {
            let state = ConnectedAccountsState(connectedAccountKinds: [kind], innerCircleCount: 0)
            XCTAssertEqual(state.presentationState, .live, "\(kind) alone should be enough to leave demo day")
        }
    }

    // MARK: - The one-tap-connect action is a real, testable transition

    func testConnectAccountActionTransitionsDemoDayStateToLive() {
        let startingState = ConnectedAccountsState.empty
        XCTAssertEqual(startingState.presentationState, .demoDay)

        let afterConnect = ConnectedAccountsTransition.apply(
            .connectAccount(.mail),
            to: startingState
        )

        XCTAssertEqual(afterConnect.presentationState, .live)
        XCTAssertTrue(afterConnect.connectedAccountKinds.contains(.mail))
    }

    func testConnectAccountIsIdempotentForTheSameKind() {
        let startingState = ConnectedAccountsState.empty
        let onceConnected = ConnectedAccountsTransition.apply(.connectAccount(.calendar), to: startingState)
        let twiceConnected = ConnectedAccountsTransition.apply(.connectAccount(.calendar), to: onceConnected)

        XCTAssertEqual(onceConnected, twiceConnected)
        XCTAssertEqual(twiceConnected.connectedAccountKinds, [.calendar])
    }

    func testConnectAccountPreservesInnerCircleCount() {
        let startingState = ConnectedAccountsState(connectedAccountKinds: [], innerCircleCount: 2)
        let afterConnect = ConnectedAccountsTransition.apply(.connectAccount(.messaging), to: startingState)

        XCTAssertEqual(afterConnect.innerCircleCount, 2)
    }

    // MARK: - Disconnecting the only account returns to demo day (the audit doc's
    // "No connected accounts" failure/recovery case, §"Manual QA script" item 10)

    func testDisconnectingTheOnlyAccountWithNoInnerCircleReturnsToDemoDay() {
        let liveState = ConnectedAccountsState(connectedAccountKinds: [.mail], innerCircleCount: 0)
        XCTAssertEqual(liveState.presentationState, .live)

        let afterDisconnect = ConnectedAccountsTransition.apply(.disconnectAccount(.mail), to: liveState)

        XCTAssertEqual(afterDisconnect.presentationState, .demoDay)
        XCTAssertTrue(afterDisconnect.connectedAccountKinds.isEmpty)
    }

    func testDisconnectingOneOfSeveralAccountsStaysLive() {
        let liveState = ConnectedAccountsState(connectedAccountKinds: [.mail, .calendar], innerCircleCount: 0)
        let afterDisconnect = ConnectedAccountsTransition.apply(.disconnectAccount(.mail), to: liveState)

        XCTAssertEqual(afterDisconnect.presentationState, .live)
        XCTAssertEqual(afterDisconnect.connectedAccountKinds, [.calendar])
    }

    func testDisconnectingAnAccountThatWasNeverConnectedIsANoOp() {
        let state = ConnectedAccountsState(connectedAccountKinds: [.mail], innerCircleCount: 0)
        let result = ConnectedAccountsTransition.apply(.disconnectAccount(.calendar), to: state)

        XCTAssertEqual(result, state)
    }

    // MARK: - Codable round-trip

    func testConnectedAccountsStateRoundTripsThroughCodable() throws {
        let state = ConnectedAccountsState(connectedAccountKinds: [.mail, .messaging], innerCircleCount: 5)

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(ConnectedAccountsState.self, from: data)

        XCTAssertEqual(decoded, state)
    }
}
