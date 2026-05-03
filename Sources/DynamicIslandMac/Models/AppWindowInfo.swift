import Foundation

struct AppWindowInfo: Identifiable, Hashable, Sendable {
    let id: Int
    let title: String
    let titleIsFallback: Bool
    let layer: Int
}
