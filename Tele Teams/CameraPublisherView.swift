//
//  CameraPublisherView.swift
//  Tele Teams
//
//  Created by Chris on 2025-09-20.
//

import Foundation
import SwiftUI
import AVFoundation
import Combine

// MARK: - Protocol your networking layer implements (e.g., WebRTC publisher)
public protocol MediaSender: AnyObject {
    // Call when capture starts/stops so you can create/tear down tracks
    func startPublishing() async throws
    func stopPublishing()

    // Forward raw A/V to the network stack (use your capturer or convert as needed)
    func sendVideo(sampleBuffer: CMSampleBuffer)
    func sendAudio(sampleBuffer: CMSampleBuffer)

    // Downlink (talkback) control
    func setReturnAudioEnabled(_ enabled: Bool)
    func pushToTalk(_ isDown: Bool)

    // Optional diagnostics
    var connectionStatePublisher: AnyPublisher<String, Never> { get }
}

// MARK: - ViewModel
@MainActor
final class CameraPublisherViewModel: NSObject, ObservableObject {
    // Public toggles
    @Published var isPublishing = false
    @Published var isMicMuted = false
    @Published var useBackCamera = true
    @Published var torchOn = false
    @Published var connectionState = "Idle"

    // Wiring
    private let sender: MediaSender
    private let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()
    private var videoDevice: AVCaptureDevice?
    private var audioDevice: AVCaptureDevice?
    private var cancellables = Set<AnyCancellable>()

    // Audio session for duplex (capture + playback)
    private let audioSession = AVAudioSession.sharedInstance()

    init(sender: MediaSender) {
        self.sender = sender
        super.init()

        // Listen to connection state from networking layer
        sender.connectionStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.connectionState = $0 }
            .store(in: &cancellables)
    }

    // MARK: Lifecycle
    func configureAndStartPreview(on previewLayer: AVCaptureVideoPreviewLayer) async {
        do {
            try await requestPermissionsIfNeeded()
            try configureAVAudioSession()
            try configureCaptureSession()
            previewLayer.session = session
            session.startRunning()
        } catch {
            connectionState = "Setup error: \(error.localizedDescription)"
        }
    }

    func startPublishing() {
        guard !isPublishing else { return }
        Task {
            do {
                try await sender.startPublishing()
                sender.setReturnAudioEnabled(true)
                isPublishing = true
                connectionState = "Publishing"
            } catch {
                connectionState = "Publish error: \(error.localizedDescription)"
            }
        }
    }

    func stopPublishing() {
        guard isPublishing else { return }
        sender.stopPublishing()
        isPublishing = false
        connectionState = "Stopped"
    }

    func toggleMicMute() { isMicMuted.toggle() }
    func toggleTorch() {
        guard let cam = videoDevice, cam.hasTorch else { return }
        do {
            try cam.lockForConfiguration()
            cam.torchMode = torchOn ? .off : .on
            cam.unlockForConfiguration()
            torchOn.toggle()
        } catch { }
    }

    func flipCamera(previewLayer: AVCaptureVideoPreviewLayer) {
        useBackCamera.toggle()
        session.beginConfiguration()
        // Remove current video input
        session.inputs
            .compactMap { $0 as? AVCaptureDeviceInput }
            .filter { $0.device.hasMediaType(.video) }
            .forEach { session.removeInput($0) }

        // Add new camera
        if let newDevice = selectVideoDevice(back: useBackCamera) {
            if let input = try? AVCaptureDeviceInput(device: newDevice),
               session.canAddInput(input) {
                session.addInput(input)
                videoDevice = newDevice
            }
        }
        session.commitConfiguration()
        previewLayer.connection?.videoOrientation = .landscapeRight
    }

    func pushToTalk(_ down: Bool) {
        sender.pushToTalk(down)
    }

    // MARK: Permissions & Config
    private func requestPermissionsIfNeeded() async throws {
        // Camera
        if AVCaptureDevice.authorizationStatus(for: .video) != .authorized {
            let ok = await AVCaptureDevice.requestAccess(for: .video)
            guard ok else { throw NSError(domain: "perm", code: 1, userInfo: [NSLocalizedDescriptionKey: "Camera permission denied"]) }
        }
        // Microphone
        if AVAudioSession.sharedInstance().recordPermission != .granted {
            let granted = await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { ok in
                    continuation.resume(returning: ok)
                }
            }
            guard granted else {
                throw NSError(domain: "perm",
                              code: 2,
                              userInfo: [NSLocalizedDescriptionKey: "Mic permission denied"])
            }
        }
    }

    private func configureAVAudioSession() throws {
        try audioSession.setCategory(.playAndRecord,
                                     mode: .voiceChat,
                                     options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP, .mixWithOthers])
        try audioSession.setActive(true, options: [])
    }

    private func configureCaptureSession() throws {
        session.beginConfiguration()
        session.sessionPreset = .hd1280x720

        // Video
        guard let vDevice = selectVideoDevice(back: useBackCamera) else { throw NSError(domain: "cap", code: 3) }
        let vInput = try AVCaptureDeviceInput(device: vDevice)
        if session.canAddInput(vInput) { session.addInput(vInput) }
        videoDevice = vDevice

        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String:
                                        kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "video.queue"))
        videoOutput.alwaysDiscardsLateVideoFrames = true
        if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }

        // Audio
        if let aDevice = AVCaptureDevice.default(for: .audio) {
            let aInput = try AVCaptureDeviceInput(device: aDevice)
            if session.canAddInput(aInput) { session.addInput(aInput) }
            audioDevice = aDevice
        }
        audioOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "audio.queue"))
        if session.canAddOutput(audioOutput) { session.addOutput(audioOutput) }

        // Orientation
        for connection in videoOutput.connections {
            if connection.isVideoOrientationSupported { connection.videoOrientation = .landscapeRight }
        }

        session.commitConfiguration()
    }

    private func selectVideoDevice(back: Bool) -> AVCaptureDevice? {
        let position: AVCaptureDevice.Position = back ? .back : .front
        let discovery = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .builtInUltraWideCamera, .builtInDualWideCamera],
                                                         mediaType: .video,
                                                         position: position)
        return discovery.devices.first ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension CameraPublisherViewModel: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if output === videoOutput {
            sender.sendVideo(sampleBuffer: sampleBuffer)
        } else if output === audioOutput {
            if !isMicMuted { sender.sendAudio(sampleBuffer: sampleBuffer) }
        }
    }
}

// MARK: - SwiftUI View
struct CameraPublisherView: View {
    @StateObject private var vm: CameraPublisherViewModel
    @State private var previewLayer = AVCaptureVideoPreviewLayer()
    @State private var hasAutoStarted = false
    private let autoStartPublishing: Bool

    init(sender: MediaSender, autoStartPublishing: Bool = false) {
        _vm = StateObject(wrappedValue: CameraPublisherViewModel(sender: sender))
        self.autoStartPublishing = autoStartPublishing
    }

    var body: some View {
        ZStack {
            PreviewLayerView(previewLayer: $previewLayer)
                .ignoresSafeArea()

            VStack {
                HStack {
                    statusPill(vm.connectionState)
                    Spacer()
                    Button(action: { vm.flipCamera(previewLayer: previewLayer) }) {
                        label(icon: "camera.rotate", text: "Flip")
                    }
                    Button(action: vm.toggleTorch) {
                        label(icon: vm.torchOn ? "flashlight.on.fill" : "flashlight.off.fill", text: "Torch")
                    }
                }
                .padding(.horizontal, 16).padding(.top, 14)

                Spacer()

                HStack(spacing: 14) {
                    Button(action: { vm.isMicMuted.toggle() }) {
                        circleButton(icon: vm.isMicMuted ? "mic.slash.fill" : "mic.fill", destructive: vm.isMicMuted)
                    }
                    Button(action: { vm.pushToTalk(true); DispatchQueue.main.asyncAfter(deadline: .now()+0.2){ vm.pushToTalk(false) } }) {
                        circleButton(icon: "waveform.circle")
                    }
                    Button(action: { vm.isPublishing ? vm.stopPublishing() : vm.startPublishing() }) {
                        circleButton(icon: vm.isPublishing ? "stop.fill" : "record.circle", accent: !vm.isPublishing)
                    }
                }
                .padding(.bottom, 22)
            }
        }
        .onAppear {
            Task {
                await vm.configureAndStartPreview(on: previewLayer)
                if autoStartPublishing && !hasAutoStarted {
                    hasAutoStarted = true
                    vm.startPublishing()
                }
            }
        }
        .onDisappear { vm.stopPublishing() }
        .preferredColorScheme(.dark)
    }

    // UI helpers
    private func label(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.callout.bold())
            Text(text).font(.callout.bold())
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.black.opacity(0.35)).clipShape(Capsule()).foregroundStyle(.white)
    }

    private func circleButton(icon: String, destructive: Bool = false, accent: Bool = false) -> some View {
        Image(systemName: icon)
            .font(.title2.bold())
            .foregroundStyle(.white)
            .frame(width: 56, height: 56)
            .background(
                Circle().fill(destructive ? Color.red.opacity(0.9) : (accent ? Color.green.opacity(0.9) : Color.white.opacity(0.15)))
            )
    }

    private func statusPill(_ text: String) -> some View {
        Text(text)
            .font(.caption.bold())
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(.black.opacity(0.35)).clipShape(Capsule()).foregroundStyle(.white)
    }
}

// MARK: - Preview layer host
struct PreviewLayerView: UIViewRepresentable {
    @Binding var previewLayer: AVCaptureVideoPreviewLayer
    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        previewLayer.videoGravity = .resizeAspectFill
        v.layer.addSublayer(previewLayer)
        return v
    }
    func updateUIView(_ uiView: UIView, context: Context) {
        previewLayer.frame = uiView.bounds
    }
}

// MARK: - Example wiring from your Connectivity Manager
/*
 // When pairing succeeds and you create your networking stack:

 struct WebRTCWhipSender: MediaSender {
     let connectionStateSubject = CurrentValueSubject<String, Never>("Connecting")
     var connectionStatePublisher: AnyPublisher<String, Never> { connectionStateSubject.eraseToAnyPublisher() }

     func startPublishing() async throws {
         // Create peer connection, add tracks, do WHIP POST, etc.
         connectionStateSubject.send("Connected")
     }
     func stopPublishing() { /* close PC/tracks */ }
     func sendVideo(sampleBuffer: CMSampleBuffer) { /* pass to capturer */ }
     func sendAudio(sampleBuffer: CMSampleBuffer) { /* pass to audio track */ }
     func setReturnAudioEnabled(_ enabled: Bool) { /* subscribe/unsubscribe remote audio */ }
     func pushToTalk(_ isDown: Bool) { /* gate iPad mic to downlink if you implement server-side talkback gating */ }
 }

 // Present the view from your sheet or navigation stack:
 let sender = WebRTCWhipSender(/* init with WHIP URL, token, ICE, etc. */)
 let view = CameraPublisherView(sender: sender)
 */
