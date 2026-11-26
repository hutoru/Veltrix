import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

struct ReceiveRequestScreen: View {
    @EnvironmentObject private var model: VeltrixModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var asset: String
    @State private var network: TransferNetwork?
    @State private var amount = ""
    @State private var request: LocalPaymentRequest?
    @State private var image: UIImage?
    @State private var error: String?
    @State private var copied = false
    @State private var manualReceipt = false

    private static let context = CIContext()

    init(initialAsset: String) {
        let selected = TransferNetwork.available(for: initialAsset).isEmpty ? "bitcoin" : initialAsset
        _asset = State(initialValue: selected)
        _network = State(initialValue: TransferNetwork.available(for: selected).first)
    }

    var body: some View {
        NavigationStack {
            PageScroll {
                if let request, let image {
                    details(request, image: image)
                } else {
                    Picker("Asset", selection: $asset) {
                        ForEach(Asset.catalog.filter { !TransferNetwork.available(for: $0.id).isEmpty }) { coin in
                            Text(verbatim: coin.name).tag(coin.id)
                        }
                    }
                    Picker("Network", selection: $network) {
                        ForEach(TransferNetwork.available(for: asset), id: \.self) { item in
                            Text(verbatim: item.rawValue).tag(Optional(item))
                        }
                    }
                    TextField("Amount", text: $amount)
                        .keyboardType(.decimalPad)
                        .font(.system(size: 48, weight: .semibold).monospacedDigit())
                        .accessibilityIdentifier("receive.amount")
                }
                if let error { Text(verbatim: error).font(.footnote).foregroundStyle(Color.vxDown) }
            }
            .scrollDismissesKeyboard(.interactively)
            .dismissibleKeyboard()
            .navigationTitle("Receive")
            .fullScreenCover(isPresented: $manualReceipt) {
                TradeEditor(intent: TradeIntent(action: .receive, asset: asset))
            }
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: asset) { network = TransferNetwork.available(for: $0).first }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        if image != nil {
                            Button("Edit") { image = nil; copied = false }
                        }
                        Button("Record local receipt") { manualReceipt = true }
                    } label: {
                        Image(systemName: "ellipsis.circle").accessibilityLabel(Text("More"))
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button(image == nil ? "Create QR request" : "Refresh QR request") { generate() }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("receive.generate")
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Color.vxBackground)
            }
        }
    }

    private func details(_ request: LocalPaymentRequest, image: UIImage) -> some View {
        VStack(spacing: 14) {
            if let coin = Asset.catalog.first(where: { $0.id == request.asset }) {
                CoinIcon(asset: coin, url: model.quotes[coin.id]?.image, size: 50)
            }
            Text(verbatim: request.network.rawValue).font(.subheadline)
            Text(verbatim: "\(Display.input(request.units)) \(Asset.ticker(request.asset))")
                .font(.title2.monospacedDigit()).lineLimit(1).minimumScaleFactor(0.5)
            Image(uiImage: image)
                .interpolation(.none).resizable().scaledToFit()
                .frame(width: 208, height: 208).padding(18)
                .background(.white, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel(Text("Test QR code"))
                .accessibilityIdentifier("receive.qr")
            Text(verbatim: request.payload)
                .font(.caption.monospaced()).multilineTextAlignment(.center).textSelection(.enabled)
            Button(copied ? "Copied" : "Copy") {
                UIPasteboard.general.string = request.payload
                copied = true
                Feedback.success()
            }.buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .transition(.opacity)
    }

    private func generate() {
        guard let network, let units = Display.amount(amount) else {
            error = L.text("Enter a valid amount.")
            return
        }
        let next = LocalPaymentRequest(id: UUID(), recipient: model.portfolio.id, asset: asset, network: network, units: units)
        guard next.isValid else { error = L.text("Enter a valid amount."); return }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(next.payload.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage,
              let cgImage = Self.context.createCGImage(output, from: output.extent) else {
            error = L.text("Could not create the QR code.")
            return
        }
        guard model.execute(.registerQR(next, replacing: request?.id), showFeedback: false) else {
            error = model.error
            model.error = nil
            return
        }
        Keyboard.dismiss()
        error = nil
        copied = false
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
            request = next
            image = UIImage(cgImage: cgImage)
        }
        Feedback.success()
    }
}
