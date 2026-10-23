import AVFoundation
import Vision
import AppKit

final class EyeTrackingService: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let sessionQueue = DispatchQueue(label: "com.oxremy.blinkmore.camera", qos: .userInitiated)
    private let videoQueue = DispatchQueue(label: "com.oxremy.blinkmore.inference", qos: .userInitiated)
    private let lock = NSLock()
    private var stopped = false
    private var deliveryPending = false
    private var latestFrame = TrackingFrame()
    private var session: AVCaptureSession?
    private var output: AVCaptureVideoDataOutput?
    private var errorObserver: NSObjectProtocol?
    private let core: OpaquePointer
    private var sensitivity: Double
    private let cameraID: String?
    private let statistics: DailyStatistics
    private let onFrame: (TrackingFrame) -> Void
    private let faceDetection = VNDetectFaceRectanglesRequest()
    private let landmarks = VNDetectFaceLandmarksRequest()
    private let sequence = VNSequenceRequestHandler()
    private var faceTracker: VNTrackObjectRequest?
    private var lastFaceSearch = -Double.infinity
    private var lastProcessed = -Double.infinity
    private var lastFrameTime: Double = 0
    private var fps: Double = 0
    private var dropped = 0

    init(cameraID: String?, sensitivity: Double, statistics: DailyStatistics,
         onFrame: @escaping (TrackingFrame) -> Void) {
        self.cameraID = cameraID; self.sensitivity = sensitivity
        self.statistics = statistics; self.onFrame = onFrame
        guard let core = bm_tracker_new() else { fatalError("Unable to allocate tracking core") }
        self.core = core
        super.init()
        landmarks.constellation = .constellation76Points
        landmarks.preferBackgroundProcessing = false
        faceDetection.preferBackgroundProcessing = false
    }

    deinit { if let observer = errorObserver { NotificationCenter.default.removeObserver(observer) }; bm_tracker_free(core) }

    static func cameras() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external], mediaType: .video, position: .unspecified).devices
    }

    func start() {
        sessionQueue.async {
            guard !self.isStopped else { return }
            let cameras = Self.cameras()
            let selected = self.cameraID.flatMap { id in cameras.first { $0.uniqueID == id } }
            guard let device = self.cameraID == nil ? (cameras.first(where: { $0.position == .front }) ?? cameras.first) : selected else {
                self.deliver(TrackingFrame(phase: .cameraMissing)); return
            }
            do {
                let session = AVCaptureSession()
                session.beginConfiguration()
                if session.canSetSessionPreset(.vga640x480) { session.sessionPreset = .vga640x480 }
                else { session.sessionPreset = .medium }
                let input = try AVCaptureDeviceInput(device: device)
                guard session.canAddInput(input) else { throw CocoaError(.featureUnsupported) }
                session.addInput(input)
                let output = AVCaptureVideoDataOutput()
                output.alwaysDiscardsLateVideoFrames = true
                output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
                output.setSampleBufferDelegate(self, queue: self.videoQueue)
                guard session.canAddOutput(output) else { throw CocoaError(.featureUnsupported) }
                session.addOutput(output)
                if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(0) {
                    connection.videoRotationAngle = 0
                }
                session.commitConfiguration()
                self.errorObserver = NotificationCenter.default.addObserver(forName: .AVCaptureSessionRuntimeError, object: session, queue: nil) { [weak self] _ in
                    self?.deliver(TrackingFrame(phase: .cameraError))
                }
                self.session = session; self.output = output
                guard !self.isStopped else { output.setSampleBufferDelegate(nil, queue: nil); return }
                session.startRunning()
                if !session.isRunning { self.deliver(TrackingFrame(phase: .cameraError)) }
            } catch {
                self.deliver(TrackingFrame(phase: .cameraError))
                NSLog("Camera could not start: %@", error.localizedDescription)
            }
        }
    }

    func stop(completion: (() -> Void)? = nil) {
        lock.lock(); stopped = true; lock.unlock()
        // Retain the service until sample delivery drains, then release it on the main thread.
        sessionQueue.async {
            self.output?.setSampleBufferDelegate(nil, queue: nil)
            if self.session?.isRunning == true { self.session?.stopRunning() }
            self.session = nil; self.output = nil
            if let observer = self.errorObserver { NotificationCenter.default.removeObserver(observer) }; self.errorObserver = nil
            self.videoQueue.async {
                DispatchQueue.main.async { withExtendedLifetime(self) { completion?() } }
            }
        }
    }

    func recalibrate() { videoQueue.async { bm_tracker_reset(self.core) } }
    func setSensitivity(_ value: Double) { videoQueue.async { self.sensitivity = value } }

    private var isStopped: Bool {
        lock.lock(); defer { lock.unlock() }; return stopped
    }

    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        dropped += 1
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard !isStopped, let image = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let now = Self.clock()
        let timestamp = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        guard timestamp.isFinite, now - timestamp < 0.25, now - timestamp >= -0.1 else {
            dropped += 1; missing(.delayed, timestamp: now); return
        }
        guard now - lastProcessed >= 1.0 / 30.0 else { return }
        lastProcessed = now
        autoreleasepool {
            do {
                let handler = VNImageRequestHandler(cvPixelBuffer: image, orientation: .up, options: [:])
                let face: VNFaceObservation
                if faceTracker == nil || now - lastFaceSearch >= 0.7 {
                    try handler.perform([faceDetection])
                    lastFaceSearch = now
                    guard let faces = faceDetection.results, faces.count == 1, let found = faces.first else {
                        faceTracker = nil
                        missing((faceDetection.results?.count ?? 0) > 1 ? .multipleFaces : .noFace, timestamp: timestamp)
                        return
                    }
                    face = found
                    let tracker = VNTrackObjectRequest(detectedObjectObservation: VNDetectedObjectObservation(boundingBox: found.boundingBox))
                    tracker.trackingLevel = .fast
                    faceTracker = tracker
                } else if let tracker = faceTracker {
                    try sequence.perform([tracker], on: image, orientation: .up)
                    guard let observation = tracker.results?.first as? VNDetectedObjectObservation,
                          observation.confidence >= 0.6 else {
                        faceTracker = nil; missing(.noFace, timestamp: timestamp); return
                    }
                    tracker.inputObservation = observation
                    face = VNFaceObservation(boundingBox: observation.boundingBox)
                } else { return }
                landmarks.inputFaceObservations = [face]
                try handler.perform([landmarks])
                guard let measured = landmarks.results?.first,
                      let left = measured.landmarks?.leftEye,
                      let right = measured.landmarks?.rightEye else {
                    faceTracker = nil; missing(.noFace, timestamp: timestamp); return
                }
                guard abs(measured.yaw?.doubleValue ?? 0) <= 0.65,
                      abs(measured.pitch?.doubleValue ?? 0) <= 0.55 else {
                    missing(.lowQuality, timestamp: timestamp); return
                }
                let finished = Self.clock()
                guard finished - timestamp <= 0.25 else {
                    dropped += 1; missing(.delayed, timestamp: timestamp); return
                }
                let lp = left.normalizedPoints.map { BMPoint(x: Double($0.x), y: Double($0.y)) }
                let rp = right.normalizedPoints.map { BMPoint(x: Double($0.x), y: Double($0.y)) }
                let box = measured.boundingBox
                let result = lp.withUnsafeBufferPointer { l in rp.withUnsafeBufferPointer { r in
                    bm_tracker_process(core, BMInput(left: l.baseAddress, left_count: UInt32(l.count),
                        right: r.baseAddress, right_count: UInt32(r.count),
                        face_width: box.width * Double(CVPixelBufferGetWidth(image)),
                        face_height: box.height * Double(CVPixelBufferGetHeight(image)),
                        timestamp: timestamp, confidence: Double(measured.confidence), sensitivity: sensitivity))
                } }
                if lastFrameTime > 0 && timestamp > lastFrameTime {
                    let instant = min(60, 1 / (timestamp - lastFrameTime))
                    fps = fps == 0 ? instant : fps * 0.85 + instant * 0.15
                }
                lastFrameTime = timestamp
                var frame = TrackingFrame()
                frame.phase = [0: TrackingPhase.noFace, 1: .calibrating, 2: .tracking, 3: .eyesClosed, 4: .lowQuality, 5: .delayed][Int(result.phase)] ?? .lowQuality
                frame.timestamp = timestamp; frame.left = result.left_openness; frame.right = result.right_openness
                frame.calibration = result.calibration; frame.openSeconds = result.open_seconds
                frame.trackedDelta = result.tracked_delta; frame.asymmetry = result.asymmetry
                frame.closedMask = result.closed_mask; frame.events = result.flags; frame.calibrated = result.flags & 2 != 0
                frame.latencyMs = (finished - timestamp) * 1000; frame.fps = fps; frame.dropped = dropped
                if CommandLine.arguments.contains("--diagnose") {
                    frame.qualityNote = "core=\(result.phase) confidence=\(measured.confidence) contours=\(lp.count)/\(rp.count) face=\(Int(box.width * Double(CVPixelBufferGetWidth(image))))x\(Int(box.height * Double(CVPixelBufferGetHeight(image))))"
                }
                statistics.record(frame)
                deliver(frame)
            } catch {
                faceTracker = nil; missing(.lowQuality, timestamp: timestamp)
            }
        }
    }

    private func missing(_ phase: TrackingPhase, timestamp: Double) {
        let result = bm_tracker_process(core, BMInput(left: nil, left_count: 0, right: nil, right_count: 0,
            face_width: 0, face_height: 0, timestamp: timestamp, confidence: 0, sensitivity: sensitivity))
        var frame = TrackingFrame(phase: phase)
        frame.timestamp = timestamp; frame.calibration = result.calibration
        frame.dropped = dropped; frame.fps = fps
        frame.latencyMs = max(0, (Self.clock() - timestamp) * 1000)
        deliver(frame)
    }

    private func deliver(_ frame: TrackingFrame) {
        lock.lock()
        guard !stopped else { lock.unlock(); return }
        latestFrame = frame
        guard !deliveryPending else { lock.unlock(); return }
        deliveryPending = true; lock.unlock()
        // One pending main-thread delivery keeps a busy UI from building a frame backlog.
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.lock.lock(); let value = self.latestFrame; let stopped = self.stopped
            self.deliveryPending = false; self.lock.unlock()
            if !stopped { self.onFrame(value) }
        }
    }

    static func clock() -> Double { CMTimeGetSeconds(CMClockGetTime(CMClockGetHostTimeClock())) }
}
