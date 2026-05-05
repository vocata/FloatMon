import SwiftUI

struct ExpandedProcessList: View {
    let apps: [AppProcess]
    @Binding var sortMode: ProcessSortMode
    let activate: (AppProcess) -> Void
    let focusWindow: (AppWindowInfo, AppProcess) -> Void
    let closeWindow: (AppWindowInfo, AppProcess) -> Void
    let requestForceQuit: (AppProcess) -> Void

    @State private var expandedAppIDs: Set<pid_t> = []

    private var sortedApps: [AppProcess] {
        sortMode.sorted(apps)
    }

    private var expandableAppIDs: Set<pid_t> {
        Set(apps.filter { !$0.windows.isEmpty }.map(\.id))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(sortedApps) { app in
                        processSection(for: app)
                    }
                }
                .animation(.spring(response: 0.42, dampingFraction: 0.9), value: sortMode)
                .animation(.spring(response: 0.28, dampingFraction: 0.9), value: expandedAppIDs)
                .padding(.horizontal, 12)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.automatic)
        }
        .onChange(of: expandableAppIDs) { _, ids in
            expandedAppIDs.formIntersection(ids)
        }
    }

    private var header: some View {
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
    }

    private func processSection(for app: AppProcess) -> some View {
        let isWindowListVisible = expandedAppIDs.contains(app.id) && !app.windows.isEmpty

        return VStack(spacing: 4) {
            ProcessRow(
                app: app,
                isExpanded: isWindowListVisible,
                toggleWindows: { toggleWindows(for: app) },
                activate: { activate(app) },
                requestForceQuit: { requestForceQuit(app) }
            )

            if isWindowListVisible {
                WindowList(
                    windows: app.windows,
                    appIcon: app.icon,
                    focusWindow: {
                        focusWindow($0, app)
                    },
                    closeWindow: {
                        closeWindow($0, app)
                    }
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func toggleWindows(for app: AppProcess) {
        guard !app.windows.isEmpty else { return }

        if expandedAppIDs.contains(app.id) {
            expandedAppIDs.remove(app.id)
        } else {
            expandedAppIDs.insert(app.id)
        }
    }
}
