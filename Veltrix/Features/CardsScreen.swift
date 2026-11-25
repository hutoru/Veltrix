import SwiftUI
import CoreMotion
import PhotosUI
import UIKit

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
            PageHeader(title: "Cards", detail: "Card collection") {
                IconButton(icon: "plus", label: "New card") { editor = CardIntent(.create) }
                    .accessibilityIdentifier("card.new")
            }
            if let card {
                cardDeck(card)
                actions(card)
                spending(card)
            } else {
                EmptyPanel(icon: "creditcard", title: "Start your card collection",
                           detail: "Choose a finish and personalize your first card.")
                Button("Create card") { editor = CardIntent(.create) }
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
        .navigationTitle("Cards")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editor, onDismiss: configureMotion) { intent in
            CardForm(intent: intent, onCreate: select).onAppear { motion.stop() }
        }
        .confirmationDialog("Delete card?", isPresented: $delete, titleVisibility: .visible) {
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
                        .id(card.id)
                        .transition(reduceMotion ? .identity : .opacity.combined(with: .scale(scale: 0.96)))
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
            Text("Net spending").font(.caption).foregroundStyle(Color.vxMuted)
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
        CardFace(tier: card.tier, design: card.design ?? card.tier.defaultDesign, name: card.name, balance: balance, frozen: card.frozen,
                 flip: flipped ? 180 : 0, tilt: motion.tilt)
    }
}

private struct CardFace: View, Animatable {
    let tier: CardTier
    let design: CardDesign
    let name: String
    let balance: String
    let frozen: Bool
    var flip: Double
    var tilt: CGSize
    var moveMark: ((Double, Double) -> Void)?

    var animatableData: Double {
        get { flip }
        set { flip = newValue }
    }

    var body: some View {
        let rotated = flip >= 90
        let (_, _, light, dark) = tier.finish
        let ink: Color = tier == .ceramicWhite && design.tint == nil && design.portrait == nil ? .black : .white
        let typeface: Font.Design = design.typeface == .classic ? .serif : (design.typeface == .mono ? .monospaced : .default)
        return ZStack {
            RoundedRectangle(cornerRadius: 21)
                .fill(LinearGradient(colors: [.init(cardRGB: design.tint ?? light), .init(cardRGB: design.shade ?? dark)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            if let portrait = design.portrait {
                CardPortrait(bytes: portrait).equatable()
                LinearGradient(colors: [.black.opacity(0.34), .black.opacity(0.76)], startPoint: .top, endPoint: .bottom)
            }
            CardGrain(texture: design.texture, collection: tier.collection)
            let center = UnitPoint(x: 0.62 + tilt.width * 0.24, y: 0.38 + tilt.height * 0.22)
            switch design.material {
            case .holographic:
                AngularGradient(colors: [.cyan, .purple, .pink, .mint, .cyan], center: center,
                                angle: .degrees(18 + Double(tilt.width) * 30))
                    .blendMode(.screen).opacity(design.sheen * 0.62)
            case .glass:
                RadialGradient(colors: [.white.opacity(0.9), .cyan.opacity(0.17), .clear], center: center,
                               startRadius: 0, endRadius: 165)
                    .blendMode(.screen).opacity(design.sheen * 0.7)
            default:
                LinearGradient(colors: [.clear, .white.opacity(0.65), .clear],
                               startPoint: UnitPoint(x: center.x - 0.26, y: 0),
                               endPoint: UnitPoint(x: center.x + 0.52, y: 1))
                    .blendMode(.screen).opacity(design.sheen * (design.material == .carbon ? 0.21 : 0.43))
            }
            if !rotated {
                GeometryReader { geometry in
                    let point = CGPoint(x: geometry.size.width * CGFloat(design.markX),
                                        y: geometry.size.height * CGFloat(design.markY))
                    if let moveMark {
                        VeltrixMark().fill(ink.opacity(0.64)).frame(width: 38, height: 38)
                            .padding(6).contentShape(Rectangle())
                            .gesture(DragGesture(coordinateSpace: .named("card.preview")).onChanged { value in
                                moveMark(Double(value.location.x / max(1, geometry.size.width)),
                                         Double(value.location.y / max(1, geometry.size.height)))
                            })
                            .position(point)
                    } else {
                        VeltrixMark().fill(ink.opacity(0.56)).frame(width: 38, height: 38)
                            .shadow(color: .black.opacity(0.28), radius: 0, x: 0, y: 1).position(point)
                    }
                }.coordinateSpace(name: "card.preview").accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text(verbatim: "VELTRIX")
                        .font(.system(.subheadline, design: typeface).weight(.bold)).tracking(3)
                    Spacer()
                    if frozen { Image(systemName: "snowflake").accessibilityLabel(Text("Frozen")) }
                }
                Spacer()
                if rotated {
                    Text("Veltrix card").font(.headline)
                    Text("No payment credentials").font(.caption).opacity(0.78)
                } else {
                    Text(verbatim: balance).font(.system(size: 29, weight: .semibold, design: typeface)).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.38)
                    Text(verbatim: name).font(.system(.caption, design: typeface).weight(.medium)).lineLimit(1).opacity(0.80)
                }
                HStack {
                    Text(tier.title).font(.caption.weight(.bold)).textCase(.uppercase).tracking(1.5)
                    Spacer()
                }
            }
            .foregroundStyle(ink)
            .padding(17)
            .allowsHitTesting(false)
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

private struct CardIntent: Identifiable {
    enum Mode { case create, edit(UUID), topUp(UUID), returnFunds(UUID), pay(UUID) }
    let id = UUID()
    let mode: Mode

    init(_ mode: Mode) { self.mode = mode }

    var title: LocalizedStringKey {
        switch mode {
        case .create, .edit: return "Card Studio"
        case .topUp: return "Top up"
        case .returnFunds: return "Return funds"
        case .pay: return "Card payment"
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
    let onCreate: (UUID) -> Void
    @EnvironmentObject private var model: VeltrixModel
    @Environment(\.dismiss) private var dismiss
    @State private var tier = CardTier.classic
    @State private var collection = CardCollection.origin
    @State private var design = CardTier.classic.defaultDesign
    @State private var photo: PhotosPickerItem?
    @State private var name = ""
    @State private var limit = ""
    @State private var amount = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            PageScroll {
                VStack(alignment: .leading, spacing: 16) {
                    switch intent.mode {
                    case .create, .edit:
                        studio
                    case .topUp, .returnFunds, .pay:
                        if case .pay = intent.mode {
                            if !model.onSet {
                                Text("Local operation").font(.caption.weight(.semibold)).foregroundStyle(Color.vxMuted)
                            }
                            TextField("Merchant", text: $name).panel(padding: 12)
                        }
                        TextField("Amount (USD)", text: $amount).keyboardType(.decimalPad).panel(padding: 12)
                    }
                }
                if let error { Text(verbatim: error).font(.footnote).foregroundStyle(Color.vxDown) }
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button(isStudio ? "Save card" : "Confirm operation") { save() }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("card.confirm")
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Color.vxBackground)
            }
            .navigationTitle(intent.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        .onAppear {
            guard case .edit = intent.mode,
                  let card = model.cards.first(where: { $0.id == intent.cardID }) else { return }
            name = card.name
            limit = card.limit.map(Display.input) ?? ""
            tier = card.tier
            collection = card.tier.collection
            design = card.design ?? card.tier.defaultDesign
        }
        .task(id: photo) {
            guard let photo else { return }
            do {
                guard let bytes = try await photo.loadTransferable(type: Data.self),
                      let image = UIImage(data: bytes),
                      let thumbnail = await image.byPreparingThumbnail(ofSize: CGSize(width: 840, height: 840)),
                      let encoded = thumbnail.jpegData(compressionQuality: 0.6),
                      encoded.count <= 360_000 else { throw CocoaError(.fileReadCorruptFile) }
                try Task.checkCancellation()
                design.portrait = encoded
                error = nil
            } catch {
                if !Task.isCancelled { self.error = L.text("Photo unavailable") }
            }
        }
    }

    private var isStudio: Bool {
        switch intent.mode {
        case .create, .edit: return true
        default: return false
        }
    }

    private var studio: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardFace(tier: tier, design: design, name: name.isEmpty ? "VELTRIX" : name,
                     balance: model.money(0), frozen: false, flip: 0, tilt: .zero) { x, y in
                design.markX = min(0.87, max(0.13, x))
                design.markY = min(0.82, max(0.14, y))
            }
            Text("Drag the emblem to reposition it.").font(.caption).foregroundStyle(Color.vxMuted)
            Picker("Collection", selection: Binding(get: { collection }, set: { value in
                collection = value
                if let first = value.tiers.first { choose(first) }
            })) {
                ForEach(CardCollection.allCases, id: \.self) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented)
            Picker("Design", selection: Binding(get: { tier }, set: choose)) {
                ForEach(collection.tiers, id: \.self) { Text($0.title).tag($0) }
            }
            Divider().overlay(Color.vxSeparator)
            Picker("Material", selection: $design.material) {
                ForEach(CardMaterial.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Picker("Texture", selection: $design.texture) {
                ForEach(CardTexture.allCases, id: \.self) { Text(LocalizedStringKey($0.rawValue.capitalized)).tag($0) }
            }
            Picker("Typeface", selection: $design.typeface) {
                ForEach(CardTypeface.allCases, id: \.self) { Text(LocalizedStringKey($0.rawValue.capitalized)).tag($0) }
            }
            ColorPicker("Base color", selection: Binding(get: { Color(cardRGB: design.tint ?? tier.finish.2) },
                                                        set: { design.tint = $0.cardRGB }), supportsOpacity: false)
            ColorPicker("Edge color", selection: Binding(get: { Color(cardRGB: design.shade ?? tier.finish.3) },
                                                        set: { design.shade = $0.cardRGB }), supportsOpacity: false)
            Text("Reflection").font(.subheadline)
            Slider(value: $design.sheen, in: 0...1) { Text("Reflection") }
            PhotosPicker(selection: $photo, matching: .images) { Label("Choose card image", systemImage: "photo") }
            if design.portrait != nil {
                Button("Remove card image") { photo = nil; design.portrait = nil }
            }
            Divider().overlay(Color.vxSeparator)
            TextField("Card name", text: $name).panel(padding: 12)
            TextField("Per-payment limit (USD)", text: $limit).keyboardType(.decimalPad).panel(padding: 12)
        }
    }

    private func choose(_ value: CardTier) {
        tier = value
        let portrait = design.portrait
        design = value.defaultDesign
        design.portrait = portrait
        Feedback.tap()
    }

    private func save() {
        do {
            let command = try makeCommand()
            if model.execute(command, id: intent.id) {
                if case .create = intent.mode, let card = model.cards.last { onCreate(card.id) }
                dismiss()
            } else {
                error = model.error
                model.error = nil
            }
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
            if let id = intent.cardID { return .configureCard(id, name, value, tier: tier, design: design) }
            let title = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "VELTRIX " + L.text(tier.titleKey) : name
            return .createCard(tier, title, value, design: design)
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
