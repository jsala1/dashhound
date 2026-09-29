// Identité Dashhound : tokens de couleur (Color Sets clair/sombre, Assets.xcassets/Colors) et
// états de l'app → posture de la mascotte (Assets.xcassets/Mascot). Cf. docs/UI_Dashhound.md.
// Règle : une posture ne remplace jamais une donnée — le chiffre reste toujours écrit.
import SwiftUI

enum Palette {
  static let bg = Color("bg")
  static let surface = Color("surface")
  static let ink = Color("ink")
  static let inkMuted = Color("inkMuted")
  static let hound = Color("hound")
  static let houndSoft = Color("houndSoft")
  static let led = Color("led")
  static let ok = Color("ok")
  static let warn = Color("warn")
  /// Texte sur `hound` (bouton SAUVER), fixe dans les deux modes : le blanc n'y fait que 2,8:1
  /// (clair) / 2,4:1 (sombre) ; ce brun y fait 6,2:1 / 7,8:1. Validé par Julian le 2026-09-27
  /// (boutons orange conservés : le bleu est la LED « ça filme » et évoquerait la marque Meta).
  static let onHound = Color(red: 0x1E / 255, green: 0x1A / 255, blue: 0x17 / 255)
  /// Fond des illustrations, identique dans les deux modes : les poses ne sont pas détourées.
  static let mascotPaper = Color(red: 0xFA / 255, green: 0xF7 / 255, blue: 0xF2 / 255)
}

enum DashhoundState: Equatable {
  /// Premier lancement / enregistrement Meta AI.
  case onboarding
  /// Recherche des lunettes, session en cours de démarrage.
  case searching
  /// Dashcam en marche : chrono depuis le démarrage (la mémoire, elle, ne s'affiche pas — un clip
  /// sauve toujours ce qui est disponible, jusqu'à la durée réglée).
  case recording(since: Date)
  /// Clip sauvé (bouton, choc, bouton des lunettes).
  case saved
  /// Lunettes en pause après un tap sur la branche : clip sauvé, mais plus de film jusqu'au tap suivant.
  case pausedByGlasses
  /// Choc détecté par l'iPhone : sauvegarde dans quelques secondes (pour garder l'« après »).
  case impactDetected
  /// Pas de stream (pause, téléphone en poche sans session).
  case resting
  /// Lunettes déconnectées : le buffer est vide.
  case disconnected(memoryKept: Bool)
  /// Dashcam en marche mais lunettes occupées (appel WhatsApp, enregistrement lancé depuis les
  /// lunettes…) : la mémoire d'avant la coupure est gardée, la reprise est automatique.
  case glassesBusy
  /// Batterie lunettes < 15 % ou thermique chaud.
  case tired(battery: Int?, isHot: Bool)
  /// Registration ou permission manquante.
  case missingPermission
  /// Clip exporté / partagé.
  case exported
  /// Écran « À propos ».
  case about

  /// Nom de l'image dans Assets.xcassets/Mascot.
  var pose: String {
    switch self {
    case .onboarding: "dashhound-hero-run"
    case .searching: "dashhound-sniff"
    case .recording: "dashhound-sit-alert"
    case .impactDetected: "dashhound-face-alert"
    case .saved, .pausedByGlasses: "dashhound-look-back"
    case .resting: "dashhound-play-bow"
    case .disconnected, .missingPermission, .glassesBusy: "dashhound-face-curious"
    case .tired: "dashhound-face-tired"
    case .exported: "dashhound-face-happy"
    case .about: "dashhound-face-wink"
    }
  }

  /// Images alternées pendant la recherche (400 ms), sauf si « Réduire les animations » est actif.
  static let searchFrames = ["dashhound-run-1", "dashhound-run-2", "dashhound-run-3"]

  /// Ligne du chien, à la première personne.
  var line: String {
    switch self {
    case .onboarding: String(localized: "Salut, moi c'est Dashhound.")
    case .searching: String(localized: "Je cherche tes lunettes…")
    case .recording: String(localized: "Je regarde.")
    case .saved: String(localized: "Sauvé !")
    case .pausedByGlasses: String(localized: "Sauvé. Je reprends dans un instant.")
    case .impactDetected: String(localized: "Choc détecté ! Je sauve dans un instant.")
    case .resting: String(localized: "Je m'étire.")
    case .disconnected: String(localized: "Hmm, je ne les vois plus.")
    case .glassesBusy: String(localized: "Les lunettes sont occupées (un appel ?).")
    case .tired(_, let isHot): isHot ? String(localized: "J'ai chaud.") : String(localized: "Je fatigue.")
    case .missingPermission: String(localized: "Il me manque une autorisation.")
    case .exported: String(localized: "Bien joué.")
    case .about: "Dashhound · Rewind"
    }
  }

  /// Le chiffre, toujours affiché quand il existe (secondes en mémoire, batterie).
  var figure: String? {
    switch self {
    case .tired(let battery, _): battery.map { "\($0) %" }
    default: nil
    }
  }

  /// Information critique à ne jamais taire.
  var warning: String? {
    switch self {
    case .disconnected(let kept):
      kept ? String(localized: "Je garde ce que j'ai vu, je reprends dès leur retour.") : String(localized: "Le buffer est vide.")
    case .glassesBusy: String(localized: "Je garde ce que j'ai vu, je reprends dès qu'elles sont libres.")
    case .pausedByGlasses: String(localized: "Je ne filme plus en pause.")
    default: nil
    }
  }
}

extension WearablesModel {
  /// État de la mascotte déduit de l'état réel. Session ouverte sans stream = « au repos » : on
  /// n'affiche jamais de secondes en mémoire qui n'existent pas.
  var dashhoundState: DashhoundState {
    switch registrationState {
    case .unavailable: return .missingPermission
    case .available, .registering: return .onboarding
    case .registered: break
    @unknown default: return .onboarding
    }
    if let battery = batteryLevel, battery < 15 { return .tired(battery: battery, isHot: isThermalHot) }
    if isThermalHot { return .tired(battery: batteryLevel, isHot: true) }
    if sessionState == .started, !isCameraGranted, cameraPermission != "—" { return .missingPermission }
    let memoryKept = recorder.availableSeconds > 0
    if !hasActiveDevice { return wantsSession ? .disconnected(memoryKept: memoryKept) : .searching }
    if recorder.impactPending { return .impactDetected }
    if recorder.isPausedByGlasses || streamState == .paused || sessionState == .paused { return .pausedByGlasses }
    if recorder.justSaved { return .saved }
    if recorder.isActive { return .recording(since: recorder.dashcamStartedAt ?? Date()) }
    if recorder.isInterrupted { return .glassesBusy }
    if sessionState == .starting || streamState == .starting || streamState == .waitingForDevice { return .searching }
    return .resting
  }
}

/// Carte mascotte : pose sur fond papier (coins 24 pt), ligne du chien, chiffre en gros.
struct MascotCard: View {
  let state: DashhoundState
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    VStack(spacing: 12) {
      illustration
        .frame(maxWidth: 180, maxHeight: 180)
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Palette.mascotPaper, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityHidden(true)

      Text(state.line)
        .font(.title3.weight(.semibold))
        .foregroundStyle(Palette.ink)
        .multilineTextAlignment(.center)

      if case .recording(let since) = state {
        Text(since, style: .timer)
          .font(.largeTitle.bold().monospacedDigit())
          .foregroundStyle(Palette.ink)
          .accessibilityLabel(Text("Durée d'enregistrement"))
      } else if let figure = state.figure {
        Text(figure)
          .font(.largeTitle.bold().monospacedDigit())
          .foregroundStyle(Palette.ink)
      }

      if let warning = state.warning {
        Label {
          Text(warning).foregroundStyle(Palette.ink)
        } icon: {
          Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.warn)
        }
        .font(.headline)
      }
    }
    .accessibilityElement(children: .combine)
  }

  @ViewBuilder private var illustration: some View {
    if state == .searching, !reduceMotion {
      TimelineView(.periodic(from: .now, by: 0.4)) { context in
        let frames = DashhoundState.searchFrames
        let index = Int(context.date.timeIntervalSinceReferenceDate / 0.4) % frames.count
        Image(frames[index]).resizable().scaledToFit()
      }
    } else {
      Image(state.pose).resizable().scaledToFit()
    }
  }
}

#Preview("Tous les états") {
  let states: [DashhoundState] = [
    .onboarding, .searching, .recording(since: Date().addingTimeInterval(-754)), .saved,
    .resting, .disconnected(memoryKept: true), .glassesBusy, .tired(battery: 12, isHot: false), .missingPermission, .exported, .about,
  ]
  ScrollView {
    VStack(spacing: 32) {
      ForEach(Array(states.enumerated()), id: \.offset) { MascotCard(state: $0.element) }
    }
    .padding()
  }
  .background(Palette.bg)
}
