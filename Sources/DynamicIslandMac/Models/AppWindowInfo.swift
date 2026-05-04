import CoreGraphics
import Foundation

struct AppWindowInfo: Identifiable, Hashable, Sendable {
    let id: Int
    let title: String
    let titleIsFallback: Bool
    let frame: CGRect
    let layer: Int
}
