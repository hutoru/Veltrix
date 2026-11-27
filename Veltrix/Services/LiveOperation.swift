import ActivityKit
import Foundation

@MainActor enum LiveOperation {
    static func start(_ command: Command, id: UUID, model: VeltrixModel) {
        guard #available(iOS 16.1, *), model.liveActivities, !model.onSet, !UITestMode.enabled,
              ActivityAuthorizationInfo().areActivitiesEnabled,
              !Activity<OperationAttributes>.activities.contains(where: { $0.attributes.operationID == id }) else { return }
        let item: (kind: OperationKind, asset: String, units: Decimal?, usd: Decimal?)
        switch command {
        case let .market(side, asset, units, _), let .limit(side, asset, units, _, _):
            item = (side == .buy ? .buy : .sell, asset, units, nil)
        case let .marketNotional(side, asset, usd, _):
            item = (side == .buy ? .buy : .sell, asset, nil, usd)
        case let .swap(asset, _, units, _): item = (.swap, asset, units, nil)
        case let .transfer(receive, asset, units, _): item = (receive ? .receive : .send, asset, units, nil)
        case let .payQR(requestID, _):
            guard let request = model.ledger.localPaymentRequests?[requestID] else { return }
            item = (.qrPayment, request.asset, request.units, nil)
        default: return
        }
        let hidden = model.hide || model.liveActivityPrivacy
        let ticker = Asset.ticker(item.asset)
        let quantity = hidden ? nil : item.units.map { model.units($0) + " " + ticker }
        let amount = hidden ? nil : item.usd.map { model.money($0) }
        let activity = OperationAttributes(operationID: id, title: item.kind.localized, ticker: ticker,
                                           quantity: quantity, amount: amount, symbol: item.kind.icon)
        _ = try? Activity.request(attributes: activity, contentState: .init(stage: .processing, status: L.text("Processing")), pushType: nil)
    }

    static func finish(_ id: UUID, saved: Bool, waiting: Bool = false, cancelled: Bool = false, discreet: Bool = false) {
        guard #available(iOS 16.1, *),
              let activity = Activity<OperationAttributes>.activities.first(where: { $0.attributes.operationID == id }) else { return }
        let status: OperationAttributes.ContentState
        if cancelled { status = .init(stage: .cancelled, status: L.text("Cancelled")) }
        else if waiting { status = .init(stage: .waiting, status: L.text("Open")) }
        else if saved { status = .init(stage: .saved, status: L.text("Operation saved")) }
        else { status = .init(stage: .failed, status: L.text("Operation failed")) }
        Task {
            if waiting { await activity.update(using: status) }
            else { await activity.end(using: status, dismissalPolicy: discreet ? .immediate : .after(Date().addingTimeInterval(12))) }
        }
    }

    static func clear() {
        guard #available(iOS 16.1, *) else { return }
        for activity in Activity<OperationAttributes>.activities {
            finish(activity.attributes.operationID, saved: false, cancelled: true, discreet: true)
        }
    }
}
