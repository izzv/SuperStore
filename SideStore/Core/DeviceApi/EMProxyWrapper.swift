//
//  EMProxyWrapper.swift
//  SideStore
//
//  Created by Magesh K on 22/02/26.
//  Copyright © 2026 SideStore. All rights reserved.
//
import Foundation
import Minimuxer

func startEMProxy(bind_addr: String = AppConstants.Proxy.serverURL) async throws {
    debugLog("[SuperStore] startEMProxy(\(bind_addr)) invoked")
    defer { debugLog("[SuperStore] startEMProxy() completed") }

    #if targetEnvironment(simulator)
    debugLog("[SuperStore] startEMProxy() is no-op on simulator")
    #else
    let components = bind_addr.split(separator: ":")
    guard components.count >= 1 && components.count <= 2 else {
        debugLog("[SuperStore] startEMProxy() invalid bind_addr format: \(bind_addr)")
        throw EMProxyError.invalidSocketAddress(bind_addr)
    }

    await bindConnectionConfig()

    let host = ConnectionConfig.shared.wireguardServerHost
    let port = ConnectionConfig.shared.wireguardServerPort
    let overrideIp = ConnectionConfig.shared.overrideTunnelPeerIp.trimmingCharacters(in: .whitespacesAndNewlines)
    let initialHandshakePeer = !overrideIp.isEmpty ? overrideIp : (ConnectionConfig.shared.tunnelPeerIp ?? "")
    let lockdowndPort = AppConstants.Minimuxer.lockdowndPort
    minimuxer.emproxy.setHandshakeClient(host: initialHandshakePeer, port: lockdowndPort, enabled: !initialHandshakePeer.isEmpty)
    do {        
        try await minimuxer.emproxy.start(host: host, port: port)
    } catch {
        debugLog("[SuperStore] startEMProxy() failed with error: \(error)")
        throw error
    }
    #endif
}

func stopEMProxy() async throws {
    debugLog("[SuperStore] stopEMProxy() invoked")
    defer { debugLog("[SuperStore] stopEMProxy() completed") }

    #if targetEnvironment(simulator)
    debugLog("[SuperStore] stopEMProxy() is no-op on simulator")
    #else
    do {
        try await minimuxer.emproxy.stop()
    } catch {
        debugLog("[SuperStore] stopEMProxy() failed with error: \(error)")
        throw error
    }
    #endif
}
