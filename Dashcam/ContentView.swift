// Écran unique. P0 : état Meta AI (registration), session, lunettes (batterie, thermique, port).
// Cible : état du stream, jauge « 60 s en mémoire », bouton SAUVER, dernier clip, réglages. Cf. CLAUDE.md.
import SwiftUI

struct ContentView: View {
  @Bindable var model: WearablesModel
  @State private var confirmPermissionRedirect = false

  var body: some View {
    NavigationStack {
      List {
        Section {
          MascotCard(state: model.dashhoundState)
            .padding(.vertical, 8)
            .animation(.easeInOut(duration: 0.25), value: model.dashhoundState)
        }
        .listRowBackground(Palette.bg)

        Section("Meta AI") {
          row("Enregistrement", model.registrationLabel)
          if !model.isRegistered {
            Button("Connecter à Meta AI") { model.register() }
          }
        }

        Section("Lunettes") {
          row("Appareil", model.deviceName ?? (model.hasActiveDevice ? "…" : "aucun"))
          row("Batterie", model.batteryLevel.map { "\($0) %" } ?? "—")
          row("Thermique", model.thermal)
          row("Portées", model.donState)
          row("Lien", model.linkState)
        }

        Section("Session") {
          row("État", model.sessionState.description)
          row("Permission caméra", model.cameraPermission)
          if model.wantsSession {
            Button("Arrêter la session", role: .destructive) { model.stopSession() }
          } else {
            Button("Démarrer la session") { model.startSession() }
              .disabled(!model.isRegistered || !model.hasActiveDevice)
          }
          if model.sessionState == .started, !model.isCameraGranted {
            Button("Autoriser la caméra…") { confirmPermissionRedirect = true }
          }
        }
      }
      .scrollContentBackground(.hidden)
      .background(Palette.bg)
      .navigationTitle("Dashhound")
      .confirmationDialog(
        "L'app va ouvrir Meta AI pour autoriser la caméra des lunettes.",
        isPresented: $confirmPermissionRedirect, titleVisibility: .visible
      ) {
        Button("Ouvrir Meta AI") { Task { await model.requestCameraPermission() } }
      }
      .alert(
        "Erreur",
        isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
      ) {
        Button("OK") { model.errorMessage = nil }
      } message: {
        Text(model.errorMessage ?? "")
      }
    }
  }

  private func row(_ label: String, _ value: String) -> some View {
    LabeledContent(label, value: value)
  }
}
