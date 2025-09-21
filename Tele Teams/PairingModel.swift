//
//  PairingModel.swift
//  Tele Teams
//
//  New pairing flow model that keeps the handshake state simple and explicit.
//

import Foundation

enum PairingRole: String, CaseIterable, Identifiable {
    case camera = "Camera"
    case viewer = "Viewer"

    var id: String { rawValue }

    var opposite: PairingRole {
        switch self {
        case .camera: return .viewer
        case .viewer: return .camera
        }
    }
}

struct PairingPeer: Identifiable, Equatable {
    let id: UUID
    var name: String
    var detail: String
    var localTapped: Bool = false
    var remoteTapped: Bool = false
    var localRole: PairingRole?
    var remoteRole: PairingRole?

    var isReady: Bool { localTapped && remoteTapped }

    var subtitle: String { detail }

    var guidance: String {
        if isReady {
            return "Both sides have tapped. Continue to choose who will be the camera and who will watch."
        }
        if localTapped {
            return "Waiting for \(name) to tap you back."
        }
        if remoteTapped {
            return "\(name) tapped you. Tap them back to accept the pairing."
        }
        return "Tap to send \(name) a pairing request."
    }
}

@MainActor
final class PairingModel: ObservableObject {
    @Published private(set) var peers: [PairingPeer]
    @Published var activePairing: PairingPeer?

    init(peers: [PairingPeer] = PairingPeer.samples) {
        self.peers = peers
    }

    func toggleLocalTap(for id: UUID) {
        guard let idx = peers.firstIndex(where: { $0.id == id }) else { return }
        peers[idx].localTapped.toggle()
        if !peers[idx].localTapped {
            // Reset handshake when cancelled.
            peers[idx].remoteTapped = false
            peers[idx].localRole = nil
            peers[idx].remoteRole = nil
            if activePairing?.id == id {
                activePairing = nil
            }
        }
        evaluatePairing(at: idx)
    }

    func registerRemoteTap(for id: UUID) {
        guard let idx = peers.firstIndex(where: { $0.id == id }) else { return }
        peers[idx].remoteTapped = true
        evaluatePairing(at: idx)
    }

    func simulateRemoteTap(for id: UUID) {
        // Prototype helper so designers can see the flow without a second device.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.registerRemoteTap(for: id)
        }
    }

    func setRole(_ role: PairingRole, for id: UUID) {
        guard let idx = peers.firstIndex(where: { $0.id == id }) else { return }
        peers[idx].localRole = role
        peers[idx].remoteRole = role.opposite
    }

    func clearActivePairing() {
        activePairing = nil
    }

    func endSession(for id: UUID) {
        guard let idx = peers.firstIndex(where: { $0.id == id }) else { return }
        peers[idx].localTapped = false
        peers[idx].remoteTapped = false
        peers[idx].localRole = nil
        peers[idx].remoteRole = nil
        if activePairing?.id == id {
            activePairing = nil
        }
    }

    func peer(for id: UUID) -> PairingPeer? {
        peers.first(where: { $0.id == id })
    }

    private func evaluatePairing(at index: Int) {
        let peer = peers[index]
        if peer.localTapped && peer.remoteTapped {
            activePairing = peer
        } else if activePairing?.id == peer.id {
            activePairing = nil
        }
    }
}

private extension PairingPeer {
    static let samples: [PairingPeer] = [
        PairingPeer(id: UUID(), name: "Director iPad", detail: "Control Room • Wi‑Fi 6"),
        PairingPeer(id: UUID(), name: "Stage Cam 1", detail: "Studio Floor • 5G", remoteTapped: true),
        PairingPeer(id: UUID(), name: "Back Row Viewer", detail: "Audience • Ethernet")
    ]
}
