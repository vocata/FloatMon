import SwiftUI

struct ProcessRow: View {
    let app: AppProcess
    let isExpanded: Bool
    let toggleWindows: () -> Void
    let activate: () -> Void
    let requestForceQuit: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            AppIconView(image: app.icon, size: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text(app.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)

                Text(app.bundleIdentifier ?? "pid \(app.id)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.46))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            ResourceTrendView(samples: app.historySamples)

            ResourceSummaryView(app: app)

            WindowDisclosureView(count: app.windows.count, isExpanded: isExpanded)

            Button {
                requestForceQuit()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(isHovering ? 0.86 : 0.56))
                    .frame(width: 24, height: 24)
                    .background {
                        Circle()
                            .fill(.white.opacity(isHovering ? 0.14 : 0.08))
                    }
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .hoverTooltip("Quit")
        }
        .padding(.horizontal, 12)
        .frame(height: 58)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(rowBackground)
        }
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture(perform: toggleWindows)
        .onTapGesture(count: 2, perform: activate)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
        .help(app.windows.isEmpty ? "Double-click to open \(app.name)" : "Click to show windows, double-click to open \(app.name)")
    }

    private var rowBackground: Color {
        .white.opacity(isHovering ? 0.11 : 0.07)
    }
}

private struct ResourceSummaryView: View {
    let app: AppProcess

    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text(AppFormatters.cpu(app.cpuPercent))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
            Text(AppFormatters.memory(app.memoryBytes))
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.54))
        }
        .monospacedDigit()
        .frame(width: 96, alignment: .trailing)
    }
}

private struct ResourceTrendView: View {
    let samples: [AppResourceSample]

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.white.opacity(0.045))

            GeometryReader { proxy in
                trendPath(
                    values: samples.map(\.memoryBytes).map(Double.init),
                    in: proxy.size,
                    scaleFloor: 512 * 1024 * 1024
                )
                .stroke(.cyan.opacity(0.72), style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))

                trendPath(
                    values: samples.map(\.cpuPercent),
                    in: proxy.size,
                    scaleFloor: 100
                )
                .stroke(.green.opacity(0.82), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
            .padding(5)
        }
        .frame(width: 72, height: 28)
        .help("5-minute trend: green CPU, cyan memory")
    }

    private func trendPath(values: [Double], in size: CGSize, scaleFloor: Double) -> Path {
        guard !values.isEmpty, size.width > 0, size.height > 0 else { return Path() }

        let maxValue = max(scaleFloor, values.max() ?? scaleFloor)
        let points = values.suffix(100)
        let denominator = max(points.count - 1, 1)

        var path = Path()
        for (index, value) in points.enumerated() {
            let x = CGFloat(index) / CGFloat(denominator) * size.width
            let normalized = min(max(value / maxValue, 0), 1)
            let y = size.height - CGFloat(normalized) * size.height
            let point = CGPoint(x: x, y: y)

            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }

        return path
    }
}

private struct WindowDisclosureView: View {
    let count: Int
    let isExpanded: Bool

    var body: some View {
        Group {
            if count > 0 {
                HStack(spacing: 3) {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .foregroundStyle(.white.opacity(0.56))
            } else {
                Color.clear
            }
        }
        .frame(width: 30, alignment: .center)
    }
}
