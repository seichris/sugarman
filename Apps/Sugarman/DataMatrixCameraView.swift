// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import SensorOnboarding
import SwiftUI

#if os(iOS) && canImport(AVFoundation) && canImport(UIKit) && canImport(Vision) && !targetEnvironment(simulator)
import AVFoundation
import UIKit
import Vision

/// Live camera Data Matrix scanner (QR fallback). Simulator builds omit this
/// type and keep PhotosPicker / file import. Payloads are not stored until
/// the onboarding confirmation dialog.
struct DataMatrixCameraView: UIViewControllerRepresentable {
    var onPayload: (String) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> DataMatrixCaptureController {
        let controller = DataMatrixCaptureController()
        controller.onPayload = onPayload
        controller.onCancel = onCancel
        return controller
    }

    func updateUIViewController(_ uiViewController: DataMatrixCaptureController, context: Context) {
        _ = uiViewController
        _ = context
    }
}

@MainActor
final class DataMatrixCaptureController: UIViewController {
    var onPayload: ((String) -> Void)?
    var onCancel: (() -> Void)?

    private let previewLayer = AVCaptureVideoPreviewLayer()
    private var captureEngine: DataMatrixCaptureEngine?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)

        let cancel = UIButton(type: .system)
        cancel.setTitle(String(localized: "sensor.camera_cancel"), for: .normal)
        cancel.setTitleColor(.white, for: .normal)
        cancel.translatesAutoresizingMaskIntoConstraints = false
        cancel.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        view.addSubview(cancel)
        NSLayoutConstraint.activate([
            cancel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            cancel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
        ])

        let engine = DataMatrixCaptureEngine(
            onPayload: { [weak self] payload in
                self?.onPayload?(payload)
            },
            onFailure: { [weak self] in
                self?.onCancel?()
            }
        )
        captureEngine = engine
        previewLayer.session = engine.session

        AVCaptureDevice.requestAccess(for: .video) { [engine] granted in
            if granted {
                engine.start()
            } else {
                engine.reportFailure()
            }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        captureEngine?.stop()
    }

    @objc private func cancelTapped() {
        onCancel?()
    }

}

/// AVFoundation and Vision work is confined to private serial queues instead
/// of the main-actor view controller. The callbacks cross back to MainActor.
private final class DataMatrixCaptureEngine: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let session = AVCaptureSession()

    private let output = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "app.sugarman.ios.camera")
    private let frameQueue = DispatchQueue(label: "app.sugarman.ios.camera.frames")
    private let onPayload: @MainActor @Sendable (String) -> Void
    private let onFailure: @MainActor @Sendable () -> Void
    /// Accessed only on `frameQueue`.
    private var didEmit = false
    /// Accessed only on `sessionQueue`.
    private var configured = false
    /// Accessed only on `sessionQueue`. Prevents a late camera-permission
    /// callback from starting capture after the sheet has been dismissed.
    private var shouldRun = true

    init(
        onPayload: @escaping @MainActor @Sendable (String) -> Void,
        onFailure: @escaping @MainActor @Sendable () -> Void
    ) {
        self.onPayload = onPayload
        self.onFailure = onFailure
        super.init()
    }

    func start() {
        sessionQueue.async {
            guard self.shouldRun else { return }
            if self.configured {
                if !self.session.isRunning {
                    self.session.startRunning()
                }
                return
            }
            self.session.beginConfiguration()
            self.session.sessionPreset = .high
            guard
                let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                let input = try? AVCaptureDeviceInput(device: device),
                self.session.canAddInput(input)
            else {
                self.session.commitConfiguration()
                self.reportFailure()
                return
            }
            self.session.addInput(input)
            self.output.alwaysDiscardsLateVideoFrames = true
            self.output.setSampleBufferDelegate(self, queue: self.frameQueue)
            guard self.session.canAddOutput(self.output) else {
                self.session.commitConfiguration()
                self.reportFailure()
                return
            }
            self.session.addOutput(self.output)
            self.session.commitConfiguration()
            self.configured = true
            self.session.startRunning()
        }
    }

    func stop() {
        sessionQueue.async {
            self.shouldRun = false
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }

    func reportFailure() {
        Task { @MainActor [onFailure] in
            onFailure()
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        _ = output
        _ = connection
        guard !didEmit, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        let request = VNDetectBarcodesRequest { [weak self] request, _ in
            let observations = request.results as? [VNBarcodeObservation] ?? []
            guard let payload = BarcodeSymbologyPolicy.preferredPayload(from: observations) else {
                return
            }
            self?.emit(payload)
        }
        request.symbologies = BarcodeSymbologyPolicy.liveCapture
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right, options: [:])
        try? handler.perform([request])
    }

    private func emit(_ payload: String) {
        guard !didEmit else { return }
        didEmit = true
        let payloadHandler = onPayload
        sessionQueue.async { [self, payloadHandler] in
            if self.session.isRunning {
                self.session.stopRunning()
            }
            Task { @MainActor in
                payloadHandler(payload)
            }
        }
    }
}
#endif
