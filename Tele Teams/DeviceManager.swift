//
//  DeviceManager.swift
//  Tele Teams
//
//  Created by Chris on 2025-09-20.
//

import Foundation
import Combine
import SwiftUI
import AVFoundation
import UIKit
import VideoToolbox

@MainActor
final class DeviceManager: ObservableObject {
    @Published var nearby: [Device] = []
    @Published var paired: [Device] = []
    @Published private(set) var videoFeeds: [UUID: DeviceVideoFeed] = [:]

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
            if let updated = self.device(for: device.id) {
                let feed = self.feed(for: updated)
                feed.connectionState = "Connected"
            }
        }
    }

    func disconnect(_ device: Device) {
        update(device) {
            $0.connection = .disconnected
            $0.talkbackEnabled = false
            // Keep roles as assigned, just drop the live streams
        }
        if let feed = videoFeeds[device.id] {
            feed.reset()
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

    func toggleMute(for deviceId: UUID) {
        guard let feed = videoFeeds[deviceId] else { return }
        feed.isMuted.toggle()
    }

    func toggleVideo(for deviceId: UUID) {
        guard let feed = videoFeeds[deviceId] else { return }
        feed.isVideoEnabled.toggle()
        if !feed.isVideoEnabled {
            feed.connectionState = "Video Off"
            feed.currentFrame = nil
        } else if feed.isPublishing {
            feed.connectionState = "Streaming"
        } else if let device = device(for: deviceId) {
            feed.connectionState = device.connection.displayLabel
        }
    }

    func markPublishing(_ isPublishing: Bool, deviceId: UUID) {
        guard let feed = videoFeeds[deviceId] else { return }
        feed.isPublishing = isPublishing
        if isPublishing {
            feed.connectionState = "Streaming"
        } else if let device = device(for: deviceId) {
            feed.connectionState = device.connection.displayLabel
            feed.currentFrame = nil
        } else {
            feed.connectionState = "Idle"
            feed.currentFrame = nil
        }
    }

    func mediaSender(for deviceId: UUID) -> MediaSender? {
        guard let device = device(for: deviceId) else { return nil }
        let feed = feed(for: device)
        return DeviceLoopbackMediaSender(deviceId: deviceId, manager: self, feed: feed)
    }

    func feed(for device: Device) -> DeviceVideoFeed {
        if let existing = videoFeeds[device.id] {
            existing.update(from: device)
            return existing
        }
        let feed = DeviceVideoFeed(device: device)
        videoFeeds[device.id] = feed
        return feed
    }

    func feedIfExists(for deviceId: UUID) -> DeviceVideoFeed? {
        videoFeeds[deviceId]
    }

    func device(for id: UUID) -> Device? {
        if let paired = paired.first(where: { $0.id == id }) { return paired }
        if let nearby = nearby.first(where: { $0.id == id }) { return nearby }
        return nil
    }

    // MARK: - Helpers
    private func update(_ device: Device, mutate: (inout Device) -> Void) {
        if let idx = paired.firstIndex(where: { $0.id == device.id }) {
            var copy = paired[idx]
            mutate(&copy)
            paired[idx] = copy
            syncFeed(with: copy)
        } else if let idx = nearby.firstIndex(where: { $0.id == device.id }) {
            var copy = nearby[idx]
            mutate(&copy)
            nearby[idx] = copy
            syncFeed(with: copy)
        }
    }

    private func syncFeed(with device: Device) {
        guard device.roles.contains(.camera) else { return }
        let feed = feed(for: device)
        feed.update(from: device)
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

@MainActor
final class DeviceVideoFeed: ObservableObject, Identifiable {
    let deviceId: UUID
    @Published var deviceName: String
    @Published var currentFrame: UIImage?
    @Published var isPublishing: Bool = false
    @Published var isMuted: Bool = false
    @Published var isVideoEnabled: Bool = true
    @Published var connectionState: String
    @Published var isSpeaking: Bool = false

    init(device: Device) {
        self.deviceId = device.id
        self.deviceName = device.name
        self.connectionState = device.connection.displayLabel
    }

    func update(from device: Device) {
        deviceName = device.name
        if !isPublishing && connectionState != "Video Off" {
            connectionState = device.connection.displayLabel
        }
    }

    func reset() {
        isPublishing = false
        currentFrame = nil
        connectionState = "Disconnected"
        isVideoEnabled = true
        isMuted = false
        isSpeaking = false
    }
}

final class DeviceLoopbackMediaSender: MediaSender {
    private let deviceId: UUID
    private weak var manager: DeviceManager?
    private let feed: DeviceVideoFeed
    private let state = CurrentValueSubject<String, Never>("Idle")

    var connectionStatePublisher: AnyPublisher<String, Never> {
        state.eraseToAnyPublisher()
    }

    init(deviceId: UUID, manager: DeviceManager, feed: DeviceVideoFeed) {
        self.deviceId = deviceId
        self.manager = manager
        self.feed = feed
    }

    func startPublishing() async throws {
        await MainActor.run {
            self.manager?.markPublishing(true, deviceId: self.deviceId)
        }
        state.send("Streaming")
    }

    func stopPublishing() {
        Task { @MainActor in
            self.manager?.markPublishing(false, deviceId: self.deviceId)
        }
        state.send("Stopped")
    }

    func sendVideo(sampleBuffer: CMSampleBuffer) {
        guard feed.isVideoEnabled else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        var cgImage: CGImage?
        VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &cgImage)
        guard let cgImage else { return }
        let image = UIImage(cgImage: cgImage)
        DispatchQueue.main.async {
            if self.feed.isVideoEnabled {
                self.feed.currentFrame = image
            }
        }
    }

    func sendAudio(sampleBuffer: CMSampleBuffer) {
        // In a real implementation, pipe audio to the connected session.
    }

    func setReturnAudioEnabled(_ enabled: Bool) {
        // Loopback mock ignores talkback routing.
    }

    func pushToTalk(_ isDown: Bool) {
        // Loopback mock ignores push-to-talk gating.
    }
}

private extension Device.Connection {
    var displayLabel: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting"
        case .connected: return "Connected"
        }
    }
}
