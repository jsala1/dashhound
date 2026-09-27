// Exporte le pack d'images de Dashhound : poses nettoyées, icône, hero, GIF de l'animation
// « Je cherche tes lunettes » (run-1 → run-2 → run-3, 400 ms, en boucle, comme MascotCard).
// Usage : swift scripts/export_pack.swift <dossier de sortie>
import AppKit
import ImageIO
import UniformTypeIdentifiers

let out = URL(fileURLWithPath: CommandLine.arguments[1])
let fm = FileManager.default
try? fm.removeItem(at: out)
for sub in ["poses", "icone", "hero", "animation", "live-activity"] {
  try! fm.createDirectory(at: out.appendingPathComponent(sub), withIntermediateDirectories: true)
}
func copy(_ src: String, _ dst: String) { try! fm.copyItem(atPath: src, toPath: out.appendingPathComponent(dst).path) }

for f in try! fm.contentsOfDirectory(atPath: "design/poses").filter({ $0.hasSuffix(".png") }).sorted() {
  copy("design/poses/\(f)", "poses/\(f)")
}
copy("design/AppIcon-1024.png", "icone/AppIcon-1024.png")
copy("design/Hero-Rewind-1080.png", "hero/Hero-Rewind-1080.png")
copy("design/poses/dashhound-face-alert.png", "live-activity/dashhound-face-alert.png")

// GIF : chaque image mise à l'échelle sur un carré de 480 px (comme scaledToFit dans l'app).
let side = 480
func frame(_ name: String) -> CGImage {
  let img = NSImage(contentsOfFile: "design/poses/\(name).png")!
  let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
    isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
  NSColor(deviceRed: 250 / 255, green: 247 / 255, blue: 242 / 255, alpha: 1).setFill()
  NSRect(x: 0, y: 0, width: side, height: side).fill()
  img.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
  NSGraphicsContext.restoreGraphicsState()
  return rep.cgImage!
}
let names = ["dashhound-run-1", "dashhound-run-2", "dashhound-run-3"]
let gifURL = out.appendingPathComponent("animation/dashhound-recherche.gif") as CFURL
let gif = CGImageDestinationCreateWithURL(gifURL, UTType.gif.identifier as CFString, names.count, nil)!
CGImageDestinationSetProperties(gif, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
for n in names {
  CGImageDestinationAddImage(gif, frame(n), [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.4]] as CFDictionary)
}
precondition(CGImageDestinationFinalize(gif))

try! """
# Dashhound · Rewind — pack d'images

Exporté depuis le repo `glasses-dashcam` (images telles qu'utilisées dans l'app).

| Dossier | Contenu |
|---|---|
| `poses/` | 14 poses nettoyées (fond `#FAF7F2` uni, sans cadre ni fragment voisin). Fond non transparent. |
| `animation/dashhound-recherche.gif` | « Je cherche tes lunettes… » : run-1 → run-2 → run-3, 400 ms, en boucle, 480 × 480 |
| `icone/AppIcon-1024.png` | icône de l'app, 1024 × 1024, sans transparence |
| `hero/Hero-Rewind-1080.png` | visuel du post LinkedIn / écran d'accueil |
| `live-activity/` | pose affichée sur l'écran verrouillé et la Dynamic Island |

## Quelle pose pour quel état

| État de l'app | Pose | Phrase (FR / EN) |
|---|---|---|
| Premier lancement | hero-run | Salut, moi c'est Dashhound. / Hi, I'm Dashhound. |
| Recherche des lunettes | animation run-1/2/3 (sniff si « Réduire les animations ») | Je cherche tes lunettes… / Looking for your glasses… |
| Mémoire en cours de remplissage | sit-alert | Je regarde. / Watching. |
| 45 s en mémoire | face-alert | 45 s en mémoire. / 45 s in memory. |
| Clip sauvé | look-back | Sauvé ! / Saved! |
| Reprise après un tap | look-back | Sauvé. Je reprends dans un instant. / Saved. Resuming in a moment. |
| Au repos | play-bow | Je m'étire. / Stretching. |
| Lunettes perdues | face-curious | Hmm, je ne les vois plus. / Hmm, I can't see them anymore. |
| Batterie < 15 % ou chaud | face-tired | Je fatigue. / J'ai chaud. |
| Autorisation manquante | face-curious | Il me manque une autorisation. |
| Clip exporté | face-happy | Bien joué. / Nice one. |
| À propos | face-wink | — |
| (non utilisée) | walk | — |

## Palette (clair / sombre)

| Token | Clair | Sombre | Usage |
|---|---|---|---|
| bg | #FCF8F4 | #171412 | fond d'écran |
| surface | #FFFFFF | #23201C | cartes |
| ink | #1E1A17 | #F5EFE8 | texte |
| inkMuted | #7A6F66 | #A89C92 | texte secondaire |
| hound | #F87521 | #FF8A3D | boutons (texte #1E1A17 dessus) |
| houndSoft | #FDE3D2 | #3A2416 | jauge, fonds passifs |
| led | #4DA3FF | #6FB6FF | LED « ça filme » |
| ok | #2FA36B | #4CC585 | succès |
| warn | #D9473A | #FF6B5E | alertes |
| papier mascotte | #FAF7F2 | #FAF7F2 | fond des poses (fixe) |

Règles : ne jamais écrire « Ray-Ban » ou « Meta » à côté de la mascotte ; la LED bleue reste visible.
""".write(to: out.appendingPathComponent("LISEZMOI.md"), atomically: true, encoding: .utf8)
print("OK", out.path)
