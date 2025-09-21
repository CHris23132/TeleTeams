//
//  ConnectivityManagerView.swift
//  Tele Teams
//
//  Created by Chris on 2025-09-20.
//

import SwiftUI

struct ConnectivityManagerView: View {
    @ObservedObject var deviceManager: DeviceManager

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    PairingOverviewCard()

                    if !deviceManager.incomingRequests.isEmpty {
                        PairingSection(title: "Incoming Requests") {
                            ForEach(deviceManager.incomingRequests) { device in
                                PairingDeviceCard(
                                    device: device,
                                    feed: deviceManager.feed(for: device),
                                    cancelRequest: { deviceManager.declineIncomingRequest(for: device) },
                                    acceptRequest: { deviceManager.acceptIncomingRequest(from: device) },
                                    declineRequest: { deviceManager.declineIncomingRequest(for: device) },
                                    selectRole: { role in deviceManager.assignRole(role, to: device) }
                                )
                            }
                        }
                    }

                    if !deviceManager.outgoingRequests.isEmpty {
                        PairingSection(title: "Awaiting Confirmation") {
                            ForEach(deviceManager.outgoingRequests) { device in
                                PairingDeviceCard(
                                    device: device,
                                    feed: deviceManager.feed(for: device),
                                    cancelRequest: { deviceManager.cancelPairingRequest(for: device) }
                                )
                            }
                        }
                    }

                    if !deviceManager.awaitingRoleDevices.isEmpty {
                        PairingSection(title: "Select a Role") {
                            ForEach(deviceManager.awaitingRoleDevices) { device in
                                PairingDeviceCard(
                                    device: device,
                                    feed: deviceManager.feed(for: device),
                                    cancelRequest: { deviceManager.cancelPairingRequest(for: device) },
                                    selectRole: { role in deviceManager.assignRole(role, to: device) }
                                )
                            }
                        }
                    }

                    if !deviceManager.pairedDevices.isEmpty {
                        PairingSection(title: "Active Devices") {
                            ForEach(deviceManager.pairedDevices) { device in
                                PairingDeviceCard(
                                    device: device,
                                    feed: deviceManager.feed(for: device),
                                    selectRole: { role in deviceManager.assignRole(role, to: device) },
                                    unpair: { deviceManager.unpair(device) }
                                )
                            }
                        }
                    }

                    if !deviceManager.discoverableDevices.isEmpty {
                        PairingSection(title: "Discoverable Nearby Devices") {
                            ForEach(deviceManager.discoverableDevices) { device in
                                PairingDeviceCard(
                                    device: device,
                                    feed: deviceManager.feed(for: device),
                                    requestPair: { deviceManager.requestPairing(with: device) }
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
            }
            .background(Color.black.opacity(0.9).ignoresSafeArea())
            .navigationTitle("Pair Devices")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        deviceManager.startDiscovery()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
            }
        }
    }
}

// MARK: - Sections & Cards
private struct PairingSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white.opacity(0.85))
            VStack(spacing: 16) {
                content
            }
        }
    }
}

private struct PairingOverviewCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pair nearby devices to assign roles and instantly light up their live feeds on the stage.")
                .font(.title3.bold())
                .foregroundStyle(.white)
            Text("Each device confirms the pairing handshake, then chooses to act as a publishing camera or a viewer. Cameras begin streaming automatically once assigned.")
                .foregroundStyle(.white.opacity(0.72))
                .font(.callout)
        }
        .padding(20)
        .background(
            LinearGradient(colors: [Color(hue: 0.64, saturation: 0.7, brightness: 0.3), Color(hue: 0.72, saturation: 0.7, brightness: 0.32)], startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
    }
}

private struct PairingDeviceCard: View {
    let device: Device
    @ObservedObject private var feed: DeviceVideoFeed
    var requestPair: () -> Void = {}
    var cancelRequest: () -> Void = {}
    var acceptRequest: () -> Void = {}
    var declineRequest: () -> Void = {}
    var selectRole: (Device.Role) -> Void = { _ in }
    var unpair: () -> Void = {}

    init(device: Device,
         feed: DeviceVideoFeed,
         requestPair: @escaping () -> Void = {},
         cancelRequest: @escaping () -> Void = {},
         acceptRequest: @escaping () -> Void = {},
         declineRequest: @escaping () -> Void = {},
         selectRole: @escaping (Device.Role) -> Void = { _ in },
         unpair: @escaping () -> Void = {}) {
        self.device = device
        _feed = ObservedObject(wrappedValue: feed)
        self.requestPair = requestPair
        self.cancelRequest = cancelRequest
        self.acceptRequest = acceptRequest
        self.declineRequest = declineRequest
        self.selectRole = selectRole
        self.unpair = unpair
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Divider().background(Color.white.opacity(0.08))
            actionArea
            if shouldShowPreview {
                DevicePreviewSurface(feed: feed)
                    .frame(height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .transition(.opacity)
            }
        }
        .padding(18)
        .background(cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 1.2)
        )
    }

    private var shouldShowPreview: Bool {
        device.role == .camera || feed.isPublishing
    }

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon(for: device.type))
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.08), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(device.name)
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(deviceDescription)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                    HStack(spacing: 8) {
                        ForEach(Array(device.transports), id: \.self) { transport in
                            Text(transport.rawValue)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.white.opacity(0.08), in: Capsule())
                        }
                    }
                }
                Spacer()
                if let role = device.role {
                    Label(role.rawValue, systemImage: role == .camera ? "video.fill" : "eye")
                        .font(.footnote.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(roleColor(for: role).opacity(0.18), in: Capsule())
                        .foregroundStyle(roleColor(for: role))
                }
            }
            Text(feed.connectionState)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.65))
        }
    }

    @ViewBuilder
    private var actionArea: some View {
        switch device.pairingProgress {
        case .discoverable:
            Button(action: requestPair) {
                Label("Request Pairing", systemImage: "link")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
        case .outgoingRequest:
            HStack(spacing: 12) {
                Label("Waiting for remote confirmation…", systemImage: "hourglass")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Button("Cancel", role: .destructive, action: cancelRequest)
                    .buttonStyle(.bordered)
            }
        case .incomingRequest:
            VStack(alignment: .leading, spacing: 12) {
                Text("This device tapped you to pair. Confirm to continue.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.75))
                HStack(spacing: 14) {
                    Button("Decline", role: .destructive, action: declineRequest)
                        .buttonStyle(.bordered)
                    Button("Accept") { acceptRequest() }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                }
            }
        case .awaitingRoleSelection:
            VStack(alignment: .leading, spacing: 14) {
                Text("Choose how this device will participate.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.75))
                RoleSelector(currentRole: device.role, selectRole: selectRole)
                Button("Cancel Pairing", role: .destructive, action: cancelRequest)
                    .buttonStyle(.bordered)
            }
        case .paired:
            VStack(alignment: .leading, spacing: 14) {
                RoleSelector(currentRole: device.role, selectRole: selectRole)
                HStack {
                    Label(device.connection.displayLabel, systemImage: "dot.radiowaves.left.and.right")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                    Spacer()
                    Button("Unpair", role: .destructive, action: unpair)
                        .buttonStyle(.bordered)
                }
            }
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(Color.white.opacity(0.05))
    }

    private var deviceDescription: String {
        switch device.type {
        case .phone: return "Phone"
        case .tablet: return "Tablet"
        case .wearable: return "Wearable"
        case .capture: return "Capture Source"
        }
    }

    private func icon(for kind: Device.Kind) -> String {
        switch kind {
        case .phone: return "iphone"
        case .tablet: return "ipad"
        case .wearable: return "applewatch"
        case .capture: return "camera.aperture"
        }
    }

    private func roleColor(for role: Device.Role) -> Color {
        switch role {
        case .camera: return .green
        case .viewer: return .blue
        }
    }

    private var borderColor: Color {
        switch device.pairingProgress {
        case .discoverable: return Color.white.opacity(0.08)
        case .outgoingRequest: return Color.orange.opacity(0.5)
        case .incomingRequest: return Color.yellow.opacity(0.5)
        case .awaitingRoleSelection: return Color.purple.opacity(0.5)
        case .paired:
            if let role = device.role { return roleColor(for: role).opacity(0.6) }
            return Color.white.opacity(0.12)
        }
    }
}

private struct RoleSelector: View {
    var currentRole: Device.Role?
    var selectRole: (Device.Role) -> Void

    var body: some View {
        HStack(spacing: 12) {
            ForEach(Device.Role.allCases, id: \.self) { role in
                Button {
                    selectRole(role)
                } label: {
                    Label(role.rawValue, systemImage: icon(for: role))
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(background(for: role), in: Capsule())
                        .foregroundStyle(foreground(for: role))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func icon(for role: Device.Role) -> String {
        role == .camera ? "video.fill" : "eye"
    }

    private func background(for role: Device.Role) -> Color {
        let color = foreground(for: role)
        return color.opacity(currentRole == role ? 0.25 : 0.12)
    }

    private func foreground(for role: Device.Role) -> Color {
        role == .camera ? .green : .blue
    }
}

private struct DevicePreviewSurface: View {
    @ObservedObject var feed: DeviceVideoFeed

    var body: some View {
        ZStack {
            if feed.isPublishing, feed.isVideoEnabled {
                if let image = feed.currentFrame {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .overlay(alignment: .topLeading) {
                            previewOverlay
                        }
                } else {
                    waitingView
                }
            } else {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.black.opacity(0.7))
                    .overlay(alignment: .center) {
                        VStack(spacing: 8) {
                            Image(systemName: "video")
                                .font(.largeTitle)
                                .foregroundStyle(.white.opacity(0.85))
                            Text(feed.connectionState)
                                .foregroundStyle(.white.opacity(0.75))
                                .font(.footnote)
                        }
                    }
            }
        }
        .clipped()
    }

    private var previewOverlay: some View {
        Text(feed.roleLabel)
            .font(.caption.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.6), in: Capsule())
            .foregroundStyle(.white)
            .padding(10)
    }

    private var waitingView: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.black.opacity(0.7))
            .overlay {
                VStack(spacing: 12) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                    Text("Waiting for camera feed…")
                        .foregroundStyle(.white.opacity(0.75))
                        .font(.footnote)
                }
            }
    }
}
