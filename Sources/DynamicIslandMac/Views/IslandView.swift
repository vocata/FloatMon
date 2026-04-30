import AppKit
import SwiftUI

struct IslandView: View {
    @State var store: ProcessStore
    @State private var expanded = false
    @State private var sortMode: ProcessSortMode = .cpu

    private var activeApp: AppProcess? {
        store.apps.first(where: \.isActive) ?? store.apps.first
    }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.84)) {
                    expanded.toggle()
                }
                currentPanel?.resize(expanded: expanded)
                if expanded {
                    store.refresh()
                }
            } label: {
                collapsedContent
            }
            .buttonStyle(.plain)
            .frame(height: 54)

            if expanded {
                Divider()
                    .overlay(.white.opacity(0.12))
                    .padding(.horizontal, 18)

                ExpandedProcessList(apps: store.apps, sortMode: $sortMode)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            RoundedRectangle(cornerRadius: expanded ? 28 : 27, style: .continuous)
                .fill(.black.opacity(0.92))
                .overlay {
                    RoundedRectangle(cornerRadius: expanded ? 28 : 27, style: .continuous)
                        .stroke(.white.opacity(0.14), lineWidth: 1)
                }
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(expanded ? 0.34 : 0.2), radius: expanded ? 24 : 12, y: 10)
        .padding(.horizontal, 6)
        .padding(.top, 2)
        .padding(.bottom, 6)
    }

    private var collapsedContent: some View {
        HStack(spacing: 12) {
            CameraCapsule()

            if let activeApp {
                AppIconView(image: activeApp.icon, size: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(activeApp.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text("\(AppFormatters.cpu(activeApp.cpuPercent)) CPU · \(AppFormatters.memory(activeApp.memoryBytes))")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                }
            } else {
                Text("No active apps")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }

            Spacer(minLength: 0)

            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.58))
                .frame(width: 24, height: 24)
        }
        .padding(.leading, 16)
        .padding(.trailing, 13)
        .contentShape(Rectangle())
    }

    private var currentPanel: IslandWindow? {
        NSApp.windows.first { $0 is IslandWindow } as? IslandWindow
    }
}

private struct CameraCapsule: View {
    var body: some View {
        Capsule()
            .fill(.black)
            .frame(width: 78, height: 25)
            .overlay(alignment: .trailing) {
                Circle()
                    .fill(.white.opacity(0.08))
                    .frame(width: 9, height: 9)
                    .padding(.trailing, 11)
            }
            .overlay {
                Capsule()
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            }
    }
}

private struct ExpandedProcessList: View {
    let apps: [AppProcess]
    @Binding var sortMode: ProcessSortMode

    private var sortedApps: [AppProcess] {
        sortMode.sorted(apps)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Open Apps")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("\(apps.count)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                SortModeControl(selection: $sortMode)
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(sortedApps) { app in
                        ProcessRow(app: app)
                    }
                }
                .animation(.spring(response: 0.42, dampingFraction: 0.9), value: sortMode)
                .padding(.horizontal, 12)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.automatic)
        }
    }
}

private struct SortModeControl: View {
    @Binding var selection: ProcessSortMode

    private let itemWidth: CGFloat = 58
    private let itemHeight: CGFloat = 24
    private let spacing: CGFloat = 2
    private let padding: CGFloat = 3

    private var selectionIndex: Int {
        ProcessSortMode.allCases.firstIndex(of: selection) ?? 0
    }

    private var controlWidth: CGFloat {
        CGFloat(ProcessSortMode.allCases.count) * itemWidth +
        CGFloat(ProcessSortMode.allCases.count - 1) * spacing +
        padding * 2
    }

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white)
                .frame(width: itemWidth, height: itemHeight)
                .offset(x: padding + CGFloat(selectionIndex) * (itemWidth + spacing))
                .animation(.interactiveSpring(response: 0.34, dampingFraction: 0.88, blendDuration: 0.14), value: selection)

            HStack(spacing: spacing) {
                ForEach(ProcessSortMode.allCases) { mode in
                    Button {
                        withAnimation(.interactiveSpring(response: 0.34, dampingFraction: 0.88, blendDuration: 0.14)) {
                            selection = mode
                        }
                    } label: {
                        Text(mode.title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(selection == mode ? .black : .white.opacity(0.68))
                            .frame(width: itemWidth, height: itemHeight)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(padding)
        }
        .frame(width: controlWidth, height: itemHeight + padding * 2)
        .background {
            Capsule()
                .fill(.white.opacity(0.1))
                .overlay {
                    Capsule()
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                }
        }
    }
}

private struct ProcessRow: View {
    let app: AppProcess

    var body: some View {
        HStack(spacing: 12) {
            AppIconView(image: app.icon, size: 34)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(app.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)

                    if app.isActive {
                        Circle()
                            .fill(.green)
                            .frame(width: 6, height: 6)
                    }
                }

                Text(app.bundleIdentifier ?? "pid \(app.id)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.46))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Text(AppFormatters.cpu(app.cpuPercent))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                Text(AppFormatters.memory(app.memoryBytes))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.54))
            }
            .monospacedDigit()
            .frame(width: 86, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .frame(height: 52)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(app.isActive ? .white.opacity(0.14) : .white.opacity(0.07))
        }
    }
}

private struct AppIconView: View {
    let image: NSImage?
    let size: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
            } else {
                Image(systemName: "app.dashed")
                    .resizable()
                    .symbolRenderingMode(.hierarchical)
                    .padding(6)
            }
        }
        .aspectRatio(contentMode: .fit)
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }
}
