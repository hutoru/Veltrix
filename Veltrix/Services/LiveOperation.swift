
import ActivityKit
import Foundation
import OSLog
import UIKit

@MainActor enum LiveOperation {
    private static let logger = Logger(subsystem: "app.veltrix.simulation", category: "LiveActivity")
    private static var receipts: [UUID: Task<Void, Never>] = [:]
    private static let receiptSeconds: TimeInterval = 10

    static var unavailableReason: String? {
        guard #available(iOS 16.1, *) else { return L.text("Live Activities require iOS 16.1 or later.") }
        guard let plugins = Bundle.main.builtInPlugInsURL,
              FileManager.default.fileExists(atPath: plugins.appendingPathComponent("VeltrixWidgets.appex/Info.plist").path) else {
            return L.text("The VELTRIX extension is missing from this installation.")
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            return L.text("Live Activities are unavailable in iOS settings.")
        }
        return nil
    }

    static func start(_ command: Command, id: UUID, model: VeltrixModel) {
        guard model.liveActivities, !UITestMode.enabled || UITestMode.fixture("--native-live-activity") else { return }
        let item: (kind: OperationKind, asset: String, units: Decimal?, usd: Decimal?)
        switch command {
        case let .market(side, asset, units, _), let .limit(side, asset, units, _, _):
            item = (side == .buy ? .buy : .sell, asset, units, nil)
        case let .marketNotional(side, asset, usd, _):
            item = (side == .buy ? .buy : .sell, asset, nil, usd)
        case let .deposit(usd): item = (.deposit, "USD", nil, usd)
        case let .swap(asset, _, units, _): item = (.swap, asset, units, nil)
        case let .transfer(receive, asset, units, _): item = (receive ? .receive : .send, asset, units, nil)
        case let .payQR(requestID, _):
            guard let request = model.ledger.localPaymentRequests?[requestID] else { return }
            item = (.qrPayment, request.asset, request.units, nil)
        default: return
        }
        request(id: id, kind: item.kind, asset: item.asset, units: item.units, usd: item.usd, saved: false, model: model)
    }

    static func showLastOperation(_ model: VeltrixModel) {
        guard let entry = model.portfolio.entries.last(where: {
            [.buy, .sell, .swap, .send, .receive, .deposit, .qrPayment].contains($0.kind)
        }) else {
            model.liveActivityResult = L.text("There is no saved operation to show.")
            return
        }
        request(id: entry.id, kind: entry.kind, asset: entry.asset, units: entry.asset == "USD" ? nil : entry.amount,
                usd: entry.settlementUSD, saved: true, model: model)
    }

    @available(iOS 16.1, *)
    private static func content(_ stage: OperationAttributes.ContentState.Stage) -> OperationAttributes.ContentState {
        switch stage {
        case .processing: return .init(stage: stage, status: L.text("Processing"))
        case .waiting: return .init(stage: stage, status: L.text("Open"))
        case .saved: return .init(stage: stage, status: L.text("Operation saved"))
        case .failed: return .init(stage: stage, status: L.text("Operation failed"))
        case .cancelled: return .init(stage: stage, status: L.text("Cancelled"))
        }
    }

    private static func request(id: UUID, kind: OperationKind, asset: String, units: Decimal?, usd: Decimal?,
                                saved: Bool, model: VeltrixModel) {
        if let reason = unavailableReason { model.liveActivityResult = reason; return }
        guard #available(iOS 16.1, *) else { return }
        if let activity = Activity<OperationAttributes>.activities.first(where: { $0.attributes.operationID == id }) {
            model.liveActivityResult = L.text("Live Activity accepted by iOS.")
            if saved { displayReceipt(activity, state: content(.saved)) }
            return
        }
        let hidden = model.hide || model.liveActivityPrivacy
        let ticker = Asset.ticker(asset)
        let quantity = hidden ? nil : units.map { model.units($0) + " " + ticker }
        let amount = hidden ? nil : usd.map { model.money($0) }
        let attributes = OperationAttributes(operationID: id, title: kind.localized, ticker: ticker,
                                             quantity: quantity, amount: amount, symbol: kind.icon)
        let state = content(saved ? .saved : .processing)
        do {
            let activity = try Activity.request(attributes: attributes, contentState: state, pushType: nil)
            model.liveActivityResult = L.text("Live Activity accepted by iOS.")
            if saved { displayReceipt(activity, state: state) }
        } catch {
            let issue = error as NSError
            logger.error("ActivityKit request failed: \(issue.domain, privacy: .public) (\(issue.code))")
            model.liveActivityResult = L.format("iOS declined the Live Activity (%@).", String(issue.code))
        }
    }

    static func finish(_ id: UUID, saved: Bool, waiting: Bool = false, cancelled: Bool = false) {
        guard #available(iOS 16.1, *),
              let activity = Activity<OperationAttributes>.activities.first(where: { $0.attributes.operationID == id }) else { return }
        let state = content(cancelled ? .cancelled : (waiting ? .waiting : (saved ? .saved : .failed)))
        if waiting {
            Task { await activity.update(using: state) }
        } else {
            displayReceipt(activity, state: state)
        }
    }

    @available(iOS 16.1, *)
    private static func displayReceipt(_ activity: Activity<OperationAttributes>, state: OperationAttributes.ContentState) {
        let id = activity.attributes.operationID
        receipts[id]?.cancel()
        let deadline = Date().addingTimeInterval(receiptSeconds)
        let background = UIApplication.shared.beginBackgroundTask(withName: "VELTRIX receipt") {
            Task { @MainActor in
                await activity.end(using: state, dismissalPolicy: .immediate)
            }
        }
        receipts[id] = Task {
            defer { if background != .invalid { UIApplication.shared.endBackgroundTask(background) } }
            if #available(iOS 16.2, *) {
                await activity.update(ActivityContent(state: state, staleDate: deadline, relevanceScore: 1))
            } else {
                await activity.update(using: state)
            }
            do { try await Task.sleep(nanoseconds: UInt64(receiptSeconds * 1_000_000_000)) }
            catch { return }
            receipts.removeValue(forKey: id)
            await activity.end(using: state, dismissalPolicy: .immediate)
        }
    }

    static func clearExpiredReceipts() {
        guard #available(iOS 16.1, *) else { return }
        for activity in Activity<OperationAttributes>.activities where receipts[activity.attributes.operationID] == nil {
            if [.saved, .failed, .cancelled].contains(activity.contentState.stage) {
                Task { await activity.end(using: nil, dismissalPolicy: .immediate) }
            }
        }
    }

    static func clear() {
        guard #available(iOS 16.1, *) else { return }
        for task in receipts.values { task.cancel() }
        receipts.removeAll()
        for activity in Activity<OperationAttributes>.activities {
            Task { await activity.end(using: nil, dismissalPolicy: .immediate) }
        }
    }
}
