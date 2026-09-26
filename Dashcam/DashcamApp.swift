// Point d'entrée. Rôle : configurer le SDK Meta DAT au lancement et router les callbacks
// URL de l'app Meta AI (enregistrement, permissions) vers le SDK. Cf. CLAUDE.md.
import SwiftUI
import MWDATCore

@main
struct DashcamApp: App {
  @State private var model: WearablesModel

  init() {
    do {
      try Wearables.configure()
    } catch {
      assertionFailure("Configuration du SDK Wearables impossible : \(error)")
    }
    // Après configure() : le modèle lit Wearables.shared dès son init.
    _model = State(wrappedValue: WearablesModel(recorder: DashcamRecorder()))
  }

  var body: some Scene {
    WindowGroup {
      ContentView(model: model)
        .onOpenURL { url in
          // Ne transmettre au SDK que les liens Meta AI (skill getting-started).
          guard
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            components.queryItems?.contains(where: { $0.name == "metaWearablesAction" }) == true
          else { return }
          Task {
            do { _ = try await Wearables.shared.handleUrl(url) } catch {
              print("handleUrl a échoué : \(error)")
            }
          }
        }
    }
  }
}
