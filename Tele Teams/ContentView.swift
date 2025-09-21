//
//  ContentView.swift
//  Tele Teams
//
//  Created by Chris on 2025-09-20.
//

import SwiftUI

// MARK: - Models
struct Participant: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var isSpeaking: Bool = false
    var isMuted: Bool = false
    var isVideoOff: Bool = false
}

// MARK: - Root View
struct ContentView: View {
    @StateObject private var deviceManager = DeviceManager()
    @State private var showConnectivityManager = false
    @State private var showCameraPublisher = false
    private let cameraSender = MockMediaSender()
    @State private var participants: [Participant] = [
        .init(name: "Jason", isSpeaking: true, isMuted: false),
        .init(name: "Brett", isSpeaking: false, isMuted: true),
        .init(name: "Mike", isSpeaking: false, isMuted: true),
        .init(name: "James", isSpeaking: false, isMuted: true)
    ]
    @State private var selectedId: UUID?
    @Environment(\.horizontalSizeClass) private var hSizeClass
    private enum CompactTab: String, CaseIterable { case stage = "Stage", participants = "Participants" }
    @State private var compactTab: CompactTab = .stage

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
                                    StageGrid(participants: participants,
                                              selectedId: $selectedId,
                                              isCompact: hSizeClass == .compact,
                                              onSelect: { selectedId = $0 })
                                    .padding(.horizontal, 12)
                                    .padding(.top, 8)
                                }
                            case .participants:
                                ScrollView {
                                    Sidebar(
                                        participants: $participants,
                                        selectedId: $selectedId,
                                        onSettings: { showConnectivityManager = true },
                                        onCamera: { showCameraPublisher = true },
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
                        participants: $participants,
                        selectedId: $selectedId,
                        onSettings: { showConnectivityManager = true },
                        onCamera: { showCameraPublisher = true },
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
                            StageGrid(participants: participants,
                                      selectedId: $selectedId,
                                      isCompact: hSizeClass == .compact,
                                      onSelect: { selectedId = $0 })
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
        .sheet(isPresented: $showCameraPublisher) {
            CameraPublisherView(sender: cameraSender)
                .preferredColorScheme(.dark)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if selectedId == nil { selectedId = participants.first?.id }
        }
    }

    private func toggleMuteSelected() {
        guard let id = selectedId, let idx = participants.firstIndex(where: { $0.id == id }) else { return }
        participants[idx].isMuted.toggle()
    }

    private func toggleVideoSelected() {
        guard let id = selectedId, let idx = participants.firstIndex(where: { $0.id == id }) else { return }
        participants[idx].isVideoOff.toggle()
    }
}

// MARK: - Sidebar
struct Sidebar: View {
    @Binding var participants: [Participant]
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
    let participant: Participant
    var isSelected: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(isSelected ? Color.green : Color.gray.opacity(0.4))
                    .frame(width: 36, height: 36)
                Image(systemName: "person.fill")
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(participant.name)
                        .foregroundStyle(.white)
                        .font(.system(size: 16, weight: .semibold))
                    if participant.isSpeaking {
                        Text("Speaking")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.green.opacity(0.18))
                            .foregroundStyle(.green)
                            .clipShape(Capsule())
                    }
                }
                .lineLimit(1)
            }
            Spacer()

            if participant.isMuted {
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
    let participants: [Participant]
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
    let participant: Participant
    var isSelected: Bool = false
    var isCompact: Bool = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(isSelected ? Color.green : .clear, lineWidth: 3)
                )

            VStack {
                Spacer()
                Circle()
                    .fill(participant.isSpeaking ? Color.green : Color.gray.opacity(0.6))
                    .frame(width: isCompact ? 72 : 96, height: isCompact ? 72 : 96)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 44, weight: .bold))
                            .foregroundStyle(.white)
                    )
                Spacer()
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
                    Circle()
                        .fill(participant.isSpeaking ? Color.green : Color.gray)
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
                    if participant.isMuted {
                        Circle()
                            .fill(Color.red)
                            .frame(width: isCompact ? 26 : 30, height: isCompact ? 26 : 30)
                            .overlay(Image(systemName: "speaker.slash.fill").foregroundStyle(.white))
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
