// Écran unique (P0 : placeholder). Cible : état du stream, jauge « 60 s en mémoire »,
// batterie/thermique des lunettes, bouton SAUVER, dernier clip, réglages. Cf. CLAUDE.md.
import SwiftUI

struct ContentView: View {
  var body: some View {
    VStack(spacing: 16) {
      Text("Glasses Dashcam").font(.largeTitle.bold())
      Text("P0 — squelette. Enregistrement Meta AI et session à brancher dans WearablesModel.")
        .multilineTextAlignment(.center)
        .foregroundStyle(.secondary)
    }
    .padding()
  }
}
