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
    @Published private(set) var devices: [Device] = []
    @Published private(set) var videoFeeds: [UUID: DeviceVideoFeed] = [:]

    private var discoveryTimer: Timer?
    private var streamers: [UUID: VideoStreamSimulator] = [:]

    init() {
        startDiscovery()
    }

    // MARK: - Discovery & Presence
    func startDiscovery() {
        stopDiscovery()

        if devices.isEmpty {
            devices = [
                Device(name: "iPhone 15 Pro", type: .phone, transports: [.wifi, .bleControl], capabilities: [.camera, .mic, .speaker]),
                Device(name: "Body Cam", type: .wearable, transports: [.bleControl], capabilities: [.camera, .mic]),
                Device(name: "iPad Mini", type: .tablet, transports: [.wifi], capabilities: [.camera, .mic, .speaker]),
                Device(name: "Drone Stream", type: .capture, transports: [.wifi], capabilities: [.camera])
            ]
        }

        discoveryTimer = Timer.scheduledTimer(withTimeInterval: 8.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.simulateIncomingRequestIfNeeded()
            }
        }
    }

    func stopDiscovery() {
        discoveryTimer?.invalidate()
        discoveryTimer = nil
    }

    // MARK: - Pairing workflow
    func requestPairing(with device: Device) {
        guard let current = device(for: device.id), current.pairingProgress == .discoverable else { return }
        mutateDevice(id: device.id) { device in
            device.pairingProgress = .outgoingRequest
            device.connection = .pairing
        }

        // Simulate the remote user tapping to confirm pairing after a brief delay.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self else { return }
            self.mutateDevice(id: device.id) { device in
                if device.pairingProgress == .outgoingRequest {
                    device.pairingProgress = .awaitingRoleSelection
                }
            }
        }
    }

    func acceptIncomingRequest(from device: Device) {
        mutateDevice(id: device.id) { device in
            guard device.pairingProgress == .incomingRequest else { return }
            device.pairingProgress = .awaitingRoleSelection
        }
    }

    func declineIncomingRequest(for device: Device) {
        mutateDevice(id: device.id) { device in
            guard device.pairingProgress == .incomingRequest else { return }
            device.pairingProgress = .discoverable
            device.connection = .disconnected
        }
        markPublishing(false, deviceId: device.id)
    }

    func cancelPairingRequest(for device: Device) {
        mutateDevice(id: device.id) { device in
            guard device.pairingProgress == .outgoingRequest || device.pairingProgress == .awaitingRoleSelection else { return }
            device.pairingProgress = .discoverable
            device.connection = .disconnected
            device.role = nil
        }
        markPublishing(false, deviceId: device.id)
    }

    func assignRole(_ role: Device.Role, to device: Device) {
        mutateDevice(id: device.id) { device in
            device.role = role
            device.pairingProgress = .paired
            device.connection = role == .camera ? .streaming : .connected
        }

        if role == .camera {
            markPublishing(true, deviceId: device.id)
        } else {
            markPublishing(false, deviceId: device.id)
            if let feed = videoFeeds[device.id] {
                feed.connectionState = "Viewer Connected"
                feed.isMuted = false
                feed.isSpeaking = false
            }
        }
    }

    func unpair(_ device: Device) {
        mutateDevice(id: device.id) { device in
            device.pairingProgress = .discoverable
            device.connection = .disconnected
            device.role = nil
        }
        markPublishing(false, deviceId: device.id)
        if let feed = videoFeeds[device.id] {
            feed.reset()
            feed.connectionState = "Discoverable"
        }
    }

    // MARK: - Stage Controls
    func toggleMute(for deviceId: UUID) {
        guard let feed = videoFeeds[deviceId] else { return }
        feed.isMuted.toggle()
    }

    func toggleVideo(for deviceId: UUID) {
        guard let feed = videoFeeds[deviceId] else { return }
        feed.isVideoEnabled.toggle()
        if !feed.isVideoEnabled {
            feed.currentFrame = nil
            feed.connectionState = "Video Disabled"
            stopStream(for: deviceId)
        } else {
            feed.connectionState = feed.streamingMode.displayLabel
            if feed.streamingMode == .simulated {
                startStream(for: deviceId, feed: feed)
            }
        }
    }

    func markPublishing(_ isPublishing: Bool, deviceId: UUID, mode: DeviceVideoFeed.StreamingMode = .simulated) {
        guard device(for: deviceId) != nil else { return }
        mutateDevice(id: deviceId) { device in
            if isPublishing {
                device.connection = .streaming
            } else if device.pairingProgress == .paired {
                device.connection = .connected
            } else {
                device.connection = .disconnected
            }
        }

        guard let updatedDevice = device(for: deviceId) else { return }
        guard let feed = videoFeeds[deviceId] ?? (updatedDevice.role != nil ? feed(for: updatedDevice) : nil) else { return }
        feed.isPublishing = isPublishing
        feed.streamingMode = isPublishing ? mode : .none
        if isPublishing {
            feed.connectionState = mode.displayLabel
            feed.isVideoEnabled = true
            if mode == .simulated {
                startStream(for: deviceId, feed: feed)
            } else {
                stopStream(for: deviceId)
            }
        } else {
            if updatedDevice.role == .viewer {
                feed.connectionState = "Viewer Connected"
            } else if updatedDevice.role == .camera {
                feed.connectionState = "Camera Ready"
            } else {
                feed.connectionState = updatedDevice.connection.displayLabel
            }
            feed.currentFrame = nil
            stopStream(for: deviceId)
        }
    }

    func mediaSender(for deviceId: UUID) -> MediaSender? {
        guard let device = device(for: deviceId), device.role == .camera else { return nil }
        let feed = feed(for: device)
        return DeviceLoopbackMediaSender(deviceId: deviceId, manager: self, feed: feed)
    }

    // MARK: - Lookup Helpers
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
        devices.first { $0.id == id }
    }

    var discoverableDevices: [Device] {
        devices.filter { $0.pairingProgress == .discoverable }
    }

    var incomingRequests: [Device] {
        devices.filter { $0.pairingProgress == .incomingRequest }
    }

    var outgoingRequests: [Device] {
        devices.filter { $0.pairingProgress == .outgoingRequest }
    }

    var awaitingRoleDevices: [Device] {
        devices.filter { $0.pairingProgress == .awaitingRoleSelection }
    }

    var pairedDevices: [Device] {
        devices.filter { $0.pairingProgress == .paired && $0.role != nil }
    }

    var cameraDevices: [Device] {
        pairedDevices.filter { $0.role == .camera }
    }

    // MARK: - Internal Helpers
    private func mutateDevice(id: UUID, mutate: (inout Device) -> Void) {
        guard let index = devices.firstIndex(where: { $0.id == id }) else { return }
        var copy = devices[index]
        mutate(&copy)
        devices[index] = copy
        syncFeed(with: copy)
    }

    private func syncFeed(with device: Device) {
        let feed = feed(for: device)
        feed.update(from: device)
    }

    private func startStream(for deviceId: UUID, feed: DeviceVideoFeed) {
        if streamers[deviceId] == nil {
            streamers[deviceId] = VideoStreamSimulator(feed: feed)
        }
        streamers[deviceId]?.start()
    }

    private func stopStream(for deviceId: UUID) {
        streamers[deviceId]?.stop()
        streamers.removeValue(forKey: deviceId)
    }

    private func simulateIncomingRequestIfNeeded() {
        guard let device = devices.first(where: { $0.pairingProgress == .discoverable }) else { return }
        mutateDevice(id: device.id) { device in
            device.pairingProgress = .incomingRequest
            device.connection = .pairing
        }
    }
}

// MARK: - Models
struct Device: Identifiable, Hashable {
    enum Kind: String { case phone, tablet, wearable, capture }
    enum Transport: String, Hashable { case wifi = "Wi-Fi", usb = "USB", bleControl = "BLE" }
    struct Capability: OptionSet, Hashable {
        let rawValue: Int
        static let camera  = Capability(rawValue: 1 << 0)
        static let mic     = Capability(rawValue: 1 << 1)
        static let speaker = Capability(rawValue: 1 << 2)
    }
    enum Connection: String { case disconnected, pairing, connected, streaming }
    enum Role: String, CaseIterable { case camera = "Camera", viewer = "Viewer" }
    enum PairingProgress: Equatable { case discoverable, outgoingRequest, incomingRequest, awaitingRoleSelection, paired }

    let id = UUID()
    var name: String
    var type: Kind
    var transports: Set<Transport>
    var capabilities: Capability

    var pairingProgress: PairingProgress = .discoverable
    var connection: Connection = .disconnected
    var role: Role?

    var supportsVideo: Bool { capabilities.contains(.camera) }
    var supportsAudioIn: Bool { capabilities.contains(.mic) }
    var supportsAudioOut: Bool { capabilities.contains(.speaker) }
}

@MainActor
final class DeviceVideoFeed: ObservableObject, Identifiable {
    enum StreamingMode: Equatable {
        case none
        case simulated
        case external

        var displayLabel: String {
            switch self {
            case .none: return "Offline"
            case .simulated: return "Streaming"
            case .external: return "Live"
            }
        }
    }

    let deviceId: UUID
    @Published var deviceName: String
    @Published var roleLabel: String
    @Published var currentFrame: UIImage?
    @Published var isPublishing: Bool = false
    @Published var isMuted: Bool = false
    @Published var isVideoEnabled: Bool = true
    @Published var connectionState: String
    @Published var isSpeaking: Bool = false
    @Published var streamingMode: StreamingMode = .none

    init(device: Device) {
        self.deviceId = device.id
        self.deviceName = device.name
        self.roleLabel = device.role?.rawValue ?? "Unassigned"
        self.connectionState = device.connection.displayLabel
    }

    func update(from device: Device) {
        deviceName = device.name
        roleLabel = device.role?.rawValue ?? "Unassigned"
        if !isPublishing {
            switch device.pairingProgress {
            case .discoverable:
                connectionState = "Discoverable"
            case .outgoingRequest:
                connectionState = "Awaiting Confirmation"
            case .incomingRequest:
                connectionState = "Incoming Request"
            case .awaitingRoleSelection:
                connectionState = "Select Role"
            case .paired:
                if device.role == .viewer {
                    connectionState = "Viewer Connected"
                } else if device.role == .camera {
                    connectionState = "Camera Ready"
                } else {
                    connectionState = device.connection.displayLabel
                }
            }
        }
    }

    func reset() {
        isPublishing = false
        currentFrame = nil
        connectionState = "Offline"
        isVideoEnabled = true
        isMuted = false
        isSpeaking = false
        roleLabel = "Unassigned"
        streamingMode = .none
    }
}

@MainActor
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
            self.manager?.markPublishing(true, deviceId: self.deviceId, mode: .external)
        }
        state.send(DeviceVideoFeed.StreamingMode.external.displayLabel)
    }

    func stopPublishing() {
        Task { @MainActor in
            self.manager?.markPublishing(false, deviceId: self.deviceId)
        }
        state.send("Stopped")
    }

    func sendVideo(sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        var cgImage: CGImage?
        VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &cgImage)
        guard let cgImage else { return }
        let image = UIImage(cgImage: cgImage)

        Task { @MainActor in
            guard self.feed.isVideoEnabled else { return }
            self.feed.connectionState = DeviceVideoFeed.StreamingMode.external.displayLabel
            self.feed.currentFrame = image
            self.feed.isSpeaking = Bool.random() && Bool.random()
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

@MainActor
private final class VideoStreamSimulator {
    private weak var feed: DeviceVideoFeed?
    private var timer: Timer?
    private var hue: CGFloat = .random(in: 0 ... 1)
    private var tick: Int = 0

    init(feed: DeviceVideoFeed) {
        self.feed = feed
    }

    func start() {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.renderFrame()
            }
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func renderFrame() {
        guard let feed else {
            stop()
            return
        }

        guard feed.isVideoEnabled else { return }
        guard feed.streamingMode == .simulated else {
            stop()
            return
        }

        let size = CGSize(width: 640, height: 360)
        let renderer = UIGraphicsImageRenderer(size: size)
        let currentHue = hue
        let image = renderer.image { ctx in
            UIColor(hue: currentHue, saturation: 0.65, brightness: 0.85, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            let stripeColor = UIColor(hue: (currentHue + 0.2).truncatingRemainder(dividingBy: 1), saturation: 0.55, brightness: 0.9, alpha: 0.65)
            stripeColor.setFill()
            let stripePath = UIBezierPath(roundedRect: CGRect(x: 0, y: size.height * 0.6, width: size.width, height: size.height * 0.45), cornerRadius: 36)
            stripePath.fill()

            let textAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 40),
                .foregroundColor: UIColor.white
            ]
            let subtitleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 22, weight: .medium),
                .foregroundColor: UIColor(white: 1, alpha: 0.8)
            ]

            let name = feed.deviceName as NSString
            name.draw(in: CGRect(x: 24, y: size.height * 0.62, width: size.width - 48, height: 44), withAttributes: textAttributes)
            let subtitle = "Live POV" as NSString
            subtitle.draw(in: CGRect(x: 24, y: size.height * 0.62 + 44, width: size.width - 48, height: 30), withAttributes: subtitleAttributes)
        }

        feed.currentFrame = image
        feed.isSpeaking = tick % 3 == 0

        hue += 0.015
        if hue > 1 { hue -= 1 }
        tick += 1
    }
}

private extension Device.Connection {
    var displayLabel: String {
        switch self {
        case .disconnected: return "Offline"
        case .pairing: return "Pairing"
        case .connected: return "Connected"
        case .streaming: return "Streaming"
        }
    }
}
