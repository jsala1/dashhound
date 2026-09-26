// Écran unique (docs/UI_Dashhound.md) : mascotte + chiffre, jauge « 45 s en mémoire », bouton
// SAUVER, dernier clip ; détails lunettes/session en dessous ; réglages derrière l'engrenage.
import SwiftUI

struct ContentView: View {
  @Bindable var model: WearablesModel
  @State private var confirmCameraRedirect = false
  @State private var confirmMicrophoneRedirect = false
  @State private var showSettings = false

  private var recorder: DashcamRecorder { model.recorder }

  var body: some View {
    NavigationStack {
      List {
        Section {
          VStack(spacing: 16) {
            MascotCard(state: model.dashhoundState)
              .animation(.easeInOut(duration: 0.25), value: model.dashhoundState)
            if recorder.isActive {
              ProgressView(value: Double(recorder.availableSeconds), total: recorder.bufferSeconds)
                .tint(Palette.hound)
                .background(Palette.houndSoft, in: Capsule())
                .animation(.linear(duration: 1), value: recorder.availableSeconds)
                .accessibilityLabel("Mémoire")
                .accessibilityValue("\(recorder.availableSeconds) secondes sur \(Int(recorder.bufferSeconds))")
            }
            saveButton
          }
          .padding(.vertical, 8)
        }
        .listRowBackground(Palette.bg)

        if let clip = recorder.lastClip {
          Section("Dernier clip") { lastClipRow(clip) }
        }

        Section("Dashcam") {
          if model.wantsSession {
            Button("Arrêter la dashcam", role: .destructive) { model.stopSession() }
          } else {
            Button("Démarrer la dashcam") { model.startSession() }
              .disabled(!model.isRegistered || !model.hasActiveDevice)
          }
          if !model.isRegistered {
            Button("Connecter mes lunettes") { model.register() }
          }
          if model.sessionState == .started, !model.isCameraGranted {
            Button("Autoriser la caméra…") { confirmCameraRedirect = true }
          }
          if model.needsMicrophonePermission {
            Button("Autoriser le micro des lunettes…") { confirmMicrophoneRedirect = true }
          }
          row("Son", recorder.isActive ? recorder.audioStatus : recorder.audioSource.label)
        }

        Section("Lunettes") {
          row("Appareil", model.deviceName ?? (model.hasActiveDevice ? "…" : "aucun"))
          row("Batterie", model.batteryLevel.map { "\($0) %" } ?? "—")
          row("Thermique", model.thermal)
          row("Session", model.sessionState.description)
          row("Stream", String(describing: model.streamState))
          row("Meta AI", model.registrationLabel)
        }
      }
      .scrollContentBackground(.hidden)
      .background(Palette.bg)
      .navigationTitle("Dashhound")
      .toolbar {
        Button { showSettings = true } label: { Image(systemName: "gearshape") }
          .accessibilityLabel("Réglages")
      }
      .sheet(isPresented: $showSettings) { SettingsView(model: model) }
      .confirmationDialog(
        "L'app va ouvrir Meta AI pour autoriser la caméra des lunettes.",
        isPresented: $confirmCameraRedirect, titleVisibility: .visible
      ) {
        Button("Ouvrir Meta AI") { Task { await model.requestCameraPermission() } }
      }
      .confirmationDialog(
        "L'app va ouvrir Meta AI pour autoriser le micro des lunettes.",
        isPresented: $confirmMicrophoneRedirect, titleVisibility: .visible
      ) {
        Button("Ouvrir Meta AI") { Task { await model.requestMicrophonePermission() } }
      }
      .alert("Erreur", isPresented: errorBinding) {
        Button("OK") {
          model.errorMessage = nil
          recorder.errorMessage = nil
        }
      } message: {
        Text(model.errorMessage ?? recorder.errorMessage ?? "")
      }
    }
  }

  private var saveButton: some View {
    Button {
      UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
      Task { await recorder.save(trigger: .manual) }
    } label: {
      Group {
        if recorder.isSaving {
          ProgressView().tint(Palette.onHound)
        } else {
          Text("Sauver les \(Int(recorder.bufferSeconds)) s")
        }
      }
      .font(.title2.bold())
      .foregroundStyle(Palette.onHound)
      .frame(maxWidth: .infinity, minHeight: 72)
      .background(Palette.hound, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
    .buttonStyle(.plain)
    .disabled(!recorder.isActive || recorder.availableSeconds == 0 || recorder.isSaving)
    .opacity(recorder.isActive && recorder.availableSeconds > 0 ? 1 : 0.45)
  }

  private func lastClipRow(_ clip: SavedClip) -> some View {
    HStack(spacing: 12) {
      if let thumbnail = clip.thumbnail {
        Image(uiImage: thumbnail).resizable().scaledToFill()
          .frame(width: 56, height: 56).clipShape(RoundedRectangle(cornerRadius: 10))
      }
      VStack(alignment: .leading, spacing: 2) {
        Text("\(Int(clip.duration.rounded())) s · \(clip.date.formatted(date: .omitted, time: .shortened))")
          .font(.headline).monospacedDigit()
        Text(clip.savedToPhotos ? "Dans Photos" : "Gardé dans l'app (pas dans Photos)")
          .font(.subheadline).foregroundStyle(clip.savedToPhotos ? Palette.ok : Palette.warn)
        if clip.audioMutedForCall {
          Text("Son coupé pendant un appel").font(.subheadline).foregroundStyle(Palette.inkMuted)
        }
      }
      Spacer()
      if clip.savedToPhotos, let photos = URL(string: "photos-redirect://") {
        Link("Voir", destination: photos)
      }
    }
  }

  private var errorBinding: Binding<Bool> {
    Binding(
      get: { model.errorMessage != nil || recorder.errorMessage != nil },
      set: {
        if !$0 {
          model.errorMessage = nil
          recorder.errorMessage = nil
        }
      })
  }

  private func row(_ label: String, _ value: String) -> some View {
    LabeledContent(label, value: value)
  }
}

private struct SettingsView: View {
  @Bindable var model: WearablesModel
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    @Bindable var recorder = model.recorder
    NavigationStack {
      Form {
        Section {
          Picker("Son", selection: $recorder.audioSource) {
            ForEach(AudioSource.allCases) { Text($0.label).tag($0) }
          }
          .pickerStyle(.inline)
        } header: {
          Text("Son des clips")
        } footer: {
          Text("Test P1 : comparer « stream » et « mains libres ». Le son est coupé pendant un appel.")
        }
        Section("Image") {
          Picker("Résolution", selection: $recorder.resolution) {
            ForEach(VideoResolution.allCases) { Text($0.label).tag($0) }
          }
        }
        Section {
          Text("Changer un réglage relance le stream : la mémoire repart de zéro.")
            .font(.footnote).foregroundStyle(Palette.inkMuted)
        }
      }
      .navigationTitle("Réglages")
      .toolbar {
        Button("OK") {
          model.restartStream()
          dismiss()
        }
      }
    }
  }
}
