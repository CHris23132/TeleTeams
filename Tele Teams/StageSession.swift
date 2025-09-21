//
//  StageSession.swift
//  Tele Teams
//
//  Defines the lightweight session container and media bridge between
//  the publishing camera and the viewer stage.
//

import Foundation
import UIKit
import Combine
import AVFoundation
import VideoToolbox

struct StageSession: Identifiable, Equatable {
    let id = UUID()
    let peer: PairingPeer
    let localRole: PairingRole
    let remoteRole: PairingRole
    let mediaCoordinator: StageMediaCoordinator

    init(peer: PairingPeer, localRole: PairingRole, mediaCoordinator: StageMediaCoordinator = StageMediaCoordinator()) {
        self.peer = peer
        self.localRole = localRole
        self.remoteRole = localRole.opposite
        self.mediaCoordinator = mediaCoordinator

        switch localRole {
        case .camera:
            mediaCoordinator.cameraStatus = "Waiting to start"
        case .viewer:
            mediaCoordinator.startSimulatedRemoteCamera(named: peer.name)
        }
    }

    static func == (lhs: StageSession, rhs: StageSession) -> Bool {
        lhs.id == rhs.id
    }
}

@MainActor
final class StageMediaCoordinator: ObservableObject {
    @Published var latestFrame: UIImage?
    @Published var cameraStatus: String = "Idle"

    private var remoteTimer: Timer?

    func makeCameraSender() -> MediaSender {
        cameraStatus = "Connecting"
        return StageCameraSender(coordinator: self)
    }

    func startSimulatedRemoteCamera(named name: String) {
        stop()
        cameraStatus = "Connecting to \(name)…"

        var step = 0
        remoteTimer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { [weak self] _ in
            guard let self else { return }
            step += 1
            if step < 3 {
                self.cameraStatus = "Connecting…"
            } else {
                self.cameraStatus = "Live from \(name)"
            }
            self.latestFrame = StageMediaCoordinator.makeDemoFrame(index: step, label: name)
        }
    }

    func stop() {
        remoteTimer?.invalidate()
        remoteTimer = nil
        latestFrame = nil
        cameraStatus = "Idle"
    }

    private static func makeDemoFrame(index: Int, label: String) -> UIImage {
        let size = CGSize(width: 1280, height: 720)
        let renderer = UIGraphicsImageRenderer(size: size)
        let hue = CGFloat((Double((index % 20)) / 20.0).truncatingRemainder(dividingBy: 1.0))
        let topColor = UIColor(hue: hue, saturation: 0.55, brightness: 0.9, alpha: 1)
        let bottomColor = UIColor(hue: (hue + 0.1).truncatingRemainder(dividingBy: 1.0), saturation: 0.65, brightness: 0.65, alpha: 1)
        let timeString = DateFormatter.cached.string(from: Date())

        return renderer.image { ctx in
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                         colors: [topColor.cgColor, bottomColor.cgColor] as CFArray,
                                         locations: [0, 1]) {
                ctx.cgContext.drawLinearGradient(gradient,
                                                 start: CGPoint(x: 0, y: 0),
                                                 end: CGPoint(x: 0, y: size.height),
                                                 options: [])
            }

            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center

            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 64, weight: .bold),
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraph
            ]
            let subAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 28, weight: .semibold),
                .foregroundColor: UIColor.white.withAlphaComponent(0.9),
                .paragraphStyle: paragraph
            ]

            let title = "Live feed"
            let titleRect = CGRect(x: 0, y: size.height * 0.35 - 40, width: size.width, height: 80)
            title.draw(in: titleRect, withAttributes: attributes)

            let subtitle = "\(label) • \(timeString)"
            let subtitleRect = CGRect(x: 0, y: size.height * 0.35 + 50, width: size.width, height: 40)
            subtitle.draw(in: subtitleRect, withAttributes: subAttributes)
        }
    }
}

private final class StageCameraSender: MediaSender {
    private weak var coordinator: StageMediaCoordinator?
    private let state = CurrentValueSubject<String, Never>("Idle")

    init(coordinator: StageMediaCoordinator) {
        self.coordinator = coordinator
        state.send("Connecting")
    }

    var connectionStatePublisher: AnyPublisher<String, Never> {
        state.eraseToAnyPublisher()
    }

    func startPublishing() async throws {
        await MainActor.run {
            coordinator?.cameraStatus = "Streaming"
        }
        state.send("Streaming")
    }

    func stopPublishing() {
        Task { @MainActor in
            coordinator?.cameraStatus = "Stopped"
            coordinator?.latestFrame = nil
        }
        state.send("Stopped")
    }

    func sendVideo(sampleBuffer: CMSampleBuffer) {
        guard let coordinator else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        var cgImage: CGImage?
        VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &cgImage)
        guard let cgImage else { return }

        let image = UIImage(cgImage: cgImage)
        DispatchQueue.main.async {
            coordinator.latestFrame = image
        }
    }

    func sendAudio(sampleBuffer: CMSampleBuffer) {
        // The prototype keeps audio local.
    }

    func setReturnAudioEnabled(_ enabled: Bool) {
        // Not required for the in-memory bridge.
    }

    func pushToTalk(_ isDown: Bool) {
        // No-op for the prototype bridge.
    }
}

private extension DateFormatter {
    static let cached: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        return formatter
    }()
}
