//
//  LocalDevVPNBridge.swift
//  LiveContainerSwiftUI
//
//  Bridges LiveContainer to the LocalDevVPN app so a signing server only
//  reachable through LocalDevVPN's local tunnel can be reached before
//  refreshing apps, without LiveContainer needing its own VPN entitlement.
//
//  LocalDevVPN supports `localdevvpn://enable?scheme=<callback>`, which
//  connects its tunnel and then reopens `<callback>://` once ready. We use
//  this instance's own URL scheme (via LCUtils.appUrlScheme()) as the
//  callback rather than a separate hardcoded one: a second scheme baked
//  into Info.plist would be identical across LiveContainer/2/3, since the
//  multi-instance installer only renames the primary scheme at index 0.
//  Using the instance's real scheme means the callback always reaches the
//  right copy, and is caught as host "vpnready" in LCTabView's existing
//  URL dispatcher.
//
import Foundation
import AppIntents
import UIKit

final class LocalDevVPNBridge {
    static let shared = LocalDevVPNBridge()
    
    private var pendingContinuation: CheckedContinuation<Void, Never>?
    
    private var callbackScheme: String {
        LCUtils.appUrlScheme()?.lowercased() ?? "livecontainer"
    }
    
    /// True if the LocalDevVPN app is installed on this device.
    @MainActor
    var isInstalled: Bool {
        guard let probeURL = URL(string: "localdevvpn://") else { return false }
        return UIApplication.shared.canOpenURL(probeURL)
    }
    
    /// Tells LocalDevVPN to connect, and suspends until its ready callback
    /// fires (caught in LCTabView's onOpenURL as host "vpnready"). Returns
    /// false immediately if LocalDevVPN isn't installed.
    @discardableResult
    @MainActor
    func connect() async -> Bool {
        guard isInstalled,
              let enableURL = URL(string: "localdevvpn://enable?scheme=\(callbackScheme)://vpnready") else {
            return false
        }
        
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            pendingContinuation = continuation
            UIApplication.shared.open(enableURL)
        }
        return true
    }
    
    /// Called from LCTabView's URL dispatcher when LocalDevVPN reopens us
    /// via the callback to signal the tunnel is up.
    func handleVPNReadyCallback() {
        pendingContinuation?.resume()
        pendingContinuation = nil
    }
    
    /// Fire-and-forget disconnect; LocalDevVPN doesn't call back for this.
    @MainActor
    func disconnect() {
        guard let url = URL(string: "localdevvpn://disable") else { return }
        UIApplication.shared.open(url)
    }
    
    /// Connects LocalDevVPN, waits for it to be ready, then runs
    /// LiveContainer's existing "Refresh All Apps" Shortcuts action.
    /// Routed through the Shortcuts app rather than calling SideStore's
    /// RefreshHandler directly, since LiveContainerSwiftUI and SideStore
    /// are separate frameworks that don't link against each other.
    @MainActor
    @discardableResult
    func connectAndRefresh() async -> LocalDevVPNResult {
        guard await connect() else {
            return .notInstalled
        }
        guard let refreshURL = URL(string: "shortcuts://run-shortcut?name=Refresh%20All%20Apps") else {
            return .connectedOnly
        }
        UIApplication.shared.open(refreshURL)
        return .connectedAndRefreshed
    }
}

enum LocalDevVPNResult {
    case notInstalled
    case connectedOnly
    case connectedAndRefreshed
}

// MARK: - Shortcuts support

@available(iOS 16.0, *)
public struct ConnectLocalDevVPNAndRefreshIntent: AppIntent {
    public static var title: LocalizedStringResource = "Connect Local Dev VPN & Refresh"
    public static var description = IntentDescription("Connects LocalDevVPN's local tunnel, then refreshes your sideloaded apps once it's ready.")
    
    public init() {}
    
    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        switch await LocalDevVPNBridge.shared.connectAndRefresh() {
        case .notInstalled:
            return .result(dialog: "LocalDevVPN doesn't appear to be installed.")
        case .connectedOnly, .connectedAndRefreshed:
            return .result(dialog: "Connected LocalDevVPN and started refreshing your apps.")
        }
    }
}

@available(iOS 16.0, *)
public struct DisconnectLocalDevVPNIntent: AppIntent {
    public static var title: LocalizedStringResource = "Disconnect Local Dev VPN"
    public static var description = IntentDescription("Disconnects LocalDevVPN's local tunnel.")
    
    public init() {}
    
    @MainActor
    public func perform() async throws -> some IntentResult {
        LocalDevVPNBridge.shared.disconnect()
        return .result()
    }
}
