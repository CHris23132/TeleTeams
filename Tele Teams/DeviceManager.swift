//
//  DeviceManager.swift
//  Tele Teams
//
//  Created by Chris on 2025-09-20.
//

import Foundation
import Combine
import Foundation
import SwiftUI

final class DeviceManager: ObservableObject {
    @Published var nearby: [Device] = []
    @Published var paired: [Device] = []

    private var discoveryTimer: Timer?

    init() { startDiscovery() }

    func startDiscovery() {
        stopDiscovery()
        // Mock discovery feed; replace with your real discovery pipeline (e.g., Bonjour, Multipeer, USB/UVC scan, etc.)
        discoveryTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let samples: [Device] = [
                Device(name: "iPhone 15 Pro", type: .phone, transports: [.wifi, .bleControl], capabilities: [.camera, .mic, .speaker]),
                Device(name: "iPad Mini", type: .tablet, transports: [.wifi, .bleControl], capabilities: [.camera, .mic, .speaker]),
                Device(name: "UVC Capture", type: .capture, transports: [.usb], capabilities: [.camera]),
                Device(name: "Watch Ultra", type: .wearable, transports: [.bleControl], capabilities: [.mic, .speaker])
            ]
            // De-dupe by id/name in a real implementation; here we rotate a few
            if self.nearby.isEmpty {
                self.nearby = samples
            } else {
                self.nearby.shuffle()
            }
        }
    }

    func stopDiscovery() {
        discoveryTimer?.invalidate()
        discoveryTimer = nil
    }

    func pair(_ device: Device) {
        // Avoid duplicates
        if !paired.contains(where: { $0.id == device.id }) {
            var d = device
            d.isPaired = true
            paired.append(d)
            nearby.removeAll { $0.id == device.id }
        }
    }

    func unpair(_ device: Device) {
        paired.removeAll { $0.id == device.id }
        var d = device
        d.isPaired = false
        if !nearby.contains(where: { $0.id == device.id }) {
            nearby.append(d)
        }
    }

    func connect(_ device: Device) {
        update(device) { $0.connection = .connecting }
        // Simulate async connect
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            self.update(device) { d in
                d.connection = .connected
                // Default routing: Wi-Fi/USB carry streams; BLE only control
                if d.transports.contains(.usb) || d.transports.contains(.wifi) {
                    // keep as-is; in real impl wire the streams
                }
            }
        }
    }

    func disconnect(_ device: Device) {
        update(device) {
            $0.connection = .disconnected
            $0.talkbackEnabled = false
            // Keep roles as assigned, just drop the live streams
        }
    }

    func assign(_ role: Device.Role, to device: Device) {
        update(device) { $0.roles.insert(role) }
    }

    func remove(_ role: Device.Role, from device: Device) {
        update(device) { $0.roles.remove(role) }
    }

    func setTalkback(_ enabled: Bool, for device: Device) {
        update(device) { $0.talkbackEnabled = enabled }
    }

    // MARK: - Helpers
    private func update(_ device: Device, mutate: (inout Device) -> Void) {
        if let idx = paired.firstIndex(where: { $0.id == device.id }) {
            var copy = paired[idx]
            mutate(&copy)
            paired[idx] = copy
        } else if let idx = nearby.firstIndex(where: { $0.id == device.id }) {
            var copy = nearby[idx]
            mutate(&copy)
            nearby[idx] = copy
        }
    }
}

struct Device: Identifiable, Hashable {
    enum Kind: String { case phone, tablet, wearable, capture }
    enum Transport: String, Hashable { case wifi = "Wi-Fi", usb = "USB", bleControl = "BLE (control)" }
    struct Capability: OptionSet, Hashable {
        let rawValue: Int
        static let camera  = Capability(rawValue: 1 << 0)
        static let mic     = Capability(rawValue: 1 << 1)
        static let speaker = Capability(rawValue: 1 << 2)
    }
    enum Connection: String { case disconnected, connecting, connected }
    enum Role: String, CaseIterable, Hashable { case camera = "Camera", mic = "Mic", speaker = "Speaker" }

    let id = UUID()
    var name: String
    var type: Kind
    var transports: Set<Transport>
    var capabilities: Capability

    var isPaired: Bool = false
    var connection: Connection = .disconnected
    var roles: Set<Role> = []
    var talkbackEnabled: Bool = false

    // Convenience flags
    var supportsVideo: Bool { capabilities.contains(.camera) }
    var supportsAudioIn: Bool { capabilities.contains(.mic) }
    var supportsAudioOut: Bool { capabilities.contains(.speaker) }
}
