// Nettoie les poses Dashhound : fond quasi blanc ramené exactement à la couleur de la MascotCard
// (#FAF7F2, fondu doux pour ne pas créer de contour) et fragments d'illustrations voisines effacés.
// Usage : swift scripts/clean_poses.swift design/source/poses-brutes design/poses
import AppKit

let paper: (Double, Double, Double) = (250, 247, 242)  // Palette.mascotPaper
/// Zones à effacer (coordonnées image, origine en haut à gauche) — fragments de la planche d'origine.
let fragments: [String: [(x0: Int, y0: Int, x1: Int, y1: Int)]] = [
  "dashhound-sit-alert.png": [(155, 0, 283, 48)],
  "dashhound-face-tired.png": [(195, 108, 217, 166)],
  "dashhound-face-curious.png": [(0, 18, 46, 42)],
  "dashhound-hero-run.png": [(505, 585, 679, 679)],
]

let src = CommandLine.arguments[1], dst = CommandLine.arguments[2]
for file in try! FileManager.default.contentsOfDirectory(atPath: src).filter({ $0.hasSuffix(".png") }).sorted() {
  let input = NSBitmapImageRep(data: try! Data(contentsOf: URL(fileURLWithPath: "\(src)/\(file)")))!
  let w = input.pixelsWide, h = input.pixelsHigh
  let out = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
    isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: w * 4, bitsPerPixel: 32)!
  let data = out.bitmapData!
  var changed = 0
  for y in 0..<h {
    for x in 0..<w {
      let c = input.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
      var r = Double(c.redComponent) * 255, g = Double(c.greenComponent) * 255, b = Double(c.blueComponent) * 255
      let inFragment = fragments[file]?.contains { x >= $0.x0 && x < $0.x1 && y >= $0.y0 && y < $0.y1 } ?? false
      let dist = max(abs(r - paper.0), abs(g - paper.1), abs(b - paper.2))
      if inFragment || dist <= 10 {
        (r, g, b) = paper
        changed += 1
      } else if dist < 20 {
        let t = (dist - 10) / 10  // fondu vers le papier près du fond
        r = paper.0 + t * (r - paper.0); g = paper.1 + t * (g - paper.1); b = paper.2 + t * (b - paper.2)
      }
      let i = (y * w + x) * 4
      data[i] = UInt8(r.rounded()); data[i + 1] = UInt8(g.rounded()); data[i + 2] = UInt8(b.rounded()); data[i + 3] = 255
    }
  }
  try! out.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(dst)/\(file)"))
  print(file, "\(w)x\(h)", "pixels ramenés au papier : \(changed * 100 / (w * h)) %", fragments[file] != nil ? "· fragment effacé" : "")
}
