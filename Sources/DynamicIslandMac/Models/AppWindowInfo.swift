import CoreGraphics

struct AppWindowInfo: Identifiable, Hashable, Sendable {
    let id: Int
    let title: String
    let frame: CGRect
}
