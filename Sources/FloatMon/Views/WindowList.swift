import AppKit
import SwiftUI

struct WindowList: View {
    let windows: [AppWindowInfo]
    let appIcon: NSImage?
    let focusWindow: (AppWindowInfo) -> Void
    let closeWindow: (AppWindowInfo) -> Void

    @State private var hoveringWindowID: Int?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(.white.opacity(0.14))
                .frame(width: 2)
                .padding(.top, 4)
                .padding(.bottom, 6)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(windows) { window in
                    WindowRow(
                        window: window,
                        appIcon: appIcon,
                        isHovering: hoveringWindowID == window.id,
                        focusWindow: { focusWindow(window) },
                        closeWindow: { closeWindow(window) }
                    )
                    .onHover { hovering in
                        withAnimation(.easeOut(duration: 0.12)) {
                            hoveringWindowID = hovering ? window.id : nil
                        }
                    }
                }
            }
        }
        .padding(.leading, 28)
        .padding(.trailing, 18)
    }
}

private struct WindowRow: View {
    let window: AppWindowInfo
    let appIcon: NSImage?
    let isHovering: Bool
    let focusWindow: () -> Void
    let closeWindow: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            AppIconView(image: appIcon, size: 16)

            Text(window.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(1)

            Spacer(minLength: 0)

            Button(action: closeWindow) {
                Image(systemName: "xmark")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.white.opacity(isHovering ? 0.76 : 0.42))
                    .frame(width: 18, height: 18)
                    .background {
                        Circle()
                            .fill(.white.opacity(isHovering ? 0.12 : 0.06))
                    }
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Close \(window.title)")
        }
        .frame(height: 28)
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(rowBackground)
        }
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onTapGesture(count: 2, perform: focusWindow)
        .help("Double-click to show \(window.title)")
    }

    private var rowBackground: Color {
        .white.opacity(isHovering ? 0.075 : 0.035)
    }
}
