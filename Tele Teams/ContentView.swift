//
//  ContentView.swift
//  Tele Teams
//
//  Reimagined pairing-first experience.
//

import SwiftUI
import Combine

struct ContentView: View {
    @StateObject private var coordinator = AppCoordinator()

    var body: some View {
        Group {
            switch coordinator.route {
            case .pairing:
                PairingScreen(model: coordinator.pairingModel)
                    .transition(.opacity)
            case .roleSelection(let peer):
                RoleSelectionScreen(peer: peer) { role in
                    coordinator.confirmRole(role, for: peer)
                } onBack: {
                    coordinator.cancelRoleSelection()
                }
                .transition(.move(edge: .trailing))
            case .stage(let session):
                StageScreen(session: session) { endedSession in
                    coordinator.endSession(endedSession)
                }
                .transition(.opacity.combined(with: .scale))
            }
        }
        .animation(.easeInOut, value: coordinator.routeID)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Pairing Flow

private struct PairingScreen: View {
    @ObservedObject var model: PairingModel

    var body: some View {
        NavigationStack {
            ZStack {
                background
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Tap the device you want to pair with. Both sides must tap each other to confirm the pairing.")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding()
                            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                        ForEach(model.peers) { peer in
                            PairingCard(
                                peer: peer,
                                onTap: { model.toggleLocalTap(for: peer.id) },
                                onSimulateRemote: { model.simulateRemoteTap(for: peer.id) }
                            )
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 32)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Pairing")
        }
    }

    private var background: some View {
        LinearGradient(
            colors: [Color(hue: 0.67, saturation: 0.65, brightness: 0.22),
                     Color(hue: 0.73, saturation: 0.60, brightness: 0.20)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

private struct PairingCard: View {
    let peer: PairingPeer
    let onTap: () -> Void
    let onSimulateRemote: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(peer.name)
                        .font(.title3.weight(.semibold))
                    Text(peer.subtitle)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.75))
                }
                Spacer()
                statusBadge
            }

            Divider().background(Color.white.opacity(0.1))

            HStack(spacing: 12) {
                Button(action: onTap) {
                    Label(peer.localTapped ? "Cancel" : "Tap to Pair", systemImage: peer.localTapped ? "xmark" : "hand.point.up.left")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(peer.localTapped ? Color.red.opacity(0.25) : Color.green.opacity(0.25), in: Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(peer.localTapped ? Color.red : Color.green)

                if !peer.remoteTapped {
                    Button(action: onSimulateRemote) {
                        Label("Simulate remote tap", systemImage: "sparkles")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.white.opacity(0.08), in: Capsule())
                }
            }

            Text(peer.guidance)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(20)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(peer.isReady ? Color.green.opacity(0.6) : Color.white.opacity(0.05), lineWidth: 1.5)
        )
    }

    private var statusBadge: some View {
        Group {
            if peer.isReady {
                Label("Ready", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if peer.localTapped {
                Label("Waiting", systemImage: "hourglass")
                    .foregroundStyle(.yellow)
            } else if peer.remoteTapped {
                Label("Incoming", systemImage: "bolt.horizontal.fill")
                    .foregroundStyle(.cyan)
            } else {
                Label("Available", systemImage: "antenna.radiowaves.left.and.right")
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.black.opacity(0.4), in: Capsule())
    }
}

// MARK: - Role Selection

private struct RoleSelectionScreen: View {
    let peer: PairingPeer
    let onSelect: (PairingRole) -> Void
    let onBack: () -> Void
    @State private var selectedRole: PairingRole = .camera

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hue: 0.66, saturation: 0.65, brightness: 0.22),
                         Color(hue: 0.58, saturation: 0.40, brightness: 0.25)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                VStack(spacing: 10) {
                    Text("Pair with \(peer.name)")
                        .font(.largeTitle.bold())
                    Text("Decide whether this device will act as the camera or the viewer for this session.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Picker("Role", selection: $selectedRole) {
                    Text("Camera").tag(PairingRole.camera)
                    Text("Viewer").tag(PairingRole.viewer)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 40)

                RoleDescription(role: selectedRole)
                    .padding(.horizontal, 24)

                Button {
                    onSelect(selectedRole)
                } label: {
                    Label(selectedRole == .camera ? "Start as Camera" : "Join as Viewer",
                          systemImage: selectedRole == .camera ? "video.fill" : "eye")
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.green, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 32)

                Button(action: onBack) {
                    Label("Back", systemImage: "chevron.left")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(.white.opacity(0.08), in: Capsule())
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(.top, 80)
        }
    }
}

private struct RoleDescription: View {
    let role: PairingRole

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(role == .camera ? "Camera responsibilities" : "Viewer responsibilities",
                  systemImage: role == .camera ? "camera" : "eye")
                .font(.headline)

            Text(role == .camera ? cameraText : viewerText)
                .foregroundStyle(.white.opacity(0.75))
                .font(.body)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var cameraText: String {
        "The camera role will publish live video and audio from this device. As soon as you continue, capture starts automatically so the paired viewer can watch in real-time."
    }

    private var viewerText: String {
        "The viewer role receives the live camera feed from your paired partner. We will automatically connect to the stream and display it on the stage once the camera comes online."
    }
}

// MARK: - Stage

private struct StageScreen: View {
    let session: StageSession
    let onEnd: (StageSession) -> Void

    var body: some View {
        StageBody(session: session, media: session.mediaCoordinator) {
            onEnd(session)
        }
    }
}

private struct StageBody: View {
    let session: StageSession
    @ObservedObject var media: StageMediaCoordinator
    let onEnd: () -> Void
    @State private var showEndAlert = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hue: 0.65, saturation: 0.62, brightness: 0.22),
                         Color(hue: 0.72, saturation: 0.58, brightness: 0.20)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                header

                Group {
                    if session.localRole == .camera {
                        CameraPublisherView(sender: media.makeCameraSender(), autoStartPublishing: true)
                            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                    } else {
                        ViewerFeedView(media: media, remoteName: session.peer.name)
                            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 360)
                .shadow(radius: 30, y: 10)

                ParticipantsStrip(session: session, media: media)

                Button(role: .destructive) {
                    showEndAlert = true
                } label: {
                    Label("End session", systemImage: "phone.down.fill")
                        .font(.headline)
                        .padding(.horizontal, 26)
                        .padding(.vertical, 12)
                        .background(Color.red.opacity(0.2), in: Capsule())
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 28)
            .padding(.top, 36)
            .padding(.bottom, 24)
        }
        .alert("End Session?", isPresented: $showEndAlert) {
            Button("End", role: .destructive) {
                media.stop()
                onEnd()
            }
            Button("Continue", role: .cancel) {}
        } message: {
            Text("This will disconnect from \(session.peer.name) and return to the pairing lobby.")
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text(session.localRole == .camera ? "Camera Session" : "Viewer Session")
                .font(.title2.weight(.semibold))
            Text(statusLine)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.75))
        }
    }

    private var statusLine: String {
        if session.localRole == .camera {
            return "Publishing to \(session.peer.name)"
        } else {
            return "Watching live from \(session.peer.name)"
        }
    }
}

private struct ViewerFeedView: View {
    @ObservedObject var media: StageMediaCoordinator
    let remoteName: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.black.opacity(0.75))

            if let image = media.latestFrame {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .clipped()
                    .overlay(alignment: .topLeading) {
                        statusPill("Watching \(remoteName)")
                            .padding(12)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        statusPill(media.cameraStatus)
                            .padding(12)
                    }
            } else {
                VStack(spacing: 14) {
                    ProgressView()
                        .tint(.green)
                    Text(media.cameraStatus)
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
        }
    }

    private func statusPill(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.45), in: Capsule())
    }
}

private struct ParticipantsStrip: View {
    let session: StageSession
    @ObservedObject var media: StageMediaCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Participants")
                .font(.headline)

            HStack(spacing: 14) {
                ParticipantBadge(name: "You", role: session.localRole, status: localStatus, highlight: true)
                ParticipantBadge(name: session.peer.name, role: session.remoteRole, status: remoteStatus, highlight: false)
                Spacer()
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var localStatus: String {
        switch session.localRole {
        case .camera:
            return media.cameraStatus
        case .viewer:
            return "Connected"
        }
    }

    private var remoteStatus: String {
        switch session.remoteRole {
        case .camera:
            return media.cameraStatus
        case .viewer:
            return session.localRole == .camera ? "Receiving" : "Ready"
        }
    }
}

private struct ParticipantBadge: View {
    let name: String
    let role: PairingRole
    let status: String
    var highlight: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: role == .camera ? "video.fill" : "eye")
                Text(role.rawValue)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(highlight ? Color.green : Color.white.opacity(0.8))

            Text(name)
                .font(.headline)

            Text(status)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(highlight ? Color.green.opacity(0.18) : Color.white.opacity(0.05),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Coordinator

@MainActor
final class AppCoordinator: ObservableObject {
    enum Route: Equatable {
        case pairing
        case roleSelection(PairingPeer)
        case stage(StageSession)
    }

    @Published var route: Route = .pairing
    @Published var pairingModel: PairingModel

    private var cancellables = Set<AnyCancellable>()

    init(pairingModel: PairingModel = PairingModel()) {
        self.pairingModel = pairingModel

        pairingModel.$activePairing
            .compactMap { $0 }
            .removeDuplicates()
            .sink { [weak self] peer in
                self?.route = .roleSelection(peer)
            }
            .store(in: &cancellables)
    }

    func confirmRole(_ role: PairingRole, for peer: PairingPeer) {
        pairingModel.setRole(role, for: peer.id)
        let updatedPeer = pairingModel.peer(for: peer.id) ?? peer
        let session = StageSession(peer: updatedPeer, localRole: role)
        pairingModel.clearActivePairing()
        route = .stage(session)
    }

    func cancelRoleSelection() {
        pairingModel.clearActivePairing()
        route = .pairing
    }

    func endSession(_ session: StageSession) {
        pairingModel.endSession(for: session.peer.id)
        route = .pairing
    }

    fileprivate var routeID: String {
        switch route {
        case .pairing: return "pairing"
        case .roleSelection(let peer): return "role-\(peer.id)"
        case .stage(let session): return "stage-\(session.id)"
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .preferredColorScheme(.dark)
}
