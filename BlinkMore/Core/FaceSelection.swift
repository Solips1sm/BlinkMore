import Vision

enum FaceSelection {
    enum Result { case none, ambiguous, selected(VNFaceObservation) }

    static func choose(_ faces: [VNFaceObservation], previous: CGRect?, imageSize: CGSize) -> Result {
        let candidates = faces.filter {
            let box = $0.boundingBox
            return $0.confidence.isFinite && $0.confidence >= 0.6 &&
                [box.minX, box.minY, box.width, box.height].allSatisfy(\.isFinite) &&
                box.width * imageSize.width >= 80 && box.height * imageSize.height >= 80
        }.sorted { area($0.boundingBox) > area($1.boundingBox) }
        guard let largest = candidates.first else { return .none }
        if let previous = previous {
            let matches = candidates.map { ($0, overlap(previous, $0.boundingBox)) }.sorted { $0.1 > $1.1 }
            if let best = matches.first, best.1 >= 0.25 { return .selected(best.0) }
        }
        if candidates.count > 1, area(candidates[1].boundingBox) >= area(largest.boundingBox) * 0.6 { return .ambiguous }
        return .selected(largest)
    }

    private static func area(_ box: CGRect) -> CGFloat { max(0, box.width) * max(0, box.height) }
    private static func overlap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let intersection = area(a.intersection(b))
        return intersection / max(0.000001, area(a) + area(b) - intersection)
    }
}
