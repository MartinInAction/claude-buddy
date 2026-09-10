import Foundation
import Observation

/// One animation row in the sprite sheet. Row order must match tools/gen_sprites.py.
enum Pose: Int, CaseIterable {
    case idle = 0, read, type, run, wait, sleep, oops, wave, spawn

    var row: Int { rawValue }
    var frameCount: Int {
        switch self {
        case .idle: return 4
        default: return 2
        }
    }
    var fps: Double {
        switch self {
        case .idle: return 1.5
        case .sleep: return 1
        case .type, .run: return 6
        default: return 3
        }
    }
}

/// A raw hook payload as sent by Claude Code (`type: "http"` hooks).
struct BuddyEvent {
    let name: String
    let sessionID: String
    let agentID: String?
    let agentType: String?
    let toolName: String?
    let toolInput: [String: Any]
    let notificationType: String?
    let cwd: String?
    let transcriptPath: String?

    init?(json data: Data) {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = obj["hook_event_name"] as? String else { return nil }
        self.name = name
        sessionID = obj["session_id"] as? String ?? "unknown"
        agentID = obj["agent_id"] as? String
        agentType = obj["agent_type"] as? String
        toolName = obj["tool_name"] as? String
        toolInput = obj["tool_input"] as? [String: Any] ?? [:]
        notificationType = obj["notification_type"] as? String
        cwd = obj["cwd"] as? String
        transcriptPath = obj["transcript_path"] as? String
    }

    /// Short human hint for the speech bubble.
    var hint: String? {
        guard let tool = toolName else { return nil }
        func base(_ key: String) -> String? {
            (toolInput[key] as? String).map { ($0 as NSString).lastPathComponent }
        }
        let text: String?
        switch tool {
        case "Read", "Edit", "Write", "MultiEdit", "NotebookEdit": text = base("file_path")
        case "Bash": text = (toolInput["description"] as? String) ?? (toolInput["command"] as? String)
        case "Grep", "Glob": text = toolInput["pattern"] as? String
        case "Agent", "Task": text = toolInput["description"] as? String
        case "WebFetch": text = (toolInput["url"] as? String).flatMap { URL(string: $0)?.host }
        case "WebSearch": text = toolInput["query"] as? String
        case "Skill": text = toolInput["skill"] as? String
        default: text = nil
        }
        let label = tool.hasPrefix("mcp__") ? tool.split(separator: "_").last.map(String.init) ?? tool : tool
        guard let t = text?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return label }
        let firstLine = t.split(separator: "\n").first.map(String.init) ?? t
        return "\(label) · \(firstLine.count > 26 ? String(firstLine.prefix(25)) + "…" : firstLine)"
    }
}

@Observable
final class Agent: Identifiable {
    let id: String
    let sessionID: String
    let isSubagent: Bool
    let label: String
    let tint: Int
    var pose: Pose = .idle
    var bubble: String?
    var lastEvent = Date()
    var leaving = false
    var poseStarted = Date()
    var contextTokens: Int?
    var contextChecked = Date.distantPast

    /// 0...1 share of the context window in use.
    var contextFraction: Double {
        guard let t = contextTokens else { return 0 }
        return min(1, Double(t) / Double(ContextMeter.window))
    }

    /// Sprite fat level: 0 below 25 % of the window, then one step per further 25 %.
    var fatLevel: Int {
        let levels = SpriteSheets.shared.fatLevels
        guard levels > 1 else { return 0 }
        return min(levels - 1, Int(contextFraction * Double(levels)))
    }

    init(id: String, sessionID: String, isSubagent: Bool, label: String, tint: Int) {
        self.id = id; self.sessionID = sessionID; self.isSubagent = isSubagent
        self.label = label; self.tint = tint
    }

    func set(_ pose: Pose, bubble: String? = nil) {
        self.pose = pose
        self.bubble = bubble
        poseStarted = Date()
        lastEvent = Date()
    }
}

@Observable
@MainActor
final class SessionModel {
    static let shared = SessionModel()

    private(set) var agents: [Agent] = []
    var lastEventDescription = "Waiting for Claude Code…"
    var eventCount = 0

    private var timer: Timer?
    private var nextTint = 1

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    // MARK: - Event handling

    func handle(_ e: BuddyEvent) {
        eventCount += 1
        lastEventDescription = [e.name, e.toolName, e.agentType].compactMap { $0 }.joined(separator: " · ")
        defer { measureContext(for: e) }

        switch e.name {
        case "SessionStart":
            main(for: e).set(.spawn, bubble: "hej!")
        case "UserPromptSubmit":
            main(for: e).set(.idle, bubble: "…")
        case "SubagentStart":
            let sub = subagent(for: e)
            sub.set(.spawn, bubble: sub.label)
            main(for: e).set(.idle, bubble: "delegating…")
        case "SubagentStop":
            if let sub = agents.first(where: { $0.id == e.agentID }) {
                sub.set(.wave, bubble: "done")
                sub.leaving = true
            }
        case "PreToolUse":
            let target = actor(for: e)
            let pose: Pose
            switch e.toolName ?? "" {
            case "Read", "Grep", "Glob", "WebFetch", "WebSearch", "NotebookRead", "LS": pose = .read
            case "Edit", "Write", "MultiEdit", "NotebookEdit": pose = .type
            case "Bash": pose = .run
            case "Agent", "Task": pose = .spawn
            default: pose = .run
            }
            target.set(pose, bubble: e.hint)
        case "PostToolUse":
            let target = actor(for: e)
            // Keep the pose visible for a moment; the tick() will settle it to idle.
            target.lastEvent = Date()
        case "PostToolUseFailure":
            actor(for: e).set(.oops, bubble: e.hint.map { "oops · \($0)" } ?? "oops")
        case "PermissionRequest":
            actor(for: e).set(.wait, bubble: e.hint.map { "may I? \($0)" } ?? "may I?")
        case "Notification":
            switch e.notificationType ?? "" {
            case "permission_prompt", "agent_needs_input", "elicitation_dialog":
                main(for: e).set(.wait, bubble: "waiting for you…")
            case "idle_prompt":
                main(for: e).set(.idle, bubble: nil)
            default: break
            }
        case "Stop":
            if e.agentID == nil { main(for: e).set(.idle, bubble: nil) }
        case "SessionEnd":
            for a in agents where a.sessionID == e.sessionID { a.set(.wave, bubble: "bye"); a.leaving = true }
        default:
            break
        }
    }

    // MARK: - Agents

    private func main(for e: BuddyEvent) -> Agent {
        if let a = agents.first(where: { $0.sessionID == e.sessionID && !$0.isSubagent }) { return a }
        let project = e.cwd.map { ($0 as NSString).lastPathComponent } ?? "claude"
        let a = Agent(id: "main:\(e.sessionID)", sessionID: e.sessionID, isSubagent: false, label: project, tint: 0)
        agents.append(a)
        return a
    }

    private func subagent(for e: BuddyEvent) -> Agent {
        let id = e.agentID ?? UUID().uuidString
        if let a = agents.first(where: { $0.id == id }) { return a }
        let a = Agent(id: id, sessionID: e.sessionID, isSubagent: true,
                      label: e.agentType ?? "agent", tint: nextTint)
        nextTint = nextTint % 4 + 1
        // Insert right after its parent so clones stand next to their main character.
        if let idx = agents.lastIndex(where: { $0.sessionID == e.sessionID }) {
            agents.insert(a, at: idx + 1)
        } else {
            agents.append(a)
        }
        return a
    }

    /// The character that performed the event: the subagent if `agent_id` is set, else the main one.
    private func actor(for e: BuddyEvent) -> Agent {
        if e.agentID != nil {
            let sub = subagent(for: e)
            _ = main(for: e)
            return sub
        }
        return main(for: e)
    }

    // MARK: - Context size

    /// Reads the actor's transcript tail (off the main thread, at most every 2 s per agent) and
    /// stores the latest context size so the sprite can grow with it.
    private func measureContext(for e: BuddyEvent) {
        guard let path = e.transcriptPath,
              let target = agents.first(where: { e.agentID != nil ? $0.id == e.agentID : ($0.sessionID == e.sessionID && !$0.isSubagent) }),
              Date().timeIntervalSince(target.contextChecked) > 2 else { return }
        target.contextChecked = Date()
        let id = target.id
        let url = ContextMeter.transcriptURL(main: path, sessionID: e.sessionID, agentID: e.agentID)
        DispatchQueue.global(qos: .utility).async {
            let tokens = url.flatMap(ContextMeter.contextTokens(at:))
            guard let tokens else { return }
            DispatchQueue.main.async { [weak self] in
                self?.agents.first(where: { $0.id == id })?.contextTokens = tokens
            }
        }
    }

    // MARK: - Housekeeping

    private func tick() {
        let now = Date()
        var remove: [String] = []
        for a in agents {
            let sincePose = now.timeIntervalSince(a.poseStarted)
            let sinceEvent = now.timeIntervalSince(a.lastEvent)
            if a.leaving {
                if sincePose > 2.5 { remove.append(a.id) }
                continue
            }
            switch a.pose {
            case .spawn, .oops, .wave:
                if sincePose > 2 { a.set(.idle, bubble: a.bubble) }
            case .read, .type, .run:
                if sinceEvent > 4 { a.set(.idle, bubble: nil) }
            case .idle:
                if sinceEvent > 8 { a.bubble = nil }
                if sinceEvent > 60 { a.pose = .sleep; a.poseStarted = now }
            case .sleep, .wait:
                break
            }
            // A subagent that has been quiet for a long time is gone (SubagentStop may have been missed).
            if a.isSubagent && sinceEvent > 15 * 60 { remove.append(a.id) }
            // A session silent for 2 hours has most likely been closed without a SessionEnd.
            if !a.isSubagent && sinceEvent > 2 * 60 * 60 { remove.append(a.id) }
        }
        if !remove.isEmpty { agents.removeAll { remove.contains($0.id) } }
    }

    func clear() { agents.removeAll() }

    /// Used by the "Play demo" menu item.
    func demo() {
        let sid = "demo"
        func ev(_ dict: [String: Any]) -> BuddyEvent? {
            var d = dict; d["session_id"] = sid; d["cwd"] = "/Users/you/demo-project"
            return try? BuddyEvent(json: JSONSerialization.data(withJSONObject: d))
        }
        let script: [(Double, [String: Any])] = [
            (0.0, ["hook_event_name": "SessionStart"]),
            (1.5, ["hook_event_name": "UserPromptSubmit", "prompt": "fix the bug"]),
            (2.5, ["hook_event_name": "PreToolUse", "tool_name": "Read", "tool_input": ["file_path": "/src/App.tsx"]]),
            (5.0, ["hook_event_name": "PreToolUse", "tool_name": "Agent", "tool_input": ["description": "Explore codebase"]]),
            (6.0, ["hook_event_name": "SubagentStart", "agent_id": "demo-sub-1", "agent_type": "Explore"]),
            (7.0, ["hook_event_name": "PreToolUse", "tool_name": "Grep", "agent_id": "demo-sub-1", "agent_type": "Explore", "tool_input": ["pattern": "useQuery"]]),
            (8.0, ["hook_event_name": "PreToolUse", "tool_name": "Edit", "tool_input": ["file_path": "/src/theme.ts"]]),
            (10.5, ["hook_event_name": "PreToolUse", "tool_name": "Bash", "tool_input": ["command": "npm run typecheck"]]),
            (12.0, ["hook_event_name": "SubagentStop", "agent_id": "demo-sub-1", "agent_type": "Explore"]),
            (13.5, ["hook_event_name": "PostToolUseFailure", "tool_name": "Bash", "tool_input": ["command": "npm run typecheck"]]),
            (16.0, ["hook_event_name": "PermissionRequest", "tool_name": "Bash", "tool_input": ["command": "git push"]]),
            (20.0, ["hook_event_name": "Stop"]),
            (24.0, ["hook_event_name": "SessionEnd"]),
        ]
        for (delay, dict) in script {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                if let e = ev(dict) { self?.handle(e) }
            }
        }
    }
}
