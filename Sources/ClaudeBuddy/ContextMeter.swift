import Foundation

/// Reads the tail of a Claude Code transcript (.jsonl) and returns the context size of the latest
/// assistant turn: input + cache_read + cache_creation tokens. Cheap: only the last 256 KB is read.
enum ContextMeter {
    static let defaultWindow = 200_000
    static let windowKey = "ContextMeter.window"

    static var window: Int {
        get { let v = UserDefaults.standard.integer(forKey: windowKey); return v > 0 ? v : defaultWindow }
        set { UserDefaults.standard.set(newValue, forKey: windowKey) }
    }

    /// Transcript file for the given actor. Subagent transcripts live in
    /// `<project>/<session_id>/subagents/agent-<agent_id>.jsonl` next to the main `<session_id>.jsonl`.
    static func transcriptURL(main: String, sessionID: String, agentID: String?) -> URL? {
        let mainURL = URL(fileURLWithPath: main)
        guard let agentID else { return mainURL }
        let dir = mainURL.deletingLastPathComponent().appendingPathComponent(sessionID).appendingPathComponent("subagents")
        let direct = dir.appendingPathComponent("agent-\(agentID).jsonl")
        if FileManager.default.fileExists(atPath: direct.path) { return direct }
        // Fallback: any transcript in that folder whose name contains the id.
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        if let match = files.first(where: { $0.contains(agentID) && $0.hasSuffix(".jsonl") }) {
            return dir.appendingPathComponent(match)
        }
        return nil
    }

    static func contextTokens(at url: URL) -> Int? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd(), size > 0 else { return nil }
        let tailLength: UInt64 = 256 * 1024
        let start = size > tailLength ? size - tailLength : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return nil }
        // Scan lines from the end; skip the first partial line if we started mid-file.
        var lines = data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)
        if start > 0, !lines.isEmpty { lines.removeFirst() }
        for line in lines.reversed() {
            guard line.range(of: Data("\"usage\"".utf8)) != nil,
                  let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  (obj["type"] as? String) == "assistant",
                  let message = obj["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any] else { continue }
            let input = usage["input_tokens"] as? Int ?? 0
            let cacheRead = usage["cache_read_input_tokens"] as? Int ?? 0
            let cacheCreate = usage["cache_creation_input_tokens"] as? Int ?? 0
            let total = input + cacheRead + cacheCreate
            if total > 0 { return total }
        }
        return nil
    }

    static func format(_ tokens: Int) -> String {
        tokens >= 1000 ? "\(tokens / 1000)k" : "\(tokens)"
    }
}
