// Menu building

import Cocoa

enum MenuItemTypes: Int {
    case none = 0, tunnel, tunnelplaceholder
}

class TunnelDetailMenuItem: NSMenuItem {
    override var indentationLevel: Int {
        get {
            return 1
        }
        set {
            self.indentationLevel = newValue
        }
    }
}

private let tunnelMenuItemHeight: CGFloat = 22

/// Full-width menu row; NSMenu otherwise sizes custom views to fit their subviews only.
private class TunnelRowMenuItemView: NSView {
    init(width: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: tunnelMenuItemHeight))
        autoresizingMask = .width
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func resizeToMenuWidth(_ menuWidth: CGFloat) {
        setFrameSize(NSSize(width: menuWidth, height: tunnelMenuItemHeight))
    }
}

/// Forwards clicks to the enclosing menu item action (required for `NSMenuItem.view`).
private class ClickableMenuItemView: TunnelRowMenuItemView {
    override func mouseUp(with _: NSEvent) {
        guard let menuItem = enclosingMenuItem,
              let menu = menuItem.menu,
              menuItem.isEnabled else { return }
        menu.cancelTracking()
        let index = menu.index(of: menuItem)
        if index >= 0 {
            menu.performActionForItem(at: index)
        }
    }

    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        return true
    }
}

/// Tunnel row while wg-quick is bringing the interface up or down.
private final class TunnelPendingMenuItemView: TunnelRowMenuItemView {
    private let spinner = NSProgressIndicator()

    init(title: String, menuWidth: CGFloat) {
        super.init(width: menuWidth)

        let label = NSTextField(labelWithString: title)
        label.font = NSFont.menuFont(ofSize: 0)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.translatesAutoresizingMaskIntoConstraints = false
        addSubview(spinner)
        spinner.startAnimation(nil)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: spinner.leadingAnchor, constant: -8),
            spinner.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            spinner.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
}

/// Active tunnel name row: green background and "(connected)" label.
private final class TunnelNameMenuItemView: ClickableMenuItemView {
    init(title: String, menuWidth: CGFloat) {
        super.init(width: menuWidth)
        wantsLayer = true
        layer?.backgroundColor = NSColor.systemGreen.cgColor

        let nameLabel = NSTextField(labelWithString: title)
        nameLabel.font = NSFont.menuFont(ofSize: 0)
        nameLabel.textColor = .labelColor
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(nameLabel)

        let statusLabel = NSTextField(labelWithString: "(connected)")
        statusLabel.font = NSFont.menuFont(ofSize: 0)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(statusLabel)

        NSLayoutConstraint.activate([
            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: nameLabel.trailingAnchor, constant: 6),
            statusLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
        ])
    }
}

let maxMenuItemChars = 40

private let aboutPanelRepositoryURL = "https://github.com/NorseGaud/macos-menubar-wireguard"
private let aboutPanelUpstreamURL = "https://github.com/aequitas/macos-menubar-wireguard"
private let aboutPanelWireGuardURL = "https://www.wireguard.com/"

func aboutPanelCredits() -> NSAttributedString {
    let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let baseAttributes: [NSAttributedString.Key: Any] = [.font: font, .paragraphStyle: paragraph]

    let credits = NSMutableAttributedString()
    var isFirstLine = true

    func appendLine() {
        guard !isFirstLine else {
            isFirstLine = false
            return
        }
        credits.append(NSAttributedString(string: "\n", attributes: baseAttributes))
    }

    func appendText(_ text: String, link: String? = nil) {
        appendLine()
        var attributes = baseAttributes
        if let link {
            attributes[.link] = link
        }
        credits.append(NSAttributedString(string: text, attributes: attributes))
    }

    appendText(aboutPanelRepositoryURL, link: aboutPanelRepositoryURL)
    appendLine()
    credits.append(NSAttributedString(string: "Forked from ", attributes: baseAttributes))
    credits.append(NSAttributedString(
        string: aboutPanelUpstreamURL,
        attributes: baseAttributes.merging([.link: aboutPanelUpstreamURL]) { _, new in new }
    ))
    appendText(aboutPanelWireGuardURL, link: aboutPanelWireGuardURL)

    return credits
}

/// Width needed to fit standard (non-view) menu items; avoids `menu.update()` during rebuild.
func tunnelMenuRowWidth(in menu: NSMenu) -> CGFloat {
    var width = menu.minimumWidth
    let font = NSFont.menuFont(ofSize: 0)
    for item in menu.items where item.view == nil {
        let titleWidth = (item.title as NSString).size(withAttributes: [.font: font]).width
        width = max(width, titleWidth + 36)
    }
    return width
}

/// Match custom tunnel row views to the menu width after items are inserted.
func resizeTunnelMenuItemViews(in menu: NSMenu) {
    let menuWidth = max(tunnelMenuRowWidth(in: menu), menu.size.width)
    for item in menu.items where item.tag == MenuItemTypes.tunnel.rawValue {
        guard let view = item.view as? TunnelRowMenuItemView else { continue }
        view.resizeToMenuWidth(menuWidth)
    }
}

extension String {
    enum TruncationPosition {
        case head
        case middle
        case tail
    }

    func truncated(limit: Int, position: TruncationPosition = .tail, leader: String = "...") -> String {
        guard count > limit else { return self }

        switch position {
        case .head:
            return leader + suffix(limit)
        case .middle:
            let headCharactersCount = Int(ceil(Float(limit - leader.count) / 2.0))

            let tailCharactersCount = Int(floor(Float(limit - leader.count) / 2.0))

            return "\(prefix(headCharactersCount))\(leader)\(suffix(tailCharactersCount))"
        case .tail:
            return prefix(limit) + leader
        }
    }
}

// contruct menu with all tunnels found in configuration
// TODO: find out if it is possible to have a dynamic bound IB menu with variable contents
/// Target enabled state for tunnels with an in-flight wg-quick up/down.
typealias PendingTunnelOperations = [String: Bool]

func buildMenu(
    tunnels: Tunnels,
    menuItemWidth: CGFloat = 200,
    pendingTunnels: PendingTunnelOperations = [:],
    allTunnelDetails: Bool = false,
    connectedTunnelDetails: Bool = true,
    showInstallInstructions _: Bool = false
) -> [NSMenuItem] {
    guard !tunnels.isEmpty else {
        return [NSMenuItem(title: "No tunnel configurations found",
                           action: nil, keyEquivalent: "")]
    }

    var items: [NSMenuItem] = []
    for tunnel in tunnels.sorted(by: { $0.name.lowercased() < $1.name.lowercased() }) {
        let item = NSMenuItem(title: tunnel.name,
                              action: #selector(AppDelegate.toggleTunnel(_:)), keyEquivalent: "")
        item.target = NSApp.delegate
        items.append(item)
        item.representedObject = tunnel.name
        if pendingTunnels[tunnel.name] != nil {
            item.view = TunnelPendingMenuItemView(title: tunnel.name, menuWidth: menuItemWidth)
            item.isEnabled = false
        } else if tunnel.connected {
            item.view = TunnelNameMenuItemView(title: tunnel.name, menuWidth: menuItemWidth)
        }

        if tunnel.connected && (connectedTunnelDetails || allTunnelDetails), let interface = tunnel.interface {
            items.append(TunnelDetailMenuItem(title: "Interface: \(interface)",
                                              action: nil, keyEquivalent: ""))
        }

        if (tunnel.connected && connectedTunnelDetails) || allTunnelDetails {
            if let config = tunnel.config {
                items.append(TunnelDetailMenuItem(title: "Address: \(config.address)",
                                                  action: nil, keyEquivalent: ""))
                for peer in config.peers {
                    let endpointTitle = "Endpoint: \(peer.endpoint)"
                    let endpointItem = TunnelDetailMenuItem(title: endpointTitle.truncated(limit: maxMenuItemChars,
                                                                                           position: .middle),
                                                            action: nil, keyEquivalent: "")
                    endpointItem.toolTip = endpointTitle
                    items.append(endpointItem)

                    let ipsTitle = "Allowed IPs: \(peer.allowedIps.joined(separator: ", "))"
                    let ipsItem = TunnelDetailMenuItem(title: ipsTitle.truncated(limit: maxMenuItemChars,
                                                                                 position: .middle),
                                                       action: nil, keyEquivalent: "")
                    ipsItem.toolTip = ipsTitle
                    items.append(ipsItem)
                }
            } else {
                items.append(TunnelDetailMenuItem(title: "Could not parse tunnel configuration!",
                                                  action: nil, keyEquivalent: ""))
            }
        }
    }

    return items
}

private let activeMenuBarGreen = NSColor.systemGreen

private func greenFilledMenuBarImage(from image: NSImage) -> NSImage {
    guard let tinted = image.copy() as? NSImage else { return image }
    tinted.isTemplate = false
    tinted.lockFocus()
    activeMenuBarGreen.set()
    NSRect(origin: .zero, size: tinted.size).fill(using: .sourceAtop)
    tinted.unlockFocus()
    return tinted
}

/// Drop pending entries once tunnel state matches the requested target.
func resolvePendingTunnelOperations(_ pending: inout PendingTunnelOperations, tunnels: Tunnels) {
    for (tunnelName, targetEnabled) in pending {
        guard let tunnel = tunnels.first(where: { $0.name == tunnelName }) else { continue }
        if tunnel.connected == targetEnabled {
            pending.removeValue(forKey: tunnelName)
        }
    }
}

func menuImage(tunnels: Tunnels) -> NSImage {
    let connectedTunnels = tunnels.filter { $0.connected }
    if connectedTunnels.isEmpty {
        let icon = NSImage(named: .disabled)!
        icon.isTemplate = true
        return icon
    } else {
        return greenFilledMenuBarImage(from: NSImage(named: .connected)!)
    }
}
