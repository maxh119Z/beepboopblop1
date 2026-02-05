//
//  PoseCameraViewController.swift
//  bbbabababdfdf
//
//  Created by Max Zhang on 2/4/26.
//

//

import UIKit
import AVFoundation
import Vision

final class PoseCameraViewController: UIViewController {

    // MARK: - Camera
    private let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let videoQueue = DispatchQueue(label: "camera.video.queue", qos: .userInitiated)

    private var previewLayer: AVCaptureVideoPreviewLayer!

    // MARK: - Vision
    private let sequenceHandler = VNSequenceRequestHandler()
    private let poseRequest = VNDetectHumanBodyPoseRequest()

    // MARK: - Drawing
    private let overlayLayer = CAShapeLayer()
    private let jointRadius: CGFloat = 5.0

    // Throttle Vision so it doesn't run on every single frame
    private var lastVisionTime = CFAbsoluteTimeGetCurrent()
    private let visionInterval: CFTimeInterval = 1.0 / 20.0   // ~20 FPS pose

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        setupPreview()
        setupOverlay()
        setupCamera()

        
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer.frame = view.bounds
        overlayLayer.frame = view.bounds
    }

    // MARK: - Setup

    private func setupPreview() {
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = .resizeAspectFill
        if let c = previewLayer.connection, c.isVideoMirroringSupported {
            c.videoOrientation = .portrait
            c.isVideoMirrored = true
        }

        view.layer.addSublayer(previewLayer)
    }

    private func setupOverlay() {
        overlayLayer.frame = view.bounds
        overlayLayer.strokeColor = UIColor.green.cgColor
        overlayLayer.fillColor = UIColor.clear.cgColor
        overlayLayer.lineWidth = 3.0
        view.layer.addSublayer(overlayLayer)
    }

    private func setupCamera() {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .high

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                   for: .video,
                                                   position: .front),
              let input = try? AVCaptureDeviceInput(device: device),
              captureSession.canAddInput(input) else {
            print("Failed to create camera input.")
            captureSession.commitConfiguration()
            return
        }

        captureSession.addInput(input)

        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)

        guard captureSession.canAddOutput(videoOutput) else {
            print("❌ Failed to add video output.")
            captureSession.commitConfiguration()
            return
        }
        captureSession.addOutput(videoOutput)

        // Set orientation (important!)
        if let connection = videoOutput.connection(with: .video) {
            connection.videoOrientation = .portrait
            if connection.isVideoMirroringSupported {
                connection.isVideoMirrored = true
            }
        }


        captureSession.commitConfiguration()
        captureSession.startRunning()
    }

    // MARK: - Pose processing

    private func processPose(pixelBuffer: CVPixelBuffer) {
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastVisionTime >= visionInterval else { return }
        lastVisionTime = now

        do {
            // For back camera portrait, this is usually .right (depends on buffer orientation)
            let orientation: CGImagePropertyOrientation = .leftMirrored
            try sequenceHandler.perform([poseRequest], on: pixelBuffer, orientation: orientation)


            
            guard let observation = poseRequest.results?.first else {
                DispatchQueue.main.async { self.overlayLayer.path = nil }
                return
            }

            let points = try observation.recognizedPoints(.all)

            // Build drawing paths
            let (jointsPath, skeletonPath) = makePaths(from: points)

            DispatchQueue.main.async {
                // Combine joint dots + skeleton lines into one path
                let combined = UIBezierPath()
                combined.append(skeletonPath)
                combined.append(jointsPath)
                self.overlayLayer.path = combined.cgPath
            }

        } catch {
            print("Vision error:", error)
        }
    }

    // MARK: - Drawing helpers

    /// Convert Vision normalized point -> screen point using preview layer
    private func toScreen(_ p: CGPoint) -> CGPoint {
        // Vision points are normalized in image coordinates (0..1).
        // Convert to AVCapturePreviewLayer coordinates:
        let normalized = CGPoint(x: p.x, y: 1.0 - p.y) // flip Y for UIKit coords
        return previewLayer.layerPointConverted(fromCaptureDevicePoint: normalized)
    }

    private func addJoint(_ point: VNRecognizedPoint, to path: UIBezierPath) {
        guard point.confidence > 0.2 else { return }
        let c = toScreen(CGPoint(x: point.x, y: point.y))
        path.append(UIBezierPath(arcCenter: c,
                                 radius: jointRadius,
                                 startAngle: 0,
                                 endAngle: .pi * 2,
                                 clockwise: true))
    }

    private func addBone(_ a: VNRecognizedPoint?,
                         _ b: VNRecognizedPoint?,
                         to path: UIBezierPath) {
        guard let a, let b else { return }
        guard a.confidence > 0.2, b.confidence > 0.2 else { return }

        let pa = toScreen(CGPoint(x: a.x, y: a.y))
        let pb = toScreen(CGPoint(x: b.x, y: b.y))

        path.move(to: pa)
        path.addLine(to: pb)
    }

    private func makePaths(from points: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint])
    -> (UIBezierPath, UIBezierPath) {
        let jointsPath = UIBezierPath()
        let skeletonPath = UIBezierPath()

        // Joints (dots)
        for (_, pt) in points {
            addJoint(pt, to: jointsPath)
        }

        // Convenience getter
        func P(_ name: VNHumanBodyPoseObservation.JointName) -> VNRecognizedPoint? {
            return points[name]
        }

        // Skeleton connections (simple/typical set)
        addBone(P(.neck), P(.root), to: skeletonPath)

        addBone(P(.neck), P(.leftShoulder), to: skeletonPath)
        addBone(P(.leftShoulder), P(.leftElbow), to: skeletonPath)
        addBone(P(.leftElbow), P(.leftWrist), to: skeletonPath)

        addBone(P(.neck), P(.rightShoulder), to: skeletonPath)
        addBone(P(.rightShoulder), P(.rightElbow), to: skeletonPath)
        addBone(P(.rightElbow), P(.rightWrist), to: skeletonPath)

        addBone(P(.root), P(.leftHip), to: skeletonPath)
        addBone(P(.leftHip), P(.leftKnee), to: skeletonPath)
        addBone(P(.leftKnee), P(.leftAnkle), to: skeletonPath)

        addBone(P(.root), P(.rightHip), to: skeletonPath)
        addBone(P(.rightHip), P(.rightKnee), to: skeletonPath)
        addBone(P(.rightKnee), P(.rightAnkle), to: skeletonPath)

        // Optional: connect shoulders + hips for torso box feel
        addBone(P(.leftShoulder), P(.rightShoulder), to: skeletonPath)
        addBone(P(.leftHip), P(.rightHip), to: skeletonPath)

        return (jointsPath, skeletonPath)
    }
}

extension PoseCameraViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        processPose(pixelBuffer: pixelBuffer)
    }
}
