import SwiftUI

struct LocalQRPaymentScreen: View {
    @Environment(\.veltrixTheme) private var theme
    @EnvironmentObject private var model: VeltrixModel
    @Environment(\.dismiss) private var dismiss
    @State private var payFrom: UUID?
    @State private var saved = false
    @State private var error: String?

    let requestID: UUID

    private var request: LocalPaymentRequest? { model.ledger.localPaymentRequests?[requestID] }

    var body: some View {
        NavigationStack {
            PageScroll {
                if saved {
                    Label("Operation saved", systemImage: "checkmark.circle.fill")
                        .font(.title2.weight(.semibold)).foregroundStyle(theme.positive)
                        .accessibilityIdentifier("scanner.paymentSaved")
                } else if let request, let receiver = model.ledger.portfolios.first(where: { $0.id == request.recipient }) {
                    payment(request, receiver: receiver)
                } else {
                    Text(model.ledger.operationIDs.contains(requestID) ? "This request was already paid." : "This request is unavailable on this device.")
                }
                if let error { Text(verbatim: error).font(.footnote).foregroundStyle(theme.negative) }
            }
            .navigationTitle("QR payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(saved ? "Done" : "Close") { dismiss() } } }
        }
    }

    private func payment(_ request: LocalPaymentRequest, receiver: Portfolio) -> some View {
        let candidates = model.ledger.portfolios.filter { $0.id != receiver.id }
        let payer = candidates.first { $0.id == payFrom } ?? candidates.first { $0.id == model.ledger.selected } ?? candidates.first
        return VStack(alignment: .leading, spacing: 14) {
            Text(verbatim: "\(Display.input(request.units)) \(Asset.ticker(request.asset))")
                .font(.largeTitle.monospacedDigit()).lineLimit(1).minimumScaleFactor(0.5)
            LabeledContent("Recipient portfolio", value: receiver.name)
            LabeledContent("Network", value: request.network.rawValue)
            if let payer {
                Picker("Pay from portfolio", selection: Binding(get: { payer.id }, set: { payFrom = $0 })) {
                    ForEach(candidates) { item in Text(verbatim: item.name).tag(item.id) }
                }
                LabeledContent("Available balance", value: (try? payer.freeUnits(request.asset)).map { model.units($0) } ?? "-")
                Button("Confirm payment") {
                    if model.execute(.payQR(request.id, from: payer.id), showFeedback: false) {
                        saved = true
                        Feedback.success()
                    } else {
                        error = model.error
                        model.error = nil
                    }
                }.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("scanner.confirmPayment")
            } else {
                Text("Create a second portfolio to pay this request.")
            }
        }
    }
}
