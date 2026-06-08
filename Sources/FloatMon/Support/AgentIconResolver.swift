import AppKit

enum AgentIconResolver {
    private static var cachedIcons: [AgentProvider: NSImage] = [:]

    static func icon(for provider: AgentProvider) -> NSImage? {
        if let cachedIcon = cachedIcons[provider] {
            return cachedIcon
        }

        guard let icon = image(named: provider.rawValue, extension: "icns") else {
            return nil
        }
        cachedIcons[provider] = icon
        return icon
    }

    private static func image(named name: String, extension pathExtension: String) -> NSImage? {
        if let bundledURL = Bundle.main.url(forResource: name, withExtension: pathExtension, subdirectory: "AgentIcons"),
           let image = NSImage(contentsOf: bundledURL) {
            return image
        }

        let sourceURL = sourceAgentIconsDirectory()
            .appendingPathComponent(name)
            .appendingPathExtension(pathExtension)
        return NSImage(contentsOf: sourceURL)
    }

    private static func sourceAgentIconsDirectory() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("AgentIcons", isDirectory: true)
    }
}
