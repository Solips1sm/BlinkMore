import AppKit

final class DashboardDocumentStack: NSStackView {
    override var isFlipped: Bool { true }
}

func dashboardLabel(_ text: String, size: CGFloat = 14, weight: NSFont.Weight = .regular, secondary: Bool = false) -> NSTextField {
    let label = NSTextField(labelWithString: text)
    label.font = .systemFont(ofSize: size, weight: weight)
    label.textColor = secondary ? .secondaryLabelColor : .labelColor
    label.lineBreakMode = .byTruncatingTail
    label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    return label
}

func dashboardStack(_ views: [NSView], horizontal: Bool = false, spacing: CGFloat = 10) -> NSStackView {
    let stack = NSStackView(views: views)
    stack.orientation = horizontal ? .horizontal : .vertical
    stack.alignment = horizontal ? .centerY : .leading
    stack.spacing = spacing
    return stack
}

final class DashboardCard: NSView {
    init(_ content: NSView) {
        super.init(frame: .zero)
        wantsLayer = true; layer?.cornerRadius = 16; layer?.borderWidth = 0.5
        content.translatesAutoresizingMaskIntoConstraints = false; addSubview(content)
        NSLayoutConstraint.activate([content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            content.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12)])
        paint()
    }
    required init?(coder: NSCoder) { nil }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); paint() }
    private func paint() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
            layer?.borderColor = NSColor.separatorColor.cgColor
        }
    }
}

final class EyePairView: NSView {
    var left: Double = 1
    var right: Double = 1
    var active = false
    override var intrinsicContentSize: NSSize { NSSize(width: 114, height: 42) }
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .image }
    override func draw(_ dirtyRect: NSRect) {
        let color = active ? NSColor.controlAccentColor : .tertiaryLabelColor
        color.setStroke(); color.setFill()
        let width = (bounds.width - 16) / 2
        for (index, openness) in [left, right].enumerated() {
            let x = CGFloat(index) * (width + 16)
            let center = bounds.midY
            let height = active ? max(0.5, min(1, openness) * 13) : 3
            let path = NSBezierPath(); path.lineWidth = 1.6
            path.move(to: NSPoint(x: x + 2, y: center))
            path.curve(to: NSPoint(x: x + width - 2, y: center), controlPoint1: NSPoint(x: x + width * 0.3, y: center + height), controlPoint2: NSPoint(x: x + width * 0.7, y: center + height))
            path.curve(to: NSPoint(x: x + 2, y: center), controlPoint1: NSPoint(x: x + width * 0.7, y: center - height), controlPoint2: NSPoint(x: x + width * 0.3, y: center - height))
            path.stroke()
            if height > 4 { NSBezierPath(ovalIn: NSRect(x: x + width / 2 - 3, y: center - 3, width: 6, height: 6)).fill() }
        }
    }
}

final class WeekChartView: NSView {
    var week: [[String: Any]] = [] {
        didSet {
            needsDisplay = true
            let text = week.map { day in
                let rate = (day["blinkRate"] as? Double).map { String(format: "%.1f per minute", $0) } ?? "no data"
                return "\(day["day"] as? String ?? ""): \(rate)"
            }.joined(separator: ", ")
            setAccessibilityLabel("Daily blink rate"); setAccessibilityValue(text)
        }
    }
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .image }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 96) }
    override func draw(_ dirtyRect: NSRect) {
        guard !week.isEmpty else { return }
        let rates = week.map { $0["blinkRate"] as? Double ?? 0 }
        let maximum = max(1, rates.max() ?? 0)
        let column = bounds.width / CGFloat(week.count)
        for (i, day) in week.enumerated() {
            let x = CGFloat(i) * column
            let hasData = day["blinkRate"] is Double
            let height = hasData ? max(2, rates[i] / maximum * (bounds.height - 54)) : 2
            (hasData ? i == week.count - 1 ? NSColor.controlAccentColor : NSColor.controlAccentColor.withAlphaComponent(0.35) : NSColor.separatorColor).setFill()
            NSBezierPath(roundedRect: NSRect(x: x + column * 0.32, y: 27, width: column * 0.36, height: height), xRadius: 3, yRadius: 3).fill()
            let style = NSMutableParagraphStyle(); style.alignment = .center
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .medium), .foregroundColor: NSColor.labelColor, .paragraphStyle: style]
            let rate = hasData ? String(format: "%.1f", rates[i]) : "—"
            (rate as NSString).draw(in: NSRect(x: x, y: bounds.height - 22, width: column, height: 20), withAttributes: attributes)
            let key = day["day"] as? String ?? ""
            let date = Self.dateFormatter.date(from: key)
            let name = date.map { Self.weekdayFormatter.string(from: $0) } ?? ""
            (name as NSString).draw(in: NSRect(x: x, y: 2, width: column, height: 20), withAttributes: attributes.merging([.foregroundColor: NSColor.secondaryLabelColor]) { _, new in new })
        }
    }
    private static let dateFormatter: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f }()
    private static let weekdayFormatter: DateFormatter = { let f = DateFormatter(); f.dateFormat = "EEE"; return f }()
}
