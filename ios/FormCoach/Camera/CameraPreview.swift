import SwiftUI
import UIKit
import AVFoundation

@MainActor
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let mirrored: Bool
    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspect // Show the entire portrait frame, including both feet.
        view.mirrored = mirrored
        return view
    }
    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.mirrored = mirrored
        uiView.setNeedsLayout()
    }
    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        var mirrored = true
        override func layoutSubviews() {
            super.layoutSubviews()
            guard let connection = previewLayer.connection else { return }
            if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = mirrored
            }
        }
    }
}
