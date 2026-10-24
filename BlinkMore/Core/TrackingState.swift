import Foundation

enum TrackingPhase: String {
    case starting, calibrating, tracking, eyesClosed, noFace, multipleFaces
    case lowQuality, delayed, paused, cameraDenied, cameraMissing, cameraError

    var title: String {
        switch self {
        case .starting: return "Starting camera"
        case .calibrating: return "Calibrating eyes"
        case .tracking: return "Tracking"
        case .eyesClosed: return "Eye closure"
        case .noFace: return "Face not visible"
        case .multipleFaces: return "Multiple faces"
        case .lowQuality: return "Adjust your camera angle"
        case .delayed: return "Processing delayed"
        case .paused: return "Paused"
        case .cameraDenied: return "Camera access required"
        case .cameraMissing: return "Camera unavailable"
        case .cameraError: return "Camera needs attention"
        }
    }

    var detail: String {
        switch self {
        case .starting: return "Starting local camera processing."
        case .calibrating: return "Face the camera and blink normally."
        case .tracking: return "Both eyes visible."
        case .eyesClosed: return "Detected closure clears the reminder."
        case .noFace: return "Move into view to resume."
        case .multipleFaces: return "Waiting for an unambiguous primary face."
        case .lowQuality: return "Face the camera in even light and keep both eyes visible."
        case .delayed: return "Waiting for fresh eye data."
        case .paused: return "Camera off. Resumes after five minutes."
        case .cameraDenied: return "Allow camera access in System Settings."
        case .cameraMissing: return "Connect a camera or choose another camera in Settings."
        case .cameraError: return "Pause and resume monitoring, or choose another camera."
        }
    }
}

struct TrackingFrame {
    var phase: TrackingPhase = .starting
    var timestamp: Double = 0
    var left: Double = 0
    var right: Double = 0
    var calibration: Double = 0
    var openSeconds: Double = 0
    var trackedDelta: Double = 0
    var asymmetry: Double = 0
    var closedMask: UInt32 = 0
    var events: UInt32 = 0
    var calibrated = false
    var latencyMs: Double = 0
    var fps: Double = 0
    var dropped = 0
    var qualityNote = ""
    var leftContour: [CGPoint] = []
    var rightContour: [CGPoint] = []
    var leftAperture: Double = 0
    var rightAperture: Double = 0
    var faceWidth: Double = 0
    var faceHeight: Double = 0
    var faceConfidence: Double = 0
}
