import AVFoundation
import SwiftUI
import UIKit

struct QRScanner: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    var onScan: ((String) -> Void)?
    @State private var available = false
    @State private var failed = false
    @State private var denied = false
    @State private var torch = false
    @State private var hasTorch = false
    @State private var result: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if available && !failed {
                CameraPreview(running: phase == .active && result == nil, torch: torch, onTorch: { hasTorch = $0 },
                              onFailure: { failed = true }, onCode: accept)
                    .ignoresSafeArea()
                if result == nil {
                    VStack(spacing: 24) {
                        QRReticle().stroke(.white, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .frame(width: 220, height: 220)
                        Text("Align a QR code inside the frame")
                            .font(.footnote.weight(.semibold))
                            .padding(12).background(.black.opacity(0.72), in: Capsule())
                    }
                    .allowsHitTesting(false)
                }
            } else if denied || failed {
                VStack(spacing: 16) {
                    Image(systemName: "camera.fill").font(.largeTitle)
                    Text(denied ? "Camera access is disabled" : "Camera unavailable").font(.headline)
                    if denied, let settings = URL(string: UIApplication.openSettingsURLString) {
                        Link("Open Settings", destination: settings).buttonStyle(.bordered)
                    }
                }.accessibilityIdentifier("scanner.unavailable")
            } else {
                ProgressView().tint(.white)
            }

            VStack {
                HStack {
                    cameraButton("xmark", "Close") { dismiss() }
                    Spacer()
                    if hasTorch && result == nil && !failed {
                        cameraButton(torch ? "flashlight.on.fill" : "flashlight.off.fill", "Flashlight") { torch.toggle() }
                    }
                }
                Spacer()
                if let result {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("QR code").font(.headline)
                        ScrollView { Text(verbatim: result).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                            .frame(maxHeight: 180)
                        HStack {
                            Button("Copy") { UIPasteboard.general.string = result; Feedback.success() }
                            Spacer()
                            Button("Scan again") { self.result = nil }
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(16).background(Color.vxCard, in: RoundedRectangle(cornerRadius: 16))
                }
            }.padding(24)
        }
        .preferredColorScheme(.dark)
        .task(id: phase) {
            guard phase == .active else { return }
            let status = AVCaptureDevice.authorizationStatus(for: .video)
            let authorized: Bool
            if status == .notDetermined {
                authorized = await AVCaptureDevice.requestAccess(for: .video)
            } else {
                authorized = status == .authorized
            }
            guard !Task.isCancelled else { return }
            denied = !authorized
            available = authorized
        }
    }

    private func accept(_ code: String) {
        guard result == nil else { return }
        result = code
        torch = false
        Feedback.success()
        if let onScan {
            onScan(code)
            dismiss()
        }
    }

    private func cameraButton(_ icon: String, _ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button {
            Feedback.tap()
            action()
        } label: {
            Image(systemName: icon).font(.body.weight(.semibold))
                .frame(width: 48, height: 48)
                .background(.black.opacity(0.72), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
    }
}

private struct QRReticle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for x in [rect.minX, rect.maxX] {
            for y in [rect.minY, rect.maxY] {
                path.move(to: CGPoint(x: x, y: y + (y == rect.minY ? 24 : -24)))
                path.addLine(to: CGPoint(x: x, y: y))
                path.addLine(to: CGPoint(x: x + (x == rect.minX ? 24 : -24), y: y))
            }
        }
        return path
    }
}

private final class CameraLayerView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

private struct CameraPreview: UIViewRepresentable {
    var running: Bool
    var torch: Bool
    let onTorch: (Bool) -> Void
    let onFailure: () -> Void
    let onCode: (String) -> Void

    func makeCoordinator() -> Capture { Capture(onTorch: onTorch, onFailure: onFailure, onCode: onCode) }

    func makeUIView(context: Context) -> CameraLayerView {
        let view = CameraLayerView()
        view.preview.videoGravity = .resizeAspectFill
        view.preview.session = context.coordinator.session
        return view
    }

    func updateUIView(_ view: CameraLayerView, context: Context) {
        context.coordinator.update(running: running, torch: torch)
    }

    static func dismantleUIView(_ view: CameraLayerView, coordinator: Capture) {
        coordinator.update(running: false, torch: false)
    }

    final class Capture: NSObject, AVCaptureMetadataOutputObjectsDelegate, @unchecked Sendable {
        let session = AVCaptureSession()
        private let queue = DispatchQueue(label: "app.veltrix.camera", qos: .userInitiated)
        private let onTorch: (Bool) -> Void
        private let onFailure: () -> Void
        private let onCode: (String) -> Void
        private var device: AVCaptureDevice?
        private var observedError: NSObjectProtocol?
        private var setupAttempted = false
        private var accepting = false

        init(onTorch: @escaping (Bool) -> Void, onFailure: @escaping () -> Void, onCode: @escaping (String) -> Void) {
            self.onTorch = onTorch
            self.onFailure = onFailure
            self.onCode = onCode
            super.init()
            observedError = NotificationCenter.default.addObserver(forName: .AVCaptureSessionRuntimeError, object: session,
                                                                    queue: .main) { [weak self] _ in self?.onFailure() }
        }

        deinit {
            if let observedError { NotificationCenter.default.removeObserver(observedError) }
        }

        func update(running: Bool, torch: Bool) {
            queue.async {
                if running && !self.setupAttempted { self.configure() }
                guard let device = self.device else { return }
                if running && !self.session.isRunning { self.session.startRunning() }
                if !running && self.session.isRunning { self.session.stopRunning() }
                self.accepting = running
                let mode: AVCaptureDevice.TorchMode = running && torch ? .on : .off
                if device.hasTorch, device.isTorchModeSupported(mode), device.torchMode != mode {
                    do {
                        try device.lockForConfiguration()
                        device.torchMode = mode
                        device.unlockForConfiguration()
                    } catch {
                        DispatchQueue.main.async { self.onTorch(false) }
                    }
                }
            }
        }

        private func configure() {
            setupAttempted = true
            let output = AVCaptureMetadataOutput()
            guard let camera = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: camera),
                  session.canAddInput(input), session.canAddOutput(output) else {
                DispatchQueue.main.async { self.onFailure() }
                return
            }
            session.beginConfiguration()
            defer { session.commitConfiguration() }
            session.addInput(input)
            session.addOutput(output)
            guard output.availableMetadataObjectTypes.contains(.qr) else {
                DispatchQueue.main.async { self.onFailure() }
                return
            }
            output.setMetadataObjectsDelegate(self, queue: queue)
            output.metadataObjectTypes = [.qr]
            device = camera
            DispatchQueue.main.async { self.onTorch(camera.hasTorch) }
        }

        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject],
                            from connection: AVCaptureConnection) {
            guard accepting,
                  let code = metadataObjects.compactMap({ ($0 as? AVMetadataMachineReadableCodeObject)?.stringValue }).first else { return }
            accepting = false
            DispatchQueue.main.async { self.onCode(code) }
        }
    }
}
