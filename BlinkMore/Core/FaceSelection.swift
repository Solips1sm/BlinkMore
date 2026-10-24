import Vision

enum FaceSelection {
    enum Result { case none, ambiguous, selected(VNFaceObservation) }

    static func choose(_ faces: [VNFaceObservation], imageSize: CGSize) -> Result {
        let candidates = qualified(faces, imageSize: imageSize)
        guard let largest = candidates.first else { return .none }
        // A second measurable face pauses observation instead of mixing people's history.
        if candidates.count > 1 { return .ambiguous }
        return .selected(largest)
    }

    static func qualified(_ faces: [VNFaceObservation], imageSize: CGSize) -> [VNFaceObservation] {
        faces.filter {
            let box = $0.boundingBox
            return $0.confidence.isFinite && $0.confidence >= 0.6 &&
                [box.minX, box.minY, box.width, box.height].allSatisfy(\.isFinite) &&
                box.width * imageSize.width >= 80 && box.height * imageSize.height >= 80
        }
    }

    static func continuous(_ previous: CGRect, _ next: CGRect) -> Bool { overlap(previous, next) >= 0.25 }

    private static func area(_ box: CGRect) -> CGFloat { max(0, box.width) * max(0, box.height) }
    private static func overlap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let intersection = area(a.intersection(b))
        return intersection / max(0.000001, area(a) + area(b) - intersection)
    }
}
