import AVFoundation
import Vision
import AppKit

final class EyeTrackingService: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let sessionQueue = DispatchQueue(label: "com.oxremy.blinkmore.camera", qos: .userInitiated)
    private let captureQueue = DispatchQueue(label: "com.oxremy.blinkmore.capture", qos: .userInitiated)
    private let videoQueue = DispatchQueue(label: "com.oxremy.blinkmore.inference", qos: .userInitiated)
    private let lock = NSLock()
    private var stopped = false
    private var deliveryPending = false
    private var pendingImage: (CVPixelBuffer, Double)?
    private var inferenceScheduled = false
    private var captureDrops = 0
    private var delivery = TrackingDelivery()
    let motion = MotionTrace()
    private var faceCount = 0
    private var sceneTimestamp = 0.0
    private var ownerBox: CGRect?
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
    private var lastFaceTrackFinished = -Double.infinity
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
                self.videoQueue.async { self.deliver(TrackingFrame(phase: .cameraMissing)) }; return
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
                output.setSampleBufferDelegate(self, queue: self.captureQueue)
                guard session.canAddOutput(output) else { throw CocoaError(.featureUnsupported) }
                session.addOutput(output)
                if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(0) {
                    connection.videoRotationAngle = 0
                }
                session.commitConfiguration()
                self.errorObserver = NotificationCenter.default.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil) { [weak self] _ in
                    self?.videoQueue.async { self?.deliver(TrackingFrame(phase: .cameraError)) }
                }
                self.session = session; self.output = output
                guard !self.isStopped else { output.setSampleBufferDelegate(nil, queue: nil); return }
                session.startRunning()
                // Match the existing inference budget at the camera, avoiding discarded captures.
                if session.isRunning, let duration = Self.captureDuration(ranges: device.activeFormat.videoSupportedFrameRateRanges.map({ $0.minFrameRate...$0.maxFrameRate })) {
                    do {
                        try device.lockForConfiguration()
                        defer { device.unlockForConfiguration() }
                        device.activeVideoMinFrameDuration = duration
                        device.activeVideoMaxFrameDuration = duration
                    } catch { NSLog("Camera keeps its default frame rate: %@", error.localizedDescription) }
                }
                if !session.isRunning { self.videoQueue.async { self.deliver(TrackingFrame(phase: .cameraError)) } }
            } catch {
                self.videoQueue.async { self.deliver(TrackingFrame(phase: .cameraError)) }
                NSLog("Camera could not start: %@", error.localizedDescription)
            }
        }
    }

    func stop(completion: (() -> Void)? = nil) {
        lock.lock(); stopped = true; pendingImage = nil; lock.unlock()
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
        lock.lock(); captureDrops += 1; lock.unlock()
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let image = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        enqueue(image, timestamp: CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer)))
    }

    func enqueue(_ image: CVPixelBuffer, timestamp: Double) {
        lock.lock()
        guard !stopped else { lock.unlock(); return }
        if pendingImage != nil { captureDrops += 1 }
        pendingImage = (image, timestamp)
        guard !inferenceScheduled else { lock.unlock(); return }
        inferenceScheduled = true; lock.unlock()
        videoQueue.async { self.consumeLatest() }
    }

    private func consumeLatest() {
        lock.lock()
        guard !stopped, let next = pendingImage else {
            inferenceScheduled = false; pendingImage = nil; lock.unlock(); return
        }
        pendingImage = nil; lock.unlock()
        process(next.0, timestamp: next.1)
        // Each inference takes the newest capture, rather than the first frame queued while busy.
        videoQueue.async { self.consumeLatest() }
    }

    private var totalDropped: Int {
        lock.lock(); defer { lock.unlock() }; return dropped + captureDrops
    }

    private func process(_ image: CVPixelBuffer, timestamp: Double) {
        guard !isStopped else { return }
        let now = Self.clock()
        guard timestamp.isFinite, now - timestamp < 0.1, now - timestamp >= -0.1 else {
            dropped += 1; missing(.delayed, timestamp: timestamp.isFinite ? timestamp : now); return
        }
        // Allow capture jitter around 15 Hz without dropping every other camera sample.
        guard now - lastProcessed >= 1.0 / 18.0 else { return }
        lastProcessed = now
        // Search at 5 Hz while absent, then return to full eye tracking as soon as a face appears.
        guard faceTracker != nil || now - lastFaceSearch >= 0.2 else { return }
        autoreleasepool {
            do {
                let handler = VNImageRequestHandler(cvPixelBuffer: image, orientation: .up, options: [:])
                let face: VNFaceObservation
                var locationPass = "cached"
                if faceTracker == nil || now - lastFaceSearch >= 0.7 {
                    locationPass = "search"
                    lastFaceSearch = now
                    try handler.perform([faceDetection])
                    let imageSize = CGSize(width: CVPixelBufferGetWidth(image), height: CVPixelBufferGetHeight(image))
                    let faces = FaceSelection.qualified(faceDetection.results ?? [], imageSize: imageSize)
                    faceCount = faces.count; sceneTimestamp = timestamp
                    let selection = FaceSelection.choose(faces, imageSize: imageSize)
                    switch selection {
                    case .none:
                        faceTracker = nil; resetOwner(timestamp: timestamp); missing(.noFace, timestamp: timestamp); return
                    case .ambiguous:
                        faceTracker = nil; resetOwner(timestamp: timestamp); missing(.multipleFaces, timestamp: timestamp); return
                    case .selected(let found):
                        if let previous = ownerBox, !FaceSelection.continuous(previous, found.boundingBox) {
                            bm_tracker_reset(core); statistics.cancelCheck(now: timestamp)
                        }
                        face = found; ownerBox = found.boundingBox
                    }
                    let tracker = VNTrackObjectRequest(detectedObjectObservation: VNDetectedObjectObservation(boundingBox: face.boundingBox))
                    tracker.trackingLevel = .fast
                    faceTracker = tracker
                    lastFaceTrackFinished = Self.clock()
                } else if let tracker = faceTracker {
                    if now - lastFaceTrackFinished >= 0.2 {
                        locationPass = "track"
                        try sequence.perform([tracker], on: image, orientation: .up)
                        guard let observation = tracker.results?.first as? VNDetectedObjectObservation,
                              observation.confidence >= 0.6 else {
                            faceTracker = nil; missing(.noFace, timestamp: timestamp); return
                        }
                        tracker.inputObservation = observation
                        ownerBox = observation.boundingBox
                        lastFaceTrackFinished = Self.clock()
                    }
                    face = VNFaceObservation(boundingBox: tracker.inputObservation.boundingBox)
                } else { return }
                let landmarkStart = Self.clock()
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
                switch result.phase {
                case 0: frame.phase = .noFace
                case 1: frame.phase = .calibrating
                case 2: frame.phase = .tracking
                case 3: frame.phase = .eyesClosed
                case 5: frame.phase = .delayed
                default: frame.phase = .lowQuality
                }
                frame.timestamp = timestamp; frame.left = result.left_openness; frame.right = result.right_openness
                frame.leftContour = lp.map { CGPoint(x: $0.x, y: $0.y) }
                frame.rightContour = rp.map { CGPoint(x: $0.x, y: $0.y) }
                frame.leftAperture = result.left_ratio; frame.rightAperture = result.right_ratio
                frame.faceWidth = box.width * Double(CVPixelBufferGetWidth(image))
                frame.faceHeight = box.height * Double(CVPixelBufferGetHeight(image))
                frame.faceConfidence = Double(measured.confidence)
                frame.calibration = result.calibration; frame.openSeconds = result.open_seconds
                frame.trackedDelta = result.tracked_delta; frame.asymmetry = result.asymmetry
                frame.closedMask = result.closed_mask; frame.events = result.flags; frame.calibrated = result.flags & 2 != 0
                frame.latencyMs = (finished - timestamp) * 1000; frame.fps = fps; frame.dropped = totalDropped
                if CommandLine.arguments.contains("--diagnose") {
                    frame.qualityNote = "locate=\(locationPass) core=\(result.phase) confidence=\(measured.confidence) contours=\(lp.count)/\(rp.count) face=\(Int(box.width * Double(CVPixelBufferGetWidth(image))))x\(Int(box.height * Double(CVPixelBufferGetHeight(image)))) inputMs=\(Int((now - timestamp) * 1000)) inferenceMs=\(Int((finished - now) * 1000)) landmarksMs=\(Int((finished - landmarkStart) * 1000))"
                }
                statistics.record(frame)
                deliver(frame)
            } catch {
                faceTracker = nil; missing(.cameraError, timestamp: timestamp, note: error.localizedDescription)
            }
        }
    }

    private func resetOwner(timestamp: Double) {
        guard ownerBox != nil else { return }
        bm_tracker_reset(core); ownerBox = nil; statistics.cancelCheck(now: timestamp)
    }

    private func missing(_ phase: TrackingPhase, timestamp: Double, note: String = "") {
        let result = bm_tracker_invalidate(core)
        var frame = TrackingFrame(phase: phase)
        frame.qualityNote = note
        frame.timestamp = timestamp; frame.calibration = result.calibration
        frame.dropped = totalDropped; frame.fps = fps
        frame.latencyMs = max(0, (Self.clock() - timestamp) * 1000)
        deliver(frame)
    }

    private func deliver(_ input: TrackingFrame) {
        var frame = input
        frame.faceCount = faceCount; frame.sceneTimestamp = sceneTimestamp
        motion.record(frame)
        lock.lock()
        guard !stopped else { lock.unlock(); return }
        delivery.replace(frame)
        guard !deliveryPending else { lock.unlock(); return }
        deliveryPending = true; lock.unlock()
        // One pending main-thread delivery keeps a busy UI from building a frame backlog.
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.lock.lock(); let value = self.delivery.take(); let stopped = self.stopped
            self.deliveryPending = false; self.lock.unlock()
            if !stopped, let value { self.onFrame(value) }
        }
    }

    static func captureDuration(ranges: [ClosedRange<Double>]) -> CMTime? {
        ranges.contains(where: { $0.contains(15) }) ? CMTime(value: 1, timescale: 15) : nil
    }

    static func clock() -> Double { CMTimeGetSeconds(CMClockGetTime(CMClockGetHostTimeClock())) }
}
