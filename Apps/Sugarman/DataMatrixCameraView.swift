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

final class DataMatrixCaptureController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    var onPayload: ((String) -> Void)?
    var onCancel: (() -> Void)?

    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "app.sugarman.ios.camera")
    private let frameQueue = DispatchQueue(label: "app.sugarman.ios.camera.frames")
    private var didEmit = false
    private let previewLayer = AVCaptureVideoPreviewLayer()

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

        AVCaptureDevice.requestAccess(for: .video) { granted in
            if granted {
                self.configureSession()
            } else {
                DispatchQueue.main.async {
                    self.onCancel?()
                }
            }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sessionQueue.async {
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }

    @objc private func cancelTapped() {
        onCancel?()
    }

    private func configureSession() {
        sessionQueue.async {
            self.session.beginConfiguration()
            self.session.sessionPreset = .high
            guard
                let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                let input = try? AVCaptureDeviceInput(device: device),
                self.session.canAddInput(input)
            else {
                self.session.commitConfiguration()
                DispatchQueue.main.async {
                    self.onCancel?()
                }
                return
            }
            self.session.addInput(input)
            self.output.alwaysDiscardsLateVideoFrames = true
            self.output.setSampleBufferDelegate(self, queue: self.frameQueue)
            if self.session.canAddOutput(self.output) {
                self.session.addOutput(self.output)
            }
            self.session.commitConfiguration()
            DispatchQueue.main.async {
                self.previewLayer.session = self.session
            }
            self.session.startRunning()
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
        sessionQueue.async {
            guard !self.didEmit else { return }
            self.didEmit = true
            if self.session.isRunning {
                self.session.stopRunning()
            }
            DispatchQueue.main.async {
                self.onPayload(payload)
            }
        }
    }
}
#endif
