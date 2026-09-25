import XCTest
import ClearskyCore
@testable import ClearskyApp

/// Exercises `ConnectCalendarViewModel` — the testable logic behind
/// `ConnectCalendarView`'s "Connect calendar" and "Skip" actions — with
/// `MockCalendarService`, never a real `EKEventStore`. See
/// `ConnectCalendarView.swift`'s type-level doc for why the view's actions live on
/// this separate `ObservableObject` rather than as `@State` + methods on the view
/// struct itself, and for why granting access applies `ConnectedAccountsTransition
/// .apply(.connectAccount(.calendar), to:)` rather than a parallel boolean.
@MainActor
final class ConnectCalendarViewModelTests: XCTestCase {

    // MARK: - Grant access

    func testGrantAccessCallsRequestAccessExactlyOnceAndAddsCalendarWhenGranted() async {
        let mock = MockCalendarService()
        mock.accessGranted = true
        var finishedStates: [ConnectedAccountsState] = []
        let viewModel = ConnectCalendarViewModel(calendarService: mock) { state in
            finishedStates.append(state)
        }

        await viewModel.grantAccess()

        XCTAssertEqual(mock.requestAccessCallCount, 1)
        XCTAssertEqual(viewModel.outcome, .granted)
        XCTAssertFalse(viewModel.isRequesting)
        XCTAssertTrue(viewModel.accountsState.connectedAccountKinds.contains(.calendar))
        XCTAssertEqual(finishedStates.count, 1)
        XCTAssertTrue(finishedStates[0].connectedAccountKinds.contains(.calendar))
    }

    func testGrantAccessRecordsDeniedAndDoesNotAddCalendarWhenTheServiceReturnsFalse() async {
        let mock = MockCalendarService()
        mock.accessGranted = false
        let viewModel = ConnectCalendarViewModel(calendarService: mock)

        await viewModel.grantAccess()

        XCTAssertEqual(mock.requestAccessCallCount, 1)
        XCTAssertEqual(viewModel.outcome, .denied)
        XCTAssertFalse(viewModel.accountsState.connectedAccountKinds.contains(.calendar))
    }

    func testGrantAccessCalledTwiceOnlyAsksTheServiceOnce() async {
        // Guards the "never ask again this session" requirement: a second
        // `grantAccess()` after the first has already resolved must not re-trigger
        // the OS prompt.
        let mock = MockCalendarService()
        let viewModel = ConnectCalendarViewModel(calendarService: mock)

        await viewModel.grantAccess()
        await viewModel.grantAccess()

        XCTAssertEqual(mock.requestAccessCallCount, 1)
    }

    func testGrantAccessBuildsOnAnExistingAccountsState() async {
        // The screen should apply its transition on top of whatever state the caller
        // handed in, not discard it — a caller further along in onboarding may already
        // have a non-empty ConnectedAccountsState.
        let mock = MockCalendarService()
        mock.accessGranted = true
        let startingState = ConnectedAccountsState(connectedAccountKinds: [], innerCircleCount: 3)
        let viewModel = ConnectCalendarViewModel(calendarService: mock, accountsState: startingState)

        await viewModel.grantAccess()

        XCTAssertEqual(viewModel.accountsState.innerCircleCount, 3)
        XCTAssertTrue(viewModel.accountsState.connectedAccountKinds.contains(.calendar))
    }

    // MARK: - Skip

    func testSkipDoesNotCallRequestAccess() {
        let mock = MockCalendarService()
        var finishedStates: [ConnectedAccountsState] = []
        let viewModel = ConnectCalendarViewModel(calendarService: mock) { state in
            finishedStates.append(state)
        }

        viewModel.skip()

        XCTAssertEqual(mock.requestAccessCallCount, 0)
        XCTAssertEqual(viewModel.outcome, .skipped)
        XCTAssertFalse(viewModel.accountsState.connectedAccountKinds.contains(.calendar))
        XCTAssertEqual(finishedStates.count, 1)
        XCTAssertFalse(finishedStates[0].connectedAccountKinds.contains(.calendar))
    }

    func testSkipAfterGrantAccessIsANoOp() async {
        let mock = MockCalendarService()
        let viewModel = ConnectCalendarViewModel(calendarService: mock)

        await viewModel.grantAccess()
        viewModel.skip()

        XCTAssertEqual(mock.requestAccessCallCount, 1)
        XCTAssertEqual(viewModel.outcome, .granted) // skip() no-ops once already resolved
    }

    func testGrantAccessAfterSkipIsANoOp() async {
        // Symmetric guard: once the person has skipped, a stray `grantAccess()` call
        // must not turn around and ask the OS either.
        let mock = MockCalendarService()
        let viewModel = ConnectCalendarViewModel(calendarService: mock)

        viewModel.skip()
        await viewModel.grantAccess()

        XCTAssertEqual(mock.requestAccessCallCount, 0)
        XCTAssertEqual(viewModel.outcome, .skipped)
    }
}
