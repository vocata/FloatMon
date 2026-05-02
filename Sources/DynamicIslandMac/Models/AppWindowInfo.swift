import Foundation

struct AppWindowInfo: Identifiable, Hashable {
    let id: Int
    let title: String
    let titleIsFallback: Bool
    let layer: Int
}
