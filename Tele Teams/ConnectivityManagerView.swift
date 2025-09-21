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
            List {
                if !deviceManager.paired.isEmpty {
                    Section("Paired") {
                        ForEach(deviceManager.paired) { device in
                            DeviceRow(
                                device: device,
                                feed: deviceManager.feedIfExists(for: device.id),
                                connect: { deviceManager.connect(device) },
                                disconnect: { deviceManager.disconnect(device) },
                                pairToggle: { deviceManager.unpair(device) },
                                assign: { role in deviceManager.assign(role, to: device) },
                                remove: { role in deviceManager.remove(role, from: device) },
                                toggleTalkback: { on in deviceManager.setTalkback(on, for: device) }
                            )
                        }
                    }
                }

                Section("Nearby") {
                    ForEach(deviceManager.nearby) { device in
                        DeviceRow(
                            device: device,
                            feed: deviceManager.feedIfExists(for: device.id),
                            connect: {
                                deviceManager.pair(device)
                                deviceManager.connect(device)
                            },
                            disconnect: { deviceManager.disconnect(device) },
                            pairToggle: { deviceManager.pair(device) },
                            assign: { role in deviceManager.assign(role, to: device) },
                            remove: { role in deviceManager.remove(role, from: device) },
                            toggleTalkback: { on in deviceManager.setTalkback(on, for: device) }
                        )
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Connectivity Manager")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        deviceManager.startDiscovery()
                    } label: {
                        Label("Scan", systemImage: "arrow.clockwise")
                    }
                }
            }
        }
    }
}

// MARK: - Device Row
private struct DeviceRow: View {
    let device: Device
    let feed: DeviceVideoFeed?
    let connect: () -> Void
    let disconnect: () -> Void
    let pairToggle: () -> Void
    let assign: (Device.Role) -> Void
    let remove: (Device.Role) -> Void
    let toggleTalkback: (Bool) -> Void

    @State private var showPreview = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                Label(device.name, systemImage: icon(for: device.type))
                    .font(.headline)
                Spacer(minLength: 8)
                HStack(spacing: 6) {
                    ForEach(Array(device.transports), id: \.self) { t in
                        Text(t.rawValue)
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.gray.opacity(0.2), in: Capsule())
                    }
                }
            }

            // Role assignment
            HStack(spacing: 10) {
                roleChip(.camera, enabled: device.roles.contains(.camera), available: device.supportsVideo) { toggled in
                    toggled ? assign(.camera) : remove(.camera)
                }
                roleChip(.mic, enabled: device.roles.contains(.mic), available: device.supportsAudioIn) { toggled in
                    toggled ? assign(.mic) : remove(.mic)
                }
                roleChip(.speaker, enabled: device.roles.contains(.speaker), available: device.supportsAudioOut) { toggled in
                    toggled ? assign(.speaker) : remove(.speaker)
                }
            }

            // Controls
            HStack(spacing: 12) {
                switch device.connection {
                case .disconnected:
                    Button(action: connect) {
                        Label("Connect", systemImage: "link")
                    }
                    .buttonStyle(.borderedProminent)

                case .connecting:
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.green)
                    Button(role: .destructive, action: disconnect) {
                        Label("Cancel", systemImage: "xmark")
                    }
                    .buttonStyle(.bordered)

                case .connected:
                    Button(role: .destructive, action: disconnect) {
                        Label("Disconnect", systemImage: "link.slash")
                    }
                    .buttonStyle(.bordered)
                }

                if device.supportsVideo {
                    Button {
                        showPreview.toggle()
                    } label: {
                        Label("Preview", systemImage: "video")
                    }
                    .buttonStyle(.bordered)
                }

                if device.supportsAudioIn && device.supportsAudioOut {
                    Toggle(isOn: .init(
                        get: { device.talkbackEnabled },
                        set: { toggleTalkback($0) }
                    )) {
                        Label("Talkback", systemImage: "waveform")
                    }
                    .toggleStyle(SwitchToggleStyle(tint: .green))
                }

                Spacer()

                Button(action: pairToggle) {
                    Label(device.isPaired ? "Unpair" : "Pair",
                          systemImage: device.isPaired ? "lock.open" : "lock")
                }
                .buttonStyle(.bordered)
            }

            if showPreview && device.supportsVideo {
                DevicePreviewSurface(feed: feed)
                    .frame(height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .transition(.opacity.combined(with: .scale))
            }

            // Connection state line
            HStack(spacing: 8) {
                Circle()
                    .frame(width: 8, height: 8)
                    .foregroundStyle(color(for: device.connection))
                Text(device.connection.rawValue.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    private func icon(for kind: Device.Kind) -> String {
        switch kind {
        case .phone: return "iphone"
        case .tablet: return "ipad"
        case .wearable: return "applewatch"
        case .capture: return "camera.aperture"
        }
    }

    private func color(for state: Device.Connection) -> Color {
        switch state {
        case .disconnected: return .gray
        case .connecting:   return .yellow
        case .connected:    return .green
        }
    }

    private func roleChip(_ role: Device.Role,
                          enabled: Bool,
                          available: Bool,
                          onToggle: @escaping (Bool) -> Void) -> some View {
        Button {
            guard available else { return }
            onToggle(!enabled)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol(for: role))
                Text(role.rawValue)
            }
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                available
                  ? (enabled ? Color.green.opacity(0.25) : Color.gray.opacity(0.2))
                  : Color.gray.opacity(0.2),
                in: Capsule()
            )
            .overlay(
                Capsule().stroke(enabled ? Color.green : Color.gray.opacity(0.3),
                                 lineWidth: enabled ? 1 : 0.5)
            )
        }
        .buttonStyle(.plain)
        .foregroundStyle(available ? (enabled ? .green : .primary) : .secondary)
        .opacity(available ? 1.0 : 0.5)
    }

    private func symbol(for role: Device.Role) -> String {
        switch role {
        case .camera: return "camera.fill"
        case .mic: return "mic.fill"
        case .speaker: return "speaker.wave.2.fill"
        }
    }
}

private struct DevicePreviewSurface: View {
    let feed: DeviceVideoFeed?

    var body: some View {
        Group {
            if let feed, feed.isPublishing, feed.isVideoEnabled, let image = feed.currentFrame {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .overlay(alignment: .topLeading) {
                        previewOverlay(state: feed.connectionState)
                    }
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.black.opacity(0.6))
                    VStack(spacing: 8) {
                        Image(systemName: "video.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.white.opacity(0.9))
                        Text("Video Preview")
                            .foregroundStyle(.white.opacity(0.8))
                            .font(.footnote)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func previewOverlay(state: String) -> some View {
        Text(state)
            .font(.caption.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.5), in: Capsule())
            .foregroundStyle(.white)
            .padding(10)
    }
}
