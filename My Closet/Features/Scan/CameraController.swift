import AVFoundation
import SwiftUI
import UIKit

/// Owns the back camera for the scan screen: asks for permission, runs the session and takes
/// one photo at a time. The simulator has no camera, so it reports `.unavailable` there.
@Observable
final class CameraController {
    enum Status { case starting, running, denied, unavailable }

    private(set) var status: Status = .starting
    @ObservationIgnored let capture = CaptureSession()

    func start() async {
        guard CaptureSession.hasCamera else {
            status = .unavailable
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else {
                status = .denied
                return
            }
        default:
            status = .denied
            return
        }
        status = await capture.start() ? .running : .unavailable
    }

    func stop() { capture.stop() }

    func takePhoto() async -> UIImage? { await capture.takePhoto() }
}

/// The AVFoundation side, kept off the main actor: every session call runs on its own queue.
nonisolated final class CaptureSession: NSObject, @unchecked Sendable, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "closet.camera.session")
    private var configured = false
    private var pending: CheckedContinuation<UIImage?, Never>?

    static var hasCamera: Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil
    }

    func start() async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                if !configured {
                    guard configure() else {
                        continuation.resume(returning: false)
                        return
                    }
                }
                if !session.isRunning { session.startRunning() }
                continuation.resume(returning: true)
            }
        }
    }

    func stop() {
        queue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    func takePhoto() async -> UIImage? {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                guard session.isRunning, pending == nil else {
                    continuation.resume(returning: nil)
                    return
                }
                pending = continuation
                if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90
                }
                output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
            }
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let image = error == nil ? photo.fileDataRepresentation().flatMap(UIImage.init(data:)) : nil
        queue.async { [self] in
            pending?.resume(returning: image)
            pending = nil
        }
    }

    /// Runs on `queue`.
    private func configure() -> Bool {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device)
        else { return false }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo
        guard session.canAddInput(input), session.canAddOutput(output) else { return false }
        session.addInput(input)
        session.addOutput(output)
        configured = true
        return true
    }
}

/// Live camera feed, filling its frame.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
