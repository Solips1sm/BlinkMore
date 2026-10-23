import Foundation

enum TrackingPhase: String {
    case starting, calibrating, tracking, eyesClosed, noFace, multipleFaces
    case lowQuality, delayed, paused, cameraDenied, cameraMissing, cameraError

    var title: String {
        switch self {
        case .starting: return "Starting camera"
        case .calibrating: return "Calibrating your eyes"
        case .tracking: return "Tracking comfortably"
        case .eyesClosed: return "Eyes resting"
        case .noFace: return "Looking for you"
        case .multipleFaces: return "More than one face"
        case .lowQuality: return "Adjust your camera angle"
        case .delayed: return "Waiting for a fresh frame"
        case .paused: return "Monitoring paused"
        case .cameraDenied: return "Camera access required"
        case .cameraMissing: return "Camera unavailable"
        case .cameraError: return "Camera needs attention"
        }
    }

    var detail: String {
        switch self {
        case .starting: return "Your camera is starting. Everything stays on this Mac."
        case .calibrating: return "Look toward the camera with your eyes naturally open. Blink normally."
        case .tracking: return "Both eyes are tracked. A gentle fade reminds you to blink."
        case .eyesClosed: return "The reminder clears as soon as your eyes close."
        case .noFace: return "Move into view. Reminders wait until your eyes are visible."
        case .multipleFaces: return "Monitoring waits until only your face is in view."
        case .lowQuality: return "Face the camera in even light and keep both eyes visible."
        case .delayed: return "Processing is busy. Old frames never trigger a reminder."
        case .paused: return "Your camera is off. Monitoring resumes automatically after the pause."
        case .cameraDenied: return "Allow BlinkMore in System Settings to begin monitoring."
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
}
