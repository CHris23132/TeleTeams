//
//  ContentView.swift
//  Tele Teams
//
//  Created by Chris on 2025-09-20.
//

import SwiftUI

// MARK: - Models
struct StageParticipant: Identifiable, Hashable {
    let device: Device
    let feed: DeviceVideoFeed

    var id: UUID { device.id }
    var name: String { device.name }
    var role: Device.Role? { device.role }
    var roleLabel: String { device.role?.rawValue ?? "" }

    static func == (lhs: StageParticipant, rhs: StageParticipant) -> Bool {
        lhs.device.id == rhs.device.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(device.id)
    }
}

struct ParticipantDisplay: Identifiable {
    let device: Device
    let feed: DeviceVideoFeed

    var id: UUID { device.id }
    var name: String { device.name }
    var role: Device.Role? { device.role }
}

// MARK: - Root View
struct ContentView: View {
    @StateObject private var deviceManager = DeviceManager()
    @State private var showConnectivityManager = false
    @State private var showCameraPublisher = false
    @State private var selectedDeviceId: UUID?
    @State private var activeSender: MediaSender?
    @State private var cameraError: String?
    @Environment(\.horizontalSizeClass) private var hSizeClass
    private enum CompactTab: String, CaseIterable { case stage = "Stage", participants = "Participants" }
    @State private var compactTab: CompactTab = .stage

    private var stageParticipants: [StageParticipant] {
        deviceManager.cameraDevices
            .map { StageParticipant(device: $0, feed: deviceManager.feed(for: $0)) }
            .sorted { $0.name < $1.name }
    }

    private var sidebarParticipants: [ParticipantDisplay] {
        deviceManager.pairedDevices
            .map { ParticipantDisplay(device: $0, feed: deviceManager.feed(for: $0)) }
            .sorted { $0.name < $1.name }
    }

    var body: some View {
        Group {
            if hSizeClass == .compact {
                // iPhone-friendly compact layout
                ZStack {
                    LinearGradient(
                        colors: [
                            Color(hue: 0.66, saturation: 0.65, brightness: 0.24),
                            Color(hue: 0.74, saturation: 0.65, brightness: 0.25)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .ignoresSafeArea()

                    VStack(spacing: 12) {
                        // Top segmented control to switch between Stage and Participants
                        Picker("Section", selection: $compactTab) {
                            ForEach(CompactTab.allCases, id: \.self) { tab in
                                Text(tab.rawValue).tag(tab)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                        // Content area
                        Group {
                            switch compactTab {
                            case .stage:
                                ScrollView {
                                    StageGrid(participants: stageParticipants,
                                              selectedId: $selectedDeviceId,
                                              isCompact: hSizeClass == .compact,
                                              onSelect: { selectedDeviceId = $0 })
                                    .padding(.horizontal, 12)
                                    .padding(.top, 8)
                                }
                            case .participants:
                                ScrollView {
                                    Sidebar(
                                        participants: sidebarParticipants,
                                        selectedId: $selectedDeviceId,
                                        onSettings: { showConnectivityManager = true },
                                        onCamera: presentCameraPublisher,
                                        onBluetooth: { print("Bluetooth tapped") }
                                    )
                                    .frame(maxWidth: .infinity)
                                    .padding(.horizontal, 12)
                                    .padding(.top, 4)
                                }
                            }
                        }

                        Spacer(minLength: 0)
                    }
                }
                // Keep bottom controls visible above the home indicator
                .safeAreaInset(edge: .bottom) {
                    BottomControlBar(
                        onToggleMute: { toggleMuteSelected() },
                        onToggleVideo: { toggleVideoSelected() },
                        onShareScreen: { print("Share Screen tapped") },
                        onMore: { print("More tapped") },
                        onMention: { print("Mention tapped") }
                    )
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
                }
            } else {
                // Regular iPad/large layout
                HStack(spacing: 0) {
                    Sidebar(
                        participants: sidebarParticipants,
                        selectedId: $selectedDeviceId,
                        onSettings: { showConnectivityManager = true },
                        onCamera: presentCameraPublisher,
                        onBluetooth: { print("Bluetooth tapped") }
                    )
                        .frame(width: 320)
                        .background(
                            LinearGradient(
                                colors: [Color(hue: 0.62, saturation: 0.68, brightness: 0.20),
                                         Color(hue: 0.70, saturation: 0.69, brightness: 0.16)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    Divider().opacity(0.12)

                    ZStack {
                        LinearGradient(
                            colors: [
                                Color(hue: 0.66, saturation: 0.65, brightness: 0.24),
                                Color(hue: 0.74, saturation: 0.65, brightness: 0.25)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .ignoresSafeArea()

                        VStack(spacing: 16) {
                            StageGrid(participants: stageParticipants,
                                      selectedId: $selectedDeviceId,
                                      isCompact: hSizeClass == .compact,
                                      onSelect: { selectedDeviceId = $0 })
                                .padding(.horizontal, 20)
                                .padding(.top, 20)

                            Spacer(minLength: 6)

                            BottomControlBar(
                                onToggleMute: { toggleMuteSelected() },
                                onToggleVideo: { toggleVideoSelected() },
                                onShareScreen: { print("Share Screen tapped") },
                                onMore: { print("More tapped") },
                                onMention: { print("Mention tapped") }
                            )
                            .padding(.bottom, 18)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showConnectivityManager) {
            ConnectivityManagerView(deviceManager: deviceManager)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showCameraPublisher, onDismiss: { activeSender = nil }) {
            if let sender = activeSender {
                CameraPublisherView(sender: sender)
                    .preferredColorScheme(.dark)
            } else {
                Text("Select a camera-enabled device from the Device Manager.")
                    .padding()
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            alignSelection()
        }
        .onReceive(deviceManager.$devices) { _ in alignSelection() }
        .alert("Camera Publisher", isPresented: .init(
            get: { cameraError != nil },
            set: { if !$0 { cameraError = nil } }
        ), presenting: cameraError) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
    }

    private func toggleMuteSelected() {
        guard let id = selectedDeviceId,
              let device = deviceManager.device(for: id),
              device.role == .camera else { return }
        deviceManager.toggleMute(for: id)
    }

    private func toggleVideoSelected() {
        guard let id = selectedDeviceId,
              let device = deviceManager.device(for: id),
              device.role == .camera else { return }
        deviceManager.toggleVideo(for: id)
    }

    private func alignSelection() {
        let participants = stageParticipants
        if let current = selectedDeviceId, participants.contains(where: { $0.id == current }) {
            return
        }
        selectedDeviceId = participants.first?.id
    }

    private func presentCameraPublisher() {
        guard let target = cameraTargetDevice() else {
            cameraError = "No camera-capable devices are paired. Pair and connect a device in the Connectivity Manager first."
            return
        }
        if target.role != .camera {
            deviceManager.assignRole(.camera, to: target)
        }
        guard let sender = deviceManager.mediaSender(for: target.id) else {
            cameraError = "Unable to create a media sender for \(target.name)."
            return
        }
        activeSender = sender
        showCameraPublisher = true
    }

    private func cameraTargetDevice() -> Device? {
        if let id = selectedDeviceId,
           let device = deviceManager.device(for: id),
           device.role == .camera {
            return device
        }
        return deviceManager.cameraDevices.first
    }
}

// MARK: - Sidebar
struct Sidebar: View {
    var participants: [ParticipantDisplay]
    @Binding var selectedId: UUID?
    var onSettings: () -> Void
    var onCamera: () -> Void
    var onBluetooth: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            // Title
            HStack {
                Text("Participants (")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.9))
                + Text("\(participants.count)")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                + Text(")")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.9))
                Spacer()
            }
            .padding(.top, 20)
            .padding(.horizontal, 16)

            // List
            VStack(spacing: 12) {
                ForEach(participants) { p in
                    ParticipantRow(participant: p, isSelected: p.id == selectedId)
                        .onTapGesture { selectedId = p.id }
                }
            }
            .padding(.horizontal, 12)

            Spacer()

            // Connection quality card
            VStack(alignment: .leading, spacing: 8) {
                Text("Connection Quality")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.9))

                HStack(spacing: 8) {
                    ForEach(0..<3) { _ in
                        Circle()
                            .frame(width: 8, height: 8)
                            .foregroundStyle(.green)
                    }
                    Spacer()
                    Text("Excellent")
                        .font(.subheadline)
                        .foregroundStyle(.green)
                }
            }
            .padding(14)
            .background(.ultraThinMaterial.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 16)

            // Footer buttons
            HStack(spacing: 18) {
                FooterCircleButton(systemName: "gearshape", action: onSettings)
                FooterCircleButton(systemName: "camera", action: onCamera)
                FooterCircleButton(systemName: "bluetooth", action: onBluetooth)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }
}

struct ParticipantRow: View {
    let participant: ParticipantDisplay
    @ObservedObject private var feed: DeviceVideoFeed
    let isSelected: Bool

    init(participant: ParticipantDisplay, isSelected: Bool = false) {
        self.participant = participant
        self.isSelected = isSelected
        _feed = ObservedObject(wrappedValue: participant.feed)
    }

    private var roleColor: Color {
        switch participant.role {
        case .camera: return .green
        case .viewer: return .blue
        case .none: return .gray.opacity(0.6)
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(isSelected ? Color.green : Color.gray.opacity(0.4))
                    .frame(width: 36, height: 36)
                Image(systemName: "person.fill")
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(participant.name)
                        .foregroundStyle(.white)
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(1)
                    if let role = participant.role {
                        Text(role.rawValue.uppercased())
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(roleColor.opacity(0.2))
                            .foregroundStyle(roleColor)
                            .clipShape(Capsule())
                    }
                    if feed.isSpeaking {
                        Text("SPEAKING")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.green.opacity(0.18))
                            .foregroundStyle(.green)
                            .clipShape(Capsule())
                    }
                }
                Text(feed.connectionState)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
            }
            Spacer()

            if feed.isMuted {
                Image(systemName: "speaker.slash.fill")
                    .foregroundStyle(.red)
            }
        }
        .padding(14)
        .background(
            ZStack {
                if isSelected {
                    LinearGradient(colors: [Color.white.opacity(0.06), Color.white.opacity(0.02)], startPoint: .top, endPoint: .bottom)
                } else {
                    Color.white.opacity(0.05)
                }
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isSelected ? Color.green.opacity(0.6) : .clear, lineWidth: 2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct FooterCircleButton: View {
    let systemName: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial.opacity(0.2))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Stage Grid
struct StageGrid: View {
    let participants: [StageParticipant]
    @Binding var selectedId: UUID?
    var isCompact: Bool = false
    var onSelect: (UUID) -> Void

    private var columns: [GridItem] {
        if isCompact {
            return [GridItem(.adaptive(minimum: 220, maximum: 380), spacing: 12)]
        } else {
            return Array(repeating: GridItem(.flexible(), spacing: 16), count: 2)
        }
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: isCompact ? 12 : 16) {
            ForEach(participants) { p in
                VideoTile(participant: p, isSelected: p.id == selectedId, isCompact: isCompact)
                    .onTapGesture { onSelect(p.id) }
            }
        }
    }
}

struct VideoTile: View {
    let participant: StageParticipant
    @ObservedObject private var feed: DeviceVideoFeed
    let isSelected: Bool
    let isCompact: Bool

    init(participant: StageParticipant, isSelected: Bool = false, isCompact: Bool = false) {
        self.participant = participant
        self.isSelected = isSelected
        self.isCompact = isCompact
        _feed = ObservedObject(wrappedValue: participant.feed)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(0.75))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(isSelected ? Color.green : .clear, lineWidth: 3)
                )

            if feed.isPublishing, feed.isVideoEnabled {
                if let image = feed.currentFrame {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.black.opacity(0.75))
                        .overlay {
                            VStack(spacing: 10) {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .tint(.white)
                                Text("Connecting to camera…")
                                    .font(.footnote)
                                    .foregroundStyle(.white.opacity(0.75))
                            }
                        }
                }
            } else {
                VStack {
                    Spacer()
                    Circle()
                        .fill(feed.isSpeaking ? Color.green : Color.gray.opacity(0.6))
                        .frame(width: isCompact ? 72 : 96, height: isCompact ? 72 : 96)
                        .overlay(
                            Image(systemName: "person.fill")
                                .font(.system(size: 44, weight: .bold))
                                .foregroundStyle(.white)
                        )
                    Spacer()
                }
            }

            // Name tag top-left
            VStack {
                HStack(spacing: 8) {
                    Text(participant.name)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    if let role = participant.role {
                        Text(participant.roleLabel)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background((role == .camera ? Color.green : Color.blue).opacity(0.2))
                            .foregroundStyle(role == .camera ? Color.green : Color.blue)
                            .clipShape(Capsule())
                    }
                    Text(feed.connectionState)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.45))
                        .clipShape(Capsule())
                    Circle()
                        .fill(feed.isSpeaking ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)
                    Spacer()
                }
                .foregroundStyle(.white)
                .padding(10)
                Spacer()
            }

            // Mute badge bottom-right
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    if feed.isMuted {
                        Circle()
                            .fill(Color.red)
                            .frame(width: isCompact ? 26 : 30, height: isCompact ? 26 : 30)
                            .overlay(Image(systemName: "speaker.slash.fill").foregroundStyle(.white))
                            .padding(isCompact ? 10 : 12)
                    } else if !feed.isVideoEnabled {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: isCompact ? 26 : 30, height: isCompact ? 26 : 30)
                            .overlay(Image(systemName: "video.slash.fill").foregroundStyle(.white))
                            .padding(isCompact ? 10 : 12)
                    }
                }
            }
        }
        .aspectRatio(16/9, contentMode: .fit)
    }
}

// MARK: - Bottom Controls
struct BottomControlBar: View {
    var onToggleMute: () -> Void
    var onToggleVideo: () -> Void
    var onShareScreen: () -> Void
    var onMore: () -> Void
    var onMention: () -> Void

    var body: some View {
        HStack(spacing: 18) {
            ControlCircleButton(symbol: "speaker.slash.fill", isDestructive: true, action: onToggleMute)
            ControlCircleButton(symbol: "video.slash.fill", isDestructive: true, action: onToggleVideo)
            ControlCircleButton(symbol: "display", isDestructive: false, action: onShareScreen)
            ControlCircleButton(symbol: "ellipsis", isDestructive: false, action: onMore)
            ControlCircleButton(symbol: "at.circle.fill", isDestructive: true, action: onMention)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

struct ControlCircleButton: View {
    let symbol: String
    var isDestructive: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(
                    Circle().fill(isDestructive ? Color.red : Color.gray.opacity(0.5))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(symbol))
    }
}

// MARK: - MockMediaSender for Preview/Testing
import AVFoundation
import Combine

final class MockMediaSender: MediaSender {
    private let state = CurrentValueSubject<String, Never>("Idle")
    var connectionStatePublisher: AnyPublisher<String, Never> { state.eraseToAnyPublisher() }

    func startPublishing() async throws { state.send("Connected") }
    func stopPublishing() { state.send("Stopped") }

    func sendVideo(sampleBuffer: CMSampleBuffer) { /* no-op for mock */ }
    func sendAudio(sampleBuffer: CMSampleBuffer) { /* no-op for mock */ }

    func setReturnAudioEnabled(_ enabled: Bool) { /* no-op */ }
    func pushToTalk(_ isDown: Bool) { /* no-op */ }
}

// MARK: - Preview
#Preview {
    ContentView()
        .previewInterfaceOrientation(.landscapeLeft)
}
