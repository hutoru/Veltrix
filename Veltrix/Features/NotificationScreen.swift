import SwiftUI

struct NotificationScreen: View {
    @EnvironmentObject private var model: VeltrixModel
    @State private var confirmClear = false

    var body: some View {
        PageScroll {
            PageHeader(title: "Notifications", detail: "Account activity") {
                if !model.notificationEntries.isEmpty {
                    Menu {
                        Button("Mark all as read") { model.readNotifications() }
                        Button("Clear history", role: .destructive) { confirmClear = true }
                    } label: {
                        Image(systemName: "ellipsis.circle").font(.title2).frame(width: 44, height: 44)
                    }.accessibilityLabel(Text("Manage notifications"))
                }
            }
            if model.notificationEntries.isEmpty {
                EmptyPanel(icon: "bell", title: "You’re all caught up", detail: "Saved account activity will appear here.")
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(model.notificationEntries) { entry in
                        NavigationLink {
                            EntryScreen(entry: entry)
                                .onAppear { model.readNotification(entry) }
                        } label: {
                            HStack(spacing: 8) {
                                Circle().fill(model.isUnread(entry) ? Color.vxAccent : .clear).frame(width: 6, height: 6)
                                EntryRow(entry: entry)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider().overlay(Color.vxSeparator)
                    }
                }
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Clear notifications?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear history", role: .destructive) { model.clearNotifications() }
            Button("Cancel", role: .cancel) {}
        }
    }
}
