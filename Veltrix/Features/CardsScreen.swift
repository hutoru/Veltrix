import SwiftUI
import CoreMotion

struct CardsScreen: View {
    @EnvironmentObject private var model: VeltrixModel
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var motion = CardMotion()
    @State private var selected: UUID?
    @State private var flipped = false
    @State private var editor: CardIntent?
    @State private var delete = false

    private var card: VirtualCard? { model.cards.first { $0.id == selected } ?? model.cards.first }

    var body: some View {
        PageScroll {
            PageHeader(title: "Cards", detail: "Virtual balances and simulated spending") {
                IconButton(icon: "plus", label: "New virtual card") { editor = CardIntent(.create) }
                    .accessibilityIdentifier("card.new")
            }
            if let card {
                cardDeck(card)
                actions(card)
                spending(card)
            } else {
                SimBadge()
                EmptyPanel(icon: "creditcard", title: "Start your card collection",
                           detail: "Choose Classic, Gold, Platinum or Black and simulate spending from a separate balance.")
                Button("Create virtual card") { editor = CardIntent(.create) }
                    .buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("card.create")
            }
        }
        .onAppear { configureMotion() }
        .onDisappear { motion.stop() }
        .onChange(of: phase) { _ in configureMotion() }
        .onChange(of: reduceMotion) { _ in configureMotion() }
        .onChange(of: model.cards.map(\.id)) { ids in
            if let selected, !ids.contains(selected) { self.selected = ids.last }
            configureMotion()
        }
        .sheet(item: $editor, onDismiss: configureMotion) { CardForm(intent: $0).onAppear { motion.stop() } }
        .confirmationDialog("Delete virtual card?", isPresented: $delete, titleVisibility: .visible) {
            if let card {
                Button("Delete card", role: .destructive) { _ = model.execute(.deleteCard(card.id)) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Return any remaining funds to your portfolio first. Activity is retained.")
        }
    }

    private func configureMotion() {
        if card != nil && phase == .active && !reduceMotion && editor == nil { motion.start() }
        else { motion.stop() }
    }

    private func cardDeck(_ card: VirtualCard) -> some View {
        VStack(spacing: 14) {
            ZStack {
                if model.cards.count > 2 {
                    RoundedRectangle(cornerRadius: 21).fill(Color.vxSurface)
                        .padding(.horizontal, 22).offset(y: -17)
                }
                if model.cards.count > 1 {
                    RoundedRectangle(cornerRadius: 21).fill(Color.vxAccent.opacity(0.35))
                        .padding(.horizontal, 11).offset(y: -9)
                }
                Button {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.49, dampingFraction: 0.81)) { flipped.toggle() }
                    Feedback.tap()
                } label: {
                    MotionCardFace(motion: motion, card: card, balance: model.money(card.balance), flipped: flipped)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Flip \(card.name) card"))
                .accessibilityValue(Text(verbatim: model.money(card.balance)))
                .accessibilityIdentifier("card.face")
                .simultaneousGesture(DragGesture(minimumDistance: 30).onEnded { gesture in
                    guard abs(gesture.translation.width) > abs(gesture.translation.height),
                          let current = model.cards.firstIndex(where: { $0.id == card.id }) else { return }
                    let offset = gesture.translation.width < 0 ? 1 : -1
                    let count = model.cards.count
                    guard count > 1 else { return }
                    select(model.cards[(current + offset + count) % count].id)
                })
            }
            .padding(.top, model.cards.count > 1 ? 17 : 0)
            if model.cards.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(model.cards) { item in
                            Button {
                                select(item.id)
                            } label: {
                                Text(verbatim: item.name).lineLimit(1)
                                    .padding(.horizontal, 12).padding(.vertical, 8)
                                    .background(item.id == card.id ? Color.vxAccent.opacity(0.18) : Color.vxSurface, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(item.id == card.id ? .isSelected : [])
                        }
                    }
                }
                .font(.caption.weight(.semibold))
            }
        }
    }

    private func select(_ id: UUID) {
        withAnimation(reduceMotion ? nil : .spring(response: 0.33, dampingFraction: 0.86)) {
            selected = id
            flipped = false
        }
        Feedback.tap()
    }

    private func actions(_ card: VirtualCard) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button("Top up") { editor = CardIntent(.topUp(card.id)) }.buttonStyle(PrimaryButtonStyle())
                Button("Pay") { editor = CardIntent(.pay(card.id)) }.buttonStyle(PrimaryButtonStyle())
            }
            HStack(spacing: 11) {
                Button {
                    _ = model.execute(.freezeCard(card.id))
                } label: {
                    Label(card.frozen ? "Unfreeze" : "Freeze", systemImage: card.frozen ? "sun.max" : "snowflake")
                }
                Button {
                    editor = CardIntent(.returnFunds(card.id))
                } label: { Label("Return funds", systemImage: "arrow.uturn.left") }
                Spacer(minLength: 0)
                Menu {
                    Button("Edit card") { editor = CardIntent(.edit(card.id)) }
                    Button("Delete card", role: .destructive) { delete = true }
                } label: {
                    Image(systemName: "ellipsis.circle").font(.title3).frame(width: 36, height: 36)
                }
                .accessibilityLabel(Text("Card options"))
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.bordered)
            LabeledContent("Per-payment limit", value: card.limit.map { model.money($0) } ?? L.text("No limit"))
                .font(.footnote)
        }
    }

    private func spending(_ card: VirtualCard) -> some View {
        let entries = model.portfolio.entries.filter { $0.cardID == card.id }
        let paid = entries.filter { $0.kind == .cardPayment }
        let refunds = entries.filter { $0.kind == .refund }
        let total = try? MoneyMath.subtract(paid.map(\.amount).reduce(Decimal.zero, MoneyMath.add),
                                            refunds.map(\.amount).reduce(Decimal.zero, MoneyMath.add))
        return VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text("Card activity").font(.title3.weight(.semibold))
                Spacer()
                Text(verbatim: model.money(total)).font(.headline.monospacedDigit())
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            Text("Net simulated spending").font(.caption).foregroundStyle(Color.vxMuted)
            if entries.isEmpty {
                Text("Card operations will appear here.").font(.footnote).foregroundStyle(Color.vxMuted)
            } else {
                ForEach(entries.reversed()) { entry in
                    NavigationLink {
                        EntryScreen(entry: entry)
                    } label: {
                        EntryRow(entry: entry)
                    }
                    .buttonStyle(.plain)
                    if entry.id != entries.first?.id { Divider() }
                }
            }
        }
        .panel()
    }
}

private struct MotionCardFace: View {
    @ObservedObject var motion: CardMotion
    let card: VirtualCard
    let balance: String
    let flipped: Bool

    var body: some View {
        CardFace(tier: card.tier, name: card.name, balance: balance, frozen: card.frozen,
                 flip: flipped ? 180 : 0, tilt: motion.tilt)
    }
}

private struct CardFace: View, Animatable {
    let tier: CardTier
    let name: String
    let balance: String
    let frozen: Bool
    var flip: Double
    var tilt: CGSize

    var animatableData: Double {
        get { flip }
        set { flip = newValue }
    }

    var body: some View {
        let rotated = flip >= 90
        let colors = tier.colors
        return ZStack {
            RoundedRectangle(cornerRadius: 21)
                .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            Canvas { context, size in
                for index in 0..<Int(size.height) {
                    let y = CGFloat(index)
                    let alpha = Double((index * 31) % 13) / 270
                    var line = Path()
                    line.move(to: CGPoint(x: 0, y: y))
                    line.addLine(to: CGPoint(x: size.width, y: y))
                    context.stroke(line, with: .color(.white.opacity(alpha)), lineWidth: 0.35)
                }
            }
            OrbitLines(opacity: 0.35)
            GeometryReader { geometry in
                let x = 0.63 + tilt.width * 0.22
                let y = 0.35 + tilt.height * 0.25
                AngularGradient(colors: [.clear, .cyan.opacity(0.19), .white.opacity(0.36), .purple.opacity(0.30), .clear],
                                center: UnitPoint(x: x, y: y), angle: .degrees(geometry.size.width / 5))
                    .blendMode(.screen)
                    .opacity(tier == .classic ? 0.4 : 0.65)
            }
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    VeltrixMark().fill(.white).frame(width: 23, height: 23)
                    Text(verbatim: "VELTRIX").font(.system(.subheadline, design: .rounded).weight(.heavy)).tracking(2)
                    Spacer()
                    if frozen { Image(systemName: "snowflake").accessibilityLabel(Text("Frozen")) }
                }
                Spacer()
                if rotated {
                    Text("Virtual funds").font(.headline)
                    Text("Simulated card. No payment credentials.").font(.caption).opacity(0.78)
                } else {
                    Text(verbatim: balance).font(.system(size: 27, weight: .semibold, design: .rounded)).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.38)
                    Text(verbatim: name).font(.caption.weight(.medium)).lineLimit(1).opacity(0.80)
                }
                HStack {
                    Text(tier.title).font(.caption.weight(.bold)).textCase(.uppercase).tracking(1.5)
                    Spacer()
                    SimBadge(inverted: true)
                }
            }
            .foregroundStyle(.white)
            .padding(17)
            .rotation3DEffect(.degrees(rotated ? 180 : 0), axis: (x: 0, y: 1, z: 0))
        }
        .aspectRatio(1.68, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 21))
        .overlay(RoundedRectangle(cornerRadius: 21).strokeBorder(.white.opacity(0.24), lineWidth: 1))
        .rotation3DEffect(.degrees(flip + Double(tilt.width) * 4), axis: (x: 0, y: 1, z: 0), perspective: 0.55)
        .rotation3DEffect(.degrees(Double(tilt.height) * -4), axis: (x: 1, y: 0, z: 0))
    }
}

@MainActor private final class CardMotion: ObservableObject {
    @Published private(set) var tilt: CGSize = .zero
    private let manager = CMMotionManager()

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1 / 30
        manager.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let data else { return }
            let roll = max(-1, min(1, data.attitude.roll))
            let pitch = max(-1, min(1, data.attitude.pitch))
            Task { @MainActor in
                guard let self, self.manager.isDeviceMotionActive else { return }
                self.tilt = CGSize(width: self.tilt.width * 0.8 + roll * 0.2, height: self.tilt.height * 0.8 + pitch * 0.2)
            }
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        if tilt != .zero { tilt = .zero }
    }
}

extension CardTier {
    var title: LocalizedStringKey {
        switch self {
        case .classic: return "Classic"
        case .gold: return "Gold"
        case .platinum: return "Platinum"
        case .black: return "Black"
        }
    }

    var colors: [Color] {
        switch self {
        case .classic: return [.init(red: 0.11, green: 0.09, blue: 0.24), .init(red: 0.24, green: 0.17, blue: 0.53), .black]
        case .gold: return [.init(red: 0.33, green: 0.20, blue: 0.08), .init(red: 0.45, green: 0.29, blue: 0.11), .black]
        case .platinum: return [.init(red: 0.29, green: 0.34, blue: 0.44), .init(red: 0.23, green: 0.27, blue: 0.39), .black]
        case .black: return [.black, .init(red: 0.23, green: 0.22, blue: 0.27), .black]
        }
    }
}

private struct CardIntent: Identifiable {
    enum Mode { case create, edit(UUID), topUp(UUID), returnFunds(UUID), pay(UUID) }
    let id = UUID()
    let mode: Mode

    init(_ mode: Mode) { self.mode = mode }

    var title: LocalizedStringKey {
        switch mode {
        case .create: return "New virtual card"
        case .edit: return "Edit card"
        case .topUp: return "Top up"
        case .returnFunds: return "Return funds"
        case .pay: return "Simulated payment"
        }
    }

    var cardID: UUID? {
        switch mode {
        case .create: return nil
        case let .edit(id), let .topUp(id), let .returnFunds(id), let .pay(id): return id
        }
    }
}

private struct CardForm: View {
    let intent: CardIntent
    @EnvironmentObject private var model: VeltrixModel
    @Environment(\.dismiss) private var dismiss
    @State private var tier = CardTier.classic
    @State private var name = ""
    @State private var limit = ""
    @State private var amount = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                SimBadge()
                Section {
                    switch intent.mode {
                    case .create, .edit:
                        if case .create = intent.mode {
                            Picker("Card tier", selection: $tier) {
                                ForEach(CardTier.allCases, id: \.self) { Text($0.title).tag($0) }
                            }
                        }
                        TextField("Card name", text: $name)
                        TextField("Per-payment limit (USD)", text: $limit).keyboardType(.decimalPad)
                        Text("Leave the limit blank for unrestricted simulated payments.")
                            .font(.footnote).foregroundStyle(Color.vxMuted)
                    case .topUp, .returnFunds, .pay:
                        if case .pay = intent.mode { TextField("Merchant", text: $name) }
                        TextField("Amount (USD)", text: $amount).keyboardType(.decimalPad)
                    }
                }
                if let error { Text(verbatim: error).font(.footnote).foregroundStyle(Color.vxDown) }
                Button("Confirm simulation") { save() }
                    .buttonStyle(PrimaryButtonStyle()).listRowBackground(Color.clear)
                    .accessibilityIdentifier("card.confirm")
            }
            .scrollContentBackground(.hidden).background(Color.vxBackground)
            .navigationTitle(intent.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        .onAppear {
            guard case .edit = intent.mode,
                  let card = model.cards.first(where: { $0.id == intent.cardID }) else { return }
            name = card.name
            limit = card.limit.map(Display.input) ?? ""
        }
    }

    private func save() {
        do {
            let command = try makeCommand()
            if model.execute(command, id: intent.id) { dismiss() }
            else { error = model.error; model.error = nil }
        } catch {
            self.error = Display.error(error)
        }
    }

    private func makeCommand() throws -> Command {
        switch intent.mode {
        case .create, .edit:
            let text = limit.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = text.isEmpty ? nil : Display.amount(text)
            if !text.isEmpty && value == nil { throw SimulationError.invalidAmount }
            if let id = intent.cardID { return .configureCard(id, name, value) }
            let title = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "VELTRIX " + L.text(tier.rawValue.capitalized) : name
            return .createCard(tier, title, value)
        case let .topUp(id), let .returnFunds(id):
            guard let value = Display.amount(amount) else { throw SimulationError.invalidAmount }
            let toCard: Bool
            if case .topUp = intent.mode { toCard = true } else { toCard = false }
            return .moveCardFunds(id, value, toCard: toCard)
        case let .pay(id):
            guard let value = Display.amount(amount) else { throw SimulationError.invalidAmount }
            return .pay(id, value, name)
        }
    }
}
