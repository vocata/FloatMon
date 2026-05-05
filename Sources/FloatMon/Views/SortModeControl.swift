import SwiftUI

struct SortModeControl: View {
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

    private var selectionAnimation: Animation {
        .interactiveSpring(response: 0.34, dampingFraction: 0.88, blendDuration: 0.14)
    }

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white)
                .frame(width: itemWidth, height: itemHeight)
                .offset(x: padding + CGFloat(selectionIndex) * (itemWidth + spacing))
                .animation(selectionAnimation, value: selection)

            HStack(spacing: spacing) {
                ForEach(ProcessSortMode.allCases) { mode in
                    Button {
                        withAnimation(selectionAnimation) {
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
