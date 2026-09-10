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

/// All sessions, wrapping onto new lines when the strip gets too wide.
struct BuddyStrip: View {
    var model: SessionModel
    var onSizeChange: (CGSize) -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 8.0)) { ctx in
            let families = Family.group(model.agents)
            FlowLayout(spacing: 6, maxWidth: 440) {
                if families.isEmpty {
                    CharacterView(agent: nil, date: ctx.date)
                } else {
                    ForEach(families) { family in
                        FamilyView(family: family, date: ctx.date)
                            .transition(.scale(scale: 0.2, anchor: .bottom).combined(with: .opacity))
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

/// Main character in the middle; subagents alternate left/right, stacked two per column,
/// newest nearest the main character.
struct FamilyView: View {
    let family: Family
    let date: Date

    private var sides: (left: [Agent], right: [Agent]) {
        var l: [Agent] = [], r: [Agent] = []
        for (i, a) in family.subs.enumerated() { if i % 2 == 0 { r.append(a) } else { l.append(a) } }
        return (l, r)
    }

    var body: some View {
        let (left, right) = sides
        HStack(alignment: .bottom, spacing: 2) {
            columns(left, mirrored: true)
            CharacterView(agent: family.main, date: date)
            columns(right, mirrored: false)
        }
        .padding(.horizontal, family.subs.isEmpty ? 0 : 6)
        .padding(.top, family.subs.isEmpty ? 0 : 4)
        .background {
            if !family.subs.isEmpty {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.regularMaterial)
                    .opacity(0.3)
            }
        }
    }

    /// Chunks of two subagents stacked vertically; the first chunk sits next to the main character.
    @ViewBuilder private func columns(_ subs: [Agent], mirrored: Bool) -> some View {
        let chunks = stride(from: 0, to: subs.count, by: 2).map { Array(subs[$0..<min($0 + 2, subs.count)]) }
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array((mirrored ? chunks.reversed() : chunks).enumerated()), id: \.offset) { _, chunk in
                VStack(spacing: 0) {
                    ForEach(chunk) { sub in
                        CharacterView(agent: sub, date: date)
                            .transition(.scale(scale: 0.2, anchor: .bottom).combined(with: .opacity))
                    }
                }
            }
        }
    }
}

/// Left-to-right flow that wraps at `maxWidth`, bottom-aligning items within a row.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var maxWidth: CGFloat = 440

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(subviews)
        for (i, origin) in result.origins.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                              anchor: .topLeading, proposal: .unspecified)
        }
    }

    private func arrange(_ subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        var rows: [[Int]] = [[]]
        var rowWidth: CGFloat = 0
        for (i, sz) in sizes.enumerated() {
            let needed = rowWidth == 0 ? sz.width : rowWidth + spacing + sz.width
            if needed > maxWidth, !rows[rows.count - 1].isEmpty {
                rows.append([i]); rowWidth = sz.width
            } else {
                rows[rows.count - 1].append(i); rowWidth = needed
            }
        }
        var origins = Array(repeating: CGPoint.zero, count: sizes.count)
        var y: CGFloat = 0
        var totalWidth: CGFloat = 0
        for row in rows {
            let rowHeight = row.map { sizes[$0].height }.max() ?? 0
            var x: CGFloat = 0
            for i in row {
                origins[i] = CGPoint(x: x, y: y + rowHeight - sizes[i].height)   // bottom-align
                x += sizes[i].width + spacing
            }
            totalWidth = max(totalWidth, x - spacing)
            y += rowHeight + spacing
        }
        return (CGSize(width: max(totalWidth, 0), height: max(y - spacing, 0)), origins)
    }
}

struct CharacterView: View {
    let agent: Agent?
    let date: Date

    private var scale: CGFloat { (agent?.isSubagent ?? false) ? 1.5 : 2 }
    private var pose: Pose { agent?.pose ?? .sleep }

    var body: some View {
        VStack(spacing: 1) {
            bubble
            sprite
            label
        }
        .opacity((agent?.leaving ?? false) ? 0.55 : 1)
    }

    private var frameIndex: Int {
        let t = date.timeIntervalSince(agent?.poseStarted ?? .distantPast)
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

    @ViewBuilder private var bubble: some View {
        let text = agent?.bubble
        Text(text ?? " ")
            .font(.system(size: 9, weight: .medium, design: .rounded))
            .lineLimit(1)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.white.opacity(0.15)))
            .opacity(text == nil ? 0 : 1)
            .frame(maxWidth: 160)
    }

    @ViewBuilder private var label: some View {
        let ctx = agent?.contextTokens.map { " · \(ContextMeter.format($0))" } ?? ""
        Text((agent?.label ?? "zzz") + ctx)
            .font(.system(size: 7.5, weight: .semibold, design: .monospaced))
            .lineLimit(1)
            .padding(.horizontal, 5).padding(.vertical, 1.5)
            .background(.regularMaterial, in: Capsule())
            .frame(maxWidth: CGFloat(SpriteSheets.frameSize) * scale + 60)
            .opacity(agent == nil ? 0.5 : 1)
    }
}
