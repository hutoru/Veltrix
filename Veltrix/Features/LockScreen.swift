import SwiftUI

struct LockScreen: View {
    @EnvironmentObject private var lock: AppLock
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("profileName") private var name = ""
    @State private var appeared = false

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    HStack(spacing: 9) {
                        VeltrixMark().fill(.white).frame(width: 19, height: 19)
                        Text(verbatim: "VELTRIX").font(.caption.weight(.semibold)).tracking(5)
                    }
                    .padding(.top, 24)
                    .accessibilityElement(children: .combine)

                    Spacer(minLength: 48)
                    VStack(spacing: 12) {
                        ProfileAvatar(size: 80, monochrome: true)
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared || reduceMotion ? 0 : 6)
                            .padding(.bottom, 10)
                        Text("Welcome back").font(.system(size: 34, weight: .semibold)).tracking(-1)
                            .accessibilityAddTraits(.isHeader)
                        if !name.isEmpty {
                            Text(verbatim: name).font(.subheadline).foregroundStyle(.white.opacity(0.62))
                                .lineLimit(1).minimumScaleFactor(0.65)
                        }
                    }
                    Spacer(minLength: 40)
                    VStack(spacing: 16) {
                        if let error = lock.error {
                            Text(verbatim: error).font(.footnote).foregroundStyle(.white.opacity(0.68))
                                .multilineTextAlignment(.center)
                        }
                        Button {
                            Feedback.tap()
                            Task { await lock.unlockWithDevice() }
                        } label: {
                            HStack(spacing: 10) {
                                if lock.busy {
                                    ProgressView().tint(.black).accessibilityHidden(true)
                                } else {
                                    Image(systemName: "lock.open").accessibilityHidden(true)
                                }
                                Text("Unlock").font(.headline)
                            }
                            .frame(maxWidth: .infinity, minHeight: 52)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.black)
                        .background(.white, in: RoundedRectangle(cornerRadius: 14))
                        .disabled(lock.busy)
                        .accessibilityIdentifier("lock.unlock")
                    }
                    .padding(.bottom, 24)
                }
                .padding(.horizontal, 32)
                .frame(maxWidth: 410)
                .frame(minHeight: geometry.size.height)
                .frame(maxWidth: .infinity)
            }
        }
        .background(Color.vxDarkBackground.ignoresSafeArea())
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .onAppear { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.35)) { appeared = true } }
    }
}
