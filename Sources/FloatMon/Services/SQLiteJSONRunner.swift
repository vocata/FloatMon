import Foundation

enum SQLiteJSONRunner {
    static func run<Row: Decodable>(path: String, query: String) -> [Row]? {
        try? runOrThrow(path: path, query: query, errorDomain: "FloatMon.SQLiteJSONRunner")
    }

    static func runOrThrow<Row: Decodable>(
        path: String,
        query: String,
        errorDomain: String
    ) throws -> [Row] {
        let process = Process()
        let output = Pipe()
        let error = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-json", path, query]
        process.standardOutput = output
        process.standardError = error

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw error
        }

        guard process.terminationStatus == 0 else {
            let data = error.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8) ?? "sqlite failed"
            throw NSError(domain: errorDomain, code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: message
            ])
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        do {
            return try JSONDecoder().decode([Row].self, from: data)
        } catch {
            throw NSError(domain: errorDomain, code: 2, userInfo: [
                NSLocalizedDescriptionKey: "sqlite JSON decode failed: \(error.localizedDescription)"
            ])
        }
    }

    static func execute(path: String, query: String, errorDomain: String) throws {
        let process = Process()
        let error = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [path, query]
        process.standardError = error
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = error.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8) ?? "sqlite failed"
            throw NSError(domain: errorDomain, code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: message
            ])
        }
    }

    static func executeIgnoringFailure(path: String, query: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [path, query]
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return
        }
    }
}
