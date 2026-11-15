import SwiftUI
import AppKit

enum AppTheme {
    static let blue = Color(red: 0.23, green: 0.55, blue: 1.0)
    static let teal = Color(red: 0.10, green: 0.70, blue: 0.68)
    static let green = Color(red: 0.22, green: 0.78, blue: 0.45)
    static let orange = Color(red: 1.0, green: 0.58, blue: 0.20)
    static let red = Color(red: 1.0, green: 0.30, blue: 0.30)
    static let purple = Color(red: 0.63, green: 0.44, blue: 1.0)

    static func usage(_ value: Double) -> Color {
        if value >= 0.85 { return red }
        if value >= 0.60 { return orange }
        return blue
    }

    static func temperature(_ celsius: Double) -> Color {
        if celsius >= 85 { return red }
        if celsius >= 70 { return orange }
        return green
    }
}

struct Card<Content: View>: View {
    let title: String
    let icon: String
    let tint: Color
    var subtitle: String?
    private let content: Content

    init(
        title: String,
        icon: String,
        tint: Color,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.tint = tint
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                Spacer(minLength: 8)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.58))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    private let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.6)
                .padding(.leading, 2)
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
        }
    }
}

struct UsageBar: View {
    struct Segment {
        let value: Double
        let color: Color
    }

    let segments: [Segment]
    /// Total capacity. When omitted the sum of segments is used.
    var total: Double = 0
    var trackColor: Color = Color.primary.opacity(0.08)

    var body: some View {
        GeometryReader { geometry in
            let derived = max(segments.reduce(0) { $0 + max(0, $1.value) }, 0.0001)
            let denominator = total > 0 ? total : derived
            HStack(spacing: 1) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    let fraction = min(max(segment.value, 0) / denominator, 1)
                    Rectangle()
                        .fill(segment.color)
                        .frame(width: max(0, geometry.size.width * fraction - 1))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(trackColor)
            .clipShape(Capsule())
        }
        .frame(height: 6)
    }
}

struct Sparkline: View {
    let values: [Double]
    var color: Color = AppTheme.blue
    var fixedMaximum: Double?
    var showArea: Bool = true

    var body: some View {
        GeometryReader { geometry in
            let maximum = max(fixedMaximum ?? values.max() ?? 1, 0.0001)
            let points = makePoints(in: geometry.size, maximum: maximum)

            ZStack {
                if points.count > 1 {
                    if showArea {
                        Path { path in
                            path.addLines(points)
                            path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height))
                            path.addLine(to: CGPoint(x: 0, y: geometry.size.height))
                            path.closeSubpath()
                        }
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.25), color.opacity(0.01)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }
                    Path { path in
                        path.addLines(points)
                    }
                    .stroke(
                        color,
                        style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round)
                    )
                } else if let point = points.first {
                    Circle()
                        .fill(color)
                        .frame(width: 3, height: 3)
                        .position(point)
                }
            }
        }
        .clipped()
    }

    private func makePoints(in size: CGSize, maximum: Double) -> [CGPoint] {
        guard !values.isEmpty else { return [] }
        let inset: CGFloat = 1.5
        let width = max(size.width - inset * 2, 1)
        let height = max(size.height - inset * 2, 1)
        let count = max(values.count - 1, 1)

        return values.enumerated().map { index, value in
            let fraction = min(max(value / maximum, 0), 1)
            let x = inset + width * CGFloat(index) / CGFloat(count)
            let y = inset + height - height * CGFloat(fraction)
            return CGPoint(x: x, y: y)
        }
    }
}

struct CoreBars: View {
    let values: [Double]

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                VStack(spacing: 3) {
                    GeometryReader { geometry in
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                .fill(Color.primary.opacity(0.07))
                            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                .fill(AppTheme.usage(value))
                                .frame(height: max(2, geometry.size.height * CGFloat(max(value, 0.015))))
                        }
                    }
                    .frame(height: 26)

                    Text("\(index + 1)")
                        .font(.system(size: 7, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

struct FanGauge: View {
    let current: Double
    let minimum: Double
    let maximum: Double

    var body: some View {
        GeometryReader { geometry in
            let span = max(maximum - minimum, 1)
            let fraction = min(max((current - minimum) / span, 0), 1)
            let markerX = max(0, min(geometry.size.width - 10, geometry.size.width * CGFloat(fraction) - 5))

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.07))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [AppTheme.teal, AppTheme.orange, AppTheme.red],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(2, geometry.size.width * CGFloat(fraction)))
                Circle()
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .frame(width: 10, height: 10)
                    .overlay(Circle().stroke(AppTheme.teal, lineWidth: 2))
                    .offset(x: markerX)
            }
        }
        .frame(height: 10)
    }
}

struct TempPill: View {
    let label: String
    let celsius: Double?
    let unit: TemperatureUnit

    var body: some View {
        let color = celsius.map { AppTheme.temperature($0) } ?? .secondary
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
            Text(celsius.map { Fmt.temperature($0, unit: unit) } ?? "—")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(color.opacity(0.1))
        )
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .leading)
            Text(value)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
    }
}

struct LegendItem: View {
    let color: Color
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            Text(label)
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
            Spacer(minLength: 2)
            Text(value)
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(.primary)
        }
    }
}

struct FooterIconButton: View {
    let icon: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.primary.opacity(0.07)))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
