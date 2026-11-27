import SwiftUI

struct EarnScreen: View {
    @Environment(\.veltrixTheme) private var theme
    @EnvironmentObject private var model: VeltrixModel
    @State private var asset = "ethereum"
    @State private var term = StakeTerm.flexible
    @State private var amount = ""
    @State private var error: String?

    private var positions: [Stake] { model.portfolio.stakes ?? [] }

    var body: some View {
        PageScroll {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                VStack(alignment: .leading, spacing: 12) {
                    let value = valuation { $0.units }
                    Text("Staked value").font(.caption).foregroundStyle(theme.muted)
                    CountValue(text: model.money(value)).font(.largeTitle.weight(.medium)).lineLimit(1).minimumScaleFactor(0.45)
                    LabeledContent("Accrued rewards", value: model.money(valuation { try $0.rewards(at: context.date) }))
                    ForEach(positions) { stake in position(stake, now: context.date) }
                }
            }
            strategy
            let history = model.portfolio.entries.filter { $0.kind == .stakeReward }.reversed()
            if !history.isEmpty {
                Text("Reward history").font(.headline)
                ForEach(history) { entry in
                    NavigationLink { EntryScreen(entry: entry) } label: { EntryRow(entry: entry) }.buttonStyle(.plain)
                }
            }
            if let error { Text(verbatim: error).font(.footnote).foregroundStyle(theme.negative) }
        }
        .navigationTitle("Earn").navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively).dismissibleKeyboard()
    }

    private var strategy: some View {
        let rate = Stake.rates[asset] ?? 0
        let units = Display.amount(amount) ?? 0
        return VStack(alignment: .leading, spacing: 12) {
            Text("Staking strategies").font(.headline)
            Picker("Asset", selection: $asset) {
                ForEach(Asset.catalog.filter { Stake.rates[$0.id] != nil }) { coin in
                    Text(verbatim: coin.name).tag(coin.id)
                }
            }
            Picker("Term", selection: $term) {
                ForEach(StakeTerm.allCases) { value in termTitle(value).tag(value) }
            }
            LabeledContent("Estimated APY", value: Display.percent(rate * 100))
            LabeledContent("Minimum amount", value: Display.number(Stake.minimum) + " " + Asset.ticker(asset))
            LabeledContent("Available balance", value: model.units((try? model.portfolio.freeUnits(asset)) ?? 0))
            Text(term == .flexible ? "Withdraw any time" : "Withdraw after the term ends").font(.caption).foregroundStyle(theme.muted)
            TextField("Amount", text: $amount).keyboardType(.decimalPad)
            ForEach([1, 30, 365], id: \.self) { days in
                if let reward = try? Stake.estimate(units: max(0, units), rate: rate, seconds: Decimal(days * 86_400)) {
                    LabeledContent {
                        Text(verbatim: Display.number(reward, maximum: 12) + " " + Asset.ticker(asset))
                    } label: { horizon(days) }
                }
            }
            Button("Stake") {
                if run(.openStake(asset, units, term)) { amount = ""; Keyboard.dismiss() }
            }.buttonStyle(PrimaryButtonStyle()).disabled(units < Stake.minimum)
        }.panel()
    }

    private func position(_ stake: Stake, now: Date) -> some View {
        let canClose = stake.maturity.map { $0 <= now } ?? true
        let reward = (try? stake.rewards(at: now)) ?? 0
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                if let coin = Asset.catalog.first(where: { $0.id == stake.asset }) {
                    CoinIcon(asset: coin, url: model.quotes[coin.id]?.image, size: 28)
                }
                Text(verbatim: model.units(stake.units) + " " + Asset.ticker(stake.asset)).font(.headline)
                Spacer()
                Text(verbatim: Display.percent(stake.rate * 100)).foregroundStyle(theme.muted)
            }
            termTitle(stake.term).font(.caption).foregroundStyle(theme.muted)
            if let maturity = stake.maturity {
                LabeledContent("Term ends", value: maturity.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
            }
            HStack {
                Button("Claim rewards") { _ = run(.claimStake(stake.id, close: false)) }.disabled(!canClose || reward <= 0)
                Button("Withdraw") { _ = run(.claimStake(stake.id, close: true)) }.disabled(!canClose)
            }.buttonStyle(.bordered)
        }.panel(padding: 12)
    }

    private func valuation(_ units: (Stake) throws -> Decimal) -> Decimal? {
        try? positions.reduce(0) { total, position in
            guard let quote = model.prices[position.asset] else { throw SimulationError.missingQuote }
            return try MoneyMath.addValuation(total, MoneyMath.multiply(units(position), quote))
        }
    }

    private func run(_ command: Command) -> Bool {
        let saved = model.execute(command, showFeedback: false)
        error = model.error
        model.error = nil
        if saved { Feedback.success() }
        return saved
    }

    private func termTitle(_ term: StakeTerm) -> Text {
        switch term {
        case .flexible: return Text("Flexible")
        case .week: return Text("7 days")
        case .month: return Text("30 days")
        case .quarter: return Text("90 days")
        }
    }

    private func horizon(_ days: Int) -> Text {
        switch days {
        case 1: return Text("Daily estimate")
        case 30: return Text("Monthly estimate")
        default: return Text("Annual estimate")
        }
    }
}
