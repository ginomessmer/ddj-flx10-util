import Foundation

/// Request/response state machine for logo transfer and delete.
///
/// A faithful port of the state values held in the original tool's `Command` object, so that the
/// device sees exactly the same report sequence:
///
/// ```
/// transfer: send D0/01 → (1) D8 → (2) D8 → (5) stream D1 reports → (6) DC → (7) DC → success
/// delete:   send D0/00 → (3) D8 → (4) D8 → send D7 → (8) DE → (9) DE → success
/// ```
///
/// A NAK (DD/DF) at either acknowledgement step fails the operation once the final response
/// arrives; a response that arrives while reports are still streaming also marks the transfer as
/// failed. The original arms a single 10 s timer when the request is sent and never re-arms it.
public struct LogoTransferMachine: Equatable {
    public enum State: Int, Equatable {
        case idle = 0
        case transferRequested = 1
        case transferReady = 2
        case deleteRequested = 3
        case deleteReady = 4
        case sending = 5
        case sentAwaitingAck = 6
        case awaitingTransferResult = 7
        case deleteSent = 8
        case awaitingDeleteResult = 9

        public var isTransfer: Bool {
            [.transferRequested, .transferReady, .sending, .sentAwaitingAck, .awaitingTransferResult].contains(self)
        }

        public var isDelete: Bool {
            [.deleteRequested, .deleteReady, .deleteSent, .awaitingDeleteResult].contains(self)
        }
    }

    public enum Outcome: Equatable {
        case transferSucceeded
        case transferFailed
        case deleteSucceeded
        case deleteFailed
    }

    public enum Effect: Equatable {
        case sendReport([UInt8])
        /// Start streaming `LogoProtocol.dataReports`; report back with `dataPhaseFinished()`.
        case beginDataPhase
        case complete(Outcome)
    }

    public static let timeout: TimeInterval = 10

    public private(set) var state: State = .idle
    private var transferFailed = false
    private var deleteFailed = false

    public init() {}

    public var isBusy: Bool { state != .idle }

    public mutating func startTransfer(payloadLength: Int) -> [Effect] {
        guard state == .idle else { return [] }
        transferFailed = false
        state = .transferRequested
        return [.sendReport(LogoProtocol.transferRequest(payloadLength: payloadLength))]
    }

    public mutating func startDelete() -> [Effect] {
        guard state == .idle else { return [] }
        deleteFailed = false
        state = .deleteRequested
        return [.sendReport(LogoProtocol.deleteRequest())]
    }

    public mutating func receive(_ report: [UInt8]) -> [Effect] {
        guard report.count >= LogoProtocol.inputReportLength,
              let response = LogoProtocol.Response(rawValue: report[1]) else { return [] }
        return receive(response)
    }

    public mutating func receive(_ response: LogoProtocol.Response) -> [Effect] {
        switch (response, state) {
        case (.ready, .transferRequested):
            state = .transferReady
        case (.ready, .transferReady):
            state = .sending
            return [.beginDataPhase]
        case (.ready, .deleteRequested):
            state = .deleteReady
        case (.ready, .deleteReady):
            state = .deleteSent
            return [.sendReport(LogoProtocol.deleteExecute())]

        case (.transferAck, .sending), (.transferNak, .sending):
            if transferFailed { return finish(.transferFailed) }
            transferFailed = true
        case (.transferAck, .sentAwaitingAck):
            state = .awaitingTransferResult
        case (.transferNak, .sentAwaitingAck):
            transferFailed = true
            state = .awaitingTransferResult
        case (.transferAck, .awaitingTransferResult):
            return finish(transferFailed ? .transferFailed : .transferSucceeded)
        case (.transferNak, .awaitingTransferResult):
            return finish(.transferFailed)

        case (.deleteAck, .deleteSent):
            state = .awaitingDeleteResult
        case (.deleteNak, .deleteSent):
            deleteFailed = true
            state = .awaitingDeleteResult
        case (.deleteAck, .awaitingDeleteResult):
            return finish(deleteFailed ? .deleteFailed : .deleteSucceeded)
        case (.deleteNak, .awaitingDeleteResult):
            return finish(.deleteFailed)

        default:
            break
        }
        return []
    }

    /// Called once every data report has been handed to the device.
    public mutating func dataPhaseFinished() -> [Effect] {
        guard state == .sending else { return [] }
        state = transferFailed ? .awaitingTransferResult : .sentAwaitingAck
        return []
    }

    public mutating func timedOut() -> [Effect] {
        if state.isTransfer { return finish(.transferFailed) }
        if state.isDelete { return finish(.deleteFailed) }
        return []
    }

    /// The device disappeared mid-operation.
    public mutating func reset() {
        state = .idle
        transferFailed = false
        deleteFailed = false
    }

    private mutating func finish(_ outcome: Outcome) -> [Effect] {
        reset()
        return [.complete(outcome)]
    }
}
