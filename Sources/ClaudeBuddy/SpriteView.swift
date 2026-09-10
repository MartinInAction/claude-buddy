import SwiftUI

/// One session: the main character with its subagents clustered on both sides.
struct Family: Identifiable {
    let main: Agent
    let subs: [Agent]
    var id: String { main.id }

    static func group(_ agents: [Agent]) -> [Family] {
        var order: [String] = []
        var bySession: [String: [Agent]] = [:]
        for a in agents {
            if bySession[a.sessionID] == nil { order.append(a.sessionID) }
            bySession[a.sessionID, default: []].append(a)
        }
        return order.compactMap { sid in
            let members = bySession[sid] ?? []
            guard let main = members.first(where: { !$0.isSubagent }) ?? members.first else { return nil }
            return Family(main: main, subs: members.filter { $0.id != main.id })
        }
    }
}

/// Fixed cell sizes so nothing shifts when labels, bubbles or poses change.
enum Cell {
    static let columns = 2            // sessions per row
    static let width: CGFloat = 236   // one session
    static let character: CGFloat = 112   // one character column inside a session
    static let spacing: CGFloat = 6
}

/// All sessions in a fixed grid, `Cell.columns` per row, bottom-aligned.
struct BuddyStrip: View {
    var model: SessionModel
    var onSizeChange: (CGSize) -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 8.0)) { ctx in
            let families = Family.group(model.agents)
            let rows = stride(from: 0, to: families.count, by: Cell.columns).map { Array(families[$0..<min($0 + Cell.columns, families.count)]) }
            Group {
                if families.isEmpty {
                    CharacterView(agent: nil, date: ctx.date, miner: model.miner)
                        .frame(width: Cell.character)
                } else {
                    Grid(alignment: .bottom, horizontalSpacing: Cell.spacing, verticalSpacing: Cell.spacing) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                            GridRow(alignment: .bottom) {
                                ForEach(row) { family in
                                    FamilyView(family: family, date: ctx.date)
                                        .frame(width: Cell.width, alignment: .bottom)
                                        .transition(.scale(scale: 0.2, anchor: .bottom).combined(with: .opacity))
                                }
                            }
                        }
                    }
                }
            }
            .animation(.spring(duration: 0.35), value: model.agents.map(\.id))
            .padding(.horizontal, 6)
            .padding(.bottom, 2)
            .fixedSize()
        }
        .background(GeometryReader { geo in
            Color.clear
                .onAppear { onSizeChange(geo.size) }
                .onChange(of: geo.size) { _, new in onSizeChange(new) }
        })
    }
}

/// One session: project title on top, then the main character and its subagents in rows of two.
struct FamilyView: View {
    let family: Family
    let date: Date
    static let perRow = 2

    var body: some View {
        let members = [family.main] + family.subs
        let rows = stride(from: 0, to: members.count, by: Self.perRow).map { Array(members[$0..<min($0 + Self.perRow, members.count)]) }
        VStack(spacing: 4) {
            // Never wider than the characters below it: a long project name gets an ellipsis.
            let titleWidth = members.count > 1 ? Cell.character * 2 + 4 : Cell.character
            Pill(text: family.main.label + contextSuffix(family.main), size: 9, weight: .semibold, maxWidth: titleWidth)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(row) { member in
                        CharacterView(agent: member, date: date)
                            .frame(width: Cell.character, alignment: .bottom)
                            .transition(.scale(scale: 0.2, anchor: .bottom).combined(with: .opacity))
                    }
                }
            }
        }
        .padding(.horizontal, 4)
    }
}

func contextSuffix(_ agent: Agent?) -> String {
    agent?.contextTokens.map { " · \(ContextMeter.format($0))" } ?? ""
}

/// Small material pill used for titles, labels and descriptions.
struct Pill: View {
    let text: String
    var size: CGFloat = 7.5
    var weight: Font.Weight = .semibold
    var design: Font.Design = .monospaced
    var maxWidth: CGFloat = 140
    var dim = false

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: weight, design: design))
            .foregroundStyle(dim ? .secondary : .primary)
            .lineLimit(1)
            .padding(.horizontal, 5).padding(.vertical, 1.5)
            .background(.regularMaterial, in: Capsule())
            .frame(maxWidth: maxWidth)
    }
}

struct CharacterView: View {
    let agent: Agent?
    let date: Date
    var miner: Miner? = nil

    private var scale: CGFloat { (agent?.isSubagent ?? false) ? 1.5 : 2 }
    private var pose: Pose { agent?.pose ?? .mine }

    var body: some View {
        VStack(spacing: 1) {
            if let agent, agent.needsInput, let text = agent.bubble {
                SpeechBubble(text: text, date: date)
                    .transition(.scale(scale: 0.3, anchor: .bottom).combined(with: .opacity))
            }
            sprite
            description
        }
        .animation(.spring(duration: 0.3), value: agent?.needsInput ?? false)
        .opacity((agent?.leaving ?? false) ? 0.55 : 1)
    }

    private var frameIndex: Int {
        let t = date.timeIntervalSince(agent?.poseStarted ?? miner?.idleSince ?? .distantPast)
        return Int(t * pose.fps) % pose.frameCount
    }

    @ViewBuilder private var sprite: some View {
        let size = CGFloat(SpriteSheets.frameSize) * scale
        // The character gets fatter as its context window fills up (dedicated sprites per level).
        if let cg = SpriteSheets.shared.frame(tint: agent?.tint ?? 0, pose: pose, index: frameIndex, level: agent?.fatLevel ?? 0) {
            Image(decorative: cg, scale: 1)
                .interpolation(.none)
                .resizable()
                .frame(width: size, height: size)
        } else {
            RoundedRectangle(cornerRadius: 6).fill(.orange).frame(width: size, height: size)
        }
    }

    /// Who this is and what it is doing right now, under the sprite.
    @ViewBuilder private var description: some View {
        if agent == nil, let miner {
            MiningScore(miner: miner, date: date)
        } else {
            agentDescription
        }
    }

    /// What the dim pill says. The question itself sits in the speech bubble, so here it just says why nothing is happening.
    private var activityText: String {
        guard let agent else { return "waiting for Claude Code" }
        if agent.needsInput { return "waiting for you" }
        return agent.bubble ?? (agent.pose == .sleep ? "sleeping" : "idle")
    }

    @ViewBuilder private var agentDescription: some View {
        let name = agent == nil ? "no session" : ((agent?.isSubagent ?? false) ? (agent?.label ?? "agent") : "main")
        let doing = activityText
        VStack(spacing: 1) {
            Pill(text: name + contextSuffix(agent), maxWidth: Cell.character)
            Pill(text: doing, weight: .regular, maxWidth: Cell.character, dim: true)
        }
    }
}

/// Comic-style speech bubble above the head, gently bobbing so it catches the eye.
struct SpeechBubble: View {
    let text: String
    let date: Date
    var maxWidth: CGFloat = Cell.character + 24

    private var bob: CGFloat {
        CGFloat(sin(date.timeIntervalSinceReferenceDate * 2 * .pi / 1.2) * 1.5)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(text)
                .font(.system(size: 7.5, weight: .medium, design: .monospaced))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.primary.opacity(0.25), lineWidth: 0.5))
                .frame(maxWidth: maxWidth)
            BubbleTail()
                .fill(.regularMaterial)
                .overlay(BubbleTail().stroke(.primary.opacity(0.25), lineWidth: 0.5))
                .frame(width: 7, height: 4)
                .offset(y: -0.5)
        }
        .offset(y: bob)
        .padding(.bottom, 2)
    }
}

/// Small downward-pointing triangle under the bubble.
struct BubbleTail: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        return p
    }
}

/// Shown under the sprite while no session exists: the wallet (all BTC ever mined, kept across sessions and
/// app restarts) and how long this idle stretch has lasted.
struct MiningScore: View {
    let miner: Miner
    let date: Date

    var body: some View {
        VStack(spacing: 1) {
            HStack(spacing: 3) {
                BitcoinLogo(size: 9)
                Text(Miner.format(miner.total))
                    .font(.system(size: 7.5, weight: .semibold, design: .monospaced))
            }
            .lineLimit(1)
            .padding(.horizontal, 5).padding(.vertical, 1.5)
            .background(.regularMaterial, in: Capsule())
            Pill(text: "mining · \(Miner.duration(miner.idleSeconds)) idle", weight: .regular, maxWidth: Cell.character, dim: true)
        }
    }
}

/// Tiny orange coin with the ₿ mark.
struct BitcoinLogo: View {
    var size: CGFloat = 10

    var body: some View {
        ZStack {
            Circle().fill(Color(red: 0.97, green: 0.58, blue: 0.10))
            Text("₿")
                .font(.system(size: size * 0.78, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .rotationEffect(.degrees(14))
                .offset(y: -size * 0.02)
        }
        .frame(width: size, height: size)
    }
}
