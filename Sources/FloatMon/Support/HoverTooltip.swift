import SwiftUI

struct HoverTooltipModifier: ViewModifier {
    let text: String
    var allowsMultiline = false
    @State private var isHovering = false
    @State private var isVisible = false
    @State private var hoverToken = 0

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .trailing) {
                if isVisible {
                    Text(text)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.68))
                        .lineLimit(allowsMultiline ? 8 : 1)
                        .fixedSize(horizontal: !allowsMultiline, vertical: allowsMultiline)
                        .frame(maxWidth: allowsMultiline ? 340 : nil, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background {
                            RoundedRectangle(cornerRadius: allowsMultiline ? 10 : 999, style: .continuous)
                                .fill(.black.opacity(0.52))
                                .overlay {
                                    RoundedRectangle(cornerRadius: allowsMultiline ? 10 : 999, style: .continuous)
                                        .stroke(.white.opacity(0.07), lineWidth: 1)
                                }
                                .shadow(color: .black.opacity(0.16), radius: 6, y: 2)
                        }
                        .offset(x: -30, y: 0)
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .trailing)))
                        .allowsHitTesting(false)
                }
            }
            .zIndex(isVisible ? 20 : 0)
            .onHover { hovering in
                updateHovering(hovering)
            }
    }

    private func updateHovering(_ hovering: Bool) {
        hoverToken += 1
        let token = hoverToken
        isHovering = hovering

        guard hovering else {
            withAnimation(.easeOut(duration: 0.10)) {
                isVisible = false
            }
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            guard isHovering, hoverToken == token else { return }
            withAnimation(.easeOut(duration: 0.14)) {
                isVisible = true
            }
        }
    }
}

extension View {
    func hoverTooltip(_ text: String) -> some View {
        modifier(HoverTooltipModifier(text: text))
    }

    func hoverDetailTooltip(_ text: String) -> some View {
        modifier(HoverTooltipModifier(text: text, allowsMultiline: true))
    }
}
