import AppKit

enum AgentIconResolver {
    static func icon(for provider: AgentProvider) -> NSImage? {
        image(named: provider.rawValue, extension: "icns")
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
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("AgentIcons", isDirectory: true)
    }
}
