import SwiftUI

struct AccessibilityPermissionView: View {
    let openSettings: () -> Void
    let recheckPermission: () -> Bool
    let continueToApp: () -> Void
    let quit: () -> Void

    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.black.opacity(0.92))

                    Image(systemName: "accessibility")
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: 5) {
                    Text("Accessibility Permission Required")
                        .font(.system(size: 19, weight: .semibold))

                    Text("DynamicIslandMac needs this permission before it can inspect windows and jump between apps.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let message {
                Text(message)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.orange)
            }

            HStack(spacing: 10) {
                Button("Open Settings") {
                    openSettings()
                }
                .buttonStyle(.borderedProminent)

                Button("Recheck") {
                    if recheckPermission() {
                        continueToApp()
                    } else {
                        message = "Permission is still missing. Enable DynamicIslandMac in Accessibility, then recheck."
                    }
                }
                .buttonStyle(.bordered)

                Spacer(minLength: 0)

                Button("Quit", role: .cancel) {
                    quit()
                }
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}
