import SwiftUI

/// The whole strip of characters. Re-renders ~8x per second via TimelineView.
struct BuddyStrip: View {
    var model: SessionModel
    var onSizeChange: (CGSize) -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 8.0)) { ctx in
            HStack(alignment: .bottom, spacing: 6) {
                if model.agents.isEmpty {
                    CharacterView(agent: nil, date: ctx.date)
                } else {
                    ForEach(model.agents) { agent in
                        CharacterView(agent: agent, date: ctx.date)
                            .transition(.scale(scale: 0.2, anchor: .bottom).combined(with: .opacity))
                    }
                }
            }
            .animation(.spring(duration: 0.35), value: model.agents.map(\.id))
            .padding(.horizontal, 10)
            .padding(.bottom, 4)
            .fixedSize()
        }
        .background(GeometryReader { geo in
            Color.clear
                .onAppear { onSizeChange(geo.size) }
                .onChange(of: geo.size) { _, new in onSizeChange(new) }
        })
    }
}

struct CharacterView: View {
    let agent: Agent?
    let date: Date

    private var scale: CGFloat { (agent?.isSubagent ?? false) ? 3 : 4 }
    private var pose: Pose { agent?.pose ?? .sleep }

    var body: some View {
        VStack(spacing: 2) {
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
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .lineLimit(1)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.white.opacity(0.15)))
            .opacity(text == nil ? 0 : 1)
            .frame(maxWidth: 220)
    }

    @ViewBuilder private var label: some View {
        let ctx = agent?.contextTokens.map { " · \(ContextMeter.format($0))" } ?? ""
        Text((agent?.label ?? "zzz") + ctx)
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .lineLimit(1)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(.regularMaterial, in: Capsule())
            .frame(maxWidth: CGFloat(SpriteSheets.frameSize) * scale + 40)
            .opacity(agent == nil ? 0.5 : 1)
    }
}
