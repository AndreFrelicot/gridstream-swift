//
//  ServerMenu.swift
//  gridstream-ipad
//
//  The app icon and connection status at the start of the top bar, as a
//  menu: connect to a Mac, open or leave the demo, reset or delete it, show
//  its credits, and forget this iPad's session.
//

import SwiftUI

struct ServerMenu: View {
    let status: ConnectionStatus
    /// Shows the icon and a status dot only, for a narrow bar.
    var compact = false
    var onForgetDevice: (() -> Void)?
    var onMenuOpen: (() -> Void)?
    var onMenuClose: (() -> Void)?

    @Environment(DemoController.self) private var demoController
    @Environment(ServerDiscoveryService.self) private var discoveryService
    @Environment(GridState.self) private var gridState

    @State private var confirmsReset = false
    @State private var confirmsDelete = false
    @State private var errorMessage: String?
    @State private var menuIsOpen = false

    /// Keeps the overlay up while the menu is open or a dialog asks
    /// something: the bar would otherwise hide under them.
    private var holdsOverlay: Bool {
        menuIsOpen || confirmsReset || confirmsDelete || errorMessage != nil
    }

    var body: some View {
        menuButton
        .onChange(of: holdsOverlay) { _, holds in
            if holds {
                onMenuOpen?()
            } else {
                onMenuClose?()
            }
        }
        .onDisappear {
            if holdsOverlay { onMenuClose?() }
        }
        .confirmationDialog("Reset the demo?", isPresented: $confirmsReset, titleVisibility: .visible) {
            Button("Reset Demo", role: .destructive) {
                Task {
                    do {
                        try await demoController.resetDemo()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
        } message: {
            Text("Ratings, tags, lists, notes and captures go back to how the demo came.")
        }
        .confirmationDialog("Delete the demo videos?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Delete Demo Videos", role: .destructive) {
                Task {
                    do {
                        try await demoController.deleteDemo(discovery: discoveryService, gridState: gridState)
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
        } message: {
            Text("This frees the space they use. You can download the demo again later.")
        }
        .alert(
            "Demo",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var menuButton: some View {
        label
            .accessibilityHidden(true)
            .overlay {
                MenuTouchArea(
                    menu: menu,
                    accessibilityLabel: String(localized: "Server: \(String(localized: status.displayText))"),
                    onMenuOpen: { menuIsOpen = true },
                    onMenuClose: { menuIsOpen = false }
                )
            }
    }

    private var menu: UIMenu {
        var items: [UIMenuElement] = []

        if discoveryService.isDemoActive {
            items.append(UIMenu(title: String(localized: "Demo"), options: .displayInline, children: [
                item("Reset Demo…", "arrow.counterclockwise") {
                    confirmsReset = true
                },
                item("Demo Credits", "text.book.closed") {
                    demoController.flow = .credits
                },
                item("Exit Demo", "rectangle.portrait.and.arrow.right") {
                    demoController.exitDemo(discovery: discoveryService, gridState: gridState)
                }
            ]))
            items.append(item("Connect to my Mac", "desktopcomputer") {
                demoController.exitDemo(discovery: discoveryService, gridState: gridState)
            })
        } else {
            items.append(item("Connect to my Mac", "desktopcomputer") {
                demoController.flow = .connectMac
            })
            items.append(item("Try the Demo", "play.rectangle.on.rectangle") {
                demoController.tryDemo(discovery: discoveryService, gridState: gridState)
            })
        }

        if demoController.isPackInstalled {
            items.append(item("Delete Demo Videos…", "trash", attributes: .destructive) {
                confirmsDelete = true
            })
        }

        if let onForgetDevice {
            items.append(item("Forget Device", "iphone.slash", action: onForgetDevice))
        }

        items.append(UIMenu(title: Self.buildDescription, options: .displayInline, children: [
            item("Help", "questionmark.circle") {
                demoController.flow = .help
            },
            item("Show Welcome", "hand.wave") {
                demoController.flow = .onboarding
            }
        ]))

        return UIMenu(children: items)
    }

    private func item(
        _ title: LocalizedStringResource,
        _ systemImage: String,
        attributes: UIMenuElement.Attributes = [],
        action: @escaping () -> Void
    ) -> UIAction {
        UIAction(title: String(localized: title), image: UIImage(systemName: systemImage), attributes: attributes) { _ in
            action()
        }
    }

    /// "GridStream 1.0 (1) · 2c73e4c": the version and the git commit the app
    /// was built from (stamped by the "Stamp Git Commit" build phase), so a
    /// report names the exact build. "no commit stamp" means that build phase
    /// did not run; "unknown" that it ran and git gave no commit.
    private static let buildDescription: String = {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        let commit = info["GridStreamCommit"] as? String ?? "no commit stamp"
        return "GridStream \(version) (\(build)) · \(commit)"
    }()

    private var label: some View {
        HStack(spacing: 10) {
            BrandIcon(size: 32)
                .overlay(alignment: .bottomTrailing) {
                    if compact { statusDot.offset(x: 3, y: 3) }
                }

            if !compact {
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: "GridStream")
                        .font(.subheadline.weight(.bold))
                    if discoveryService.isDemoActive {
                        Text("DEMO")
                            .font(.caption2.weight(.heavy))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(.white, in: Capsule())
                            .foregroundStyle(Brand.deep)
                    } else {
                        HStack(spacing: 5) {
                            statusDot
                            Text(status.displayText)
                                .font(.caption.weight(.medium))
                                .opacity(0.85)
                        }
                    }
                }
                .lineLimit(1)
                .fixedSize()
            }

            Image(systemName: "chevron.down")
                .font(.caption.weight(.bold))
                .opacity(0.75)
        }
        .foregroundStyle(.white)
        .padding(.leading, 5)
        .padding(.trailing, 12)
        .frame(minHeight: 42)
        .background(Capsule().fill(.white.opacity(0.17)))
        .contentShape(Capsule())
    }

    /// Green when a server is reachable, white while searching, red when
    /// the connection is lost; amber in the demo.
    private var statusDot: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 8, height: 8)
            .overlay(Circle().stroke(.white, lineWidth: compact ? 1.5 : 0))
    }

    private var statusColor: Color {
        if discoveryService.isDemoActive { return Brand.amber }
        switch status {
        case .searching:
            return .white.opacity(0.7)
        case .found, .connected:
            return Color(red: 0.45, green: 0.95, blue: 0.5)
        case .disconnected:
            return Color(red: 1, green: 0.35, blue: 0.35)
        }
    }
}

/// An invisible button over the label that opens a native menu and reports
/// it opening and closing, which a SwiftUI `Menu` cannot (see
/// `MenuCircleButton`).
private struct MenuTouchArea: UIViewRepresentable {
    var menu: UIMenu
    var accessibilityLabel: String
    var onMenuOpen: () -> Void
    var onMenuClose: () -> Void

    func makeUIView(context: Context) -> MenuCircleButton.MenuButton {
        let button = MenuCircleButton.MenuButton(configuration: .plain())
        button.showsMenuAsPrimaryAction = true
        return button
    }

    func updateUIView(_ button: MenuCircleButton.MenuButton, context: Context) {
        button.menu = menu
        button.onMenuOpen = onMenuOpen
        button.onMenuClose = onMenuClose
        button.accessibilityLabel = accessibilityLabel
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: MenuCircleButton.MenuButton, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions()
    }
}
