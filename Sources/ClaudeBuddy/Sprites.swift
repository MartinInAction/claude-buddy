import AppKit
import SwiftUI

/// Loads the sprite sheets and slices them into per-frame images.
/// Sheet: 32x32 frames, 4 columns, one animation (Pose) per row, repeated in blocks per fat level. See tools/gen_sprites.py.
final class SpriteSheets {
    static let frameSize = 32
    static let columns = 4
    static let shared = SpriteSheets()

    private var frames: [Int: [[CGImage]]] = [:]   // tint -> row -> frames
    /// Number of fat levels in the sheet (blocks of `Pose.allCases.count` rows). Matches FAT_LEVELS in gen_sprites.py.
    var fatLevels: Int { (frames[0]?.count ?? 0) / Pose.allCases.count }

    /// `level` 0 = normal body; higher = fatter (falls back to the fattest available level).
    func frame(tint: Int, pose: Pose, index: Int, level: Int = 0) -> CGImage? {
        let sheet = frames[tint] ?? frames[0]
        guard let rows = sheet, !rows.isEmpty else { return nil }
        let lvl = max(0, min(level, fatLevels - 1))
        let rowIndex = lvl * Pose.allCases.count + pose.row
        guard rowIndex < rows.count, !rows[rowIndex].isEmpty else { return nil }
        let row = rows[rowIndex]
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
