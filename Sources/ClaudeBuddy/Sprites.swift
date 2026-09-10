import AppKit
import SwiftUI

/// Loads the sprite sheets and slices them into per-frame images.
/// Sheet: 32x32 frames, 4 columns, one animation (Pose) per row. See tools/gen_sprites.py.
final class SpriteSheets {
    static let frameSize = 32
    static let columns = 4
    static let shared = SpriteSheets()

    private var frames: [Int: [[CGImage]]] = [:]   // tint -> row -> frames
    private var scaledCache: [String: CGImage] = [:]
    private let lock = NSLock()

    /// A frame pre-scaled with nearest-neighbour sampling to an exact pixel size, so stretched
    /// sprites stay crisp (SwiftUI's own resizing blurs non-integer scales).
    func scaledFrame(tint: Int, pose: Pose, index: Int, pixelWidth: Int, pixelHeight: Int) -> CGImage? {
        guard let src = frame(tint: tint, pose: pose, index: index), pixelWidth > 0, pixelHeight > 0 else { return nil }
        let key = "\(tint)-\(pose.rawValue)-\(index % pose.frameCount)-\(pixelWidth)x\(pixelHeight)"
        lock.lock(); defer { lock.unlock() }
        if let hit = scaledCache[key] { return hit }
        guard let ctx = CGContext(data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .none
        ctx.draw(src, in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        guard let out = ctx.makeImage() else { return nil }
        if scaledCache.count > 400 { scaledCache.removeAll() }
        scaledCache[key] = out
        return out
    }

    func frame(tint: Int, pose: Pose, index: Int) -> CGImage? {
        let sheet = frames[tint] ?? frames[0]
        guard let rows = sheet, pose.row < rows.count, !rows[pose.row].isEmpty else { return nil }
        let row = rows[pose.row]
        return row[index % min(row.count, pose.frameCount)]
    }

    private init() {
        for tint in 0...4 {
            let name = tint == 0 ? "buddy" : "buddy_\(tint)"
            if let cg = Self.load(name: name) { frames[tint] = Self.slice(cg) }
        }
        if frames.isEmpty { NSLog("ClaudeBuddy: no sprite sheets found") }
    }

    private static func load(name: String) -> CGImage? {
        var candidates: [URL] = []
        if let u = Bundle.main.resourceURL?.appendingPathComponent("\(name).png") { candidates.append(u) }
        if let u = Bundle.module.url(forResource: name, withExtension: "png") { candidates.append(u) }
        let exe = Bundle.main.executableURL?.deletingLastPathComponent()
        if let u = exe?.appendingPathComponent("\(name).png") { candidates.append(u) }
        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            if let src = CGImageSourceCreateWithURL(url as CFURL, nil),
               let img = CGImageSourceCreateImageAtIndex(src, 0, nil) { return img }
        }
        return nil
    }

    private static func slice(_ sheet: CGImage) -> [[CGImage]] {
        let f = frameSize
        let rows = sheet.height / f
        return (0..<rows).map { r in
            (0..<columns).compactMap { c in
                sheet.cropping(to: CGRect(x: c * f, y: r * f, width: f, height: f))
            }
        }
    }
}
