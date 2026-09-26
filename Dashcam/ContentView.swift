// Écran unique (docs/UI_Dashhound.md) : mascotte + chiffre, jauge « 45 s en mémoire », action
// principale selon l'état (connecter → démarrer → sauver), dernier clip ; détails lunettes/session en dessous ; réglages derrière l'engrenage.
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
          }
          .padding(.vertical, 8)
        }
        .listRowBackground(Palette.bg)

        if let clip = recorder.lastClip {
          Section("Dernier clip") { lastClipRow(clip) }
        }

        Section("Dashcam") {
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
          row("Bouton des lunettes", model.inputsStatus)
          row("« Hey Meta »", model.voiceStatus)
          row("Meta AI", model.registrationLabel)
        }
      }
      .scrollContentBackground(.hidden)
      .background(Palette.bg)
      .safeAreaInset(edge: .bottom) { dashcamBar }
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

  /// Action de la carte, seulement quand il y en a une : l'état lui-même est dit par la mascotte
  /// et la jauge (pas de pseudo-bouton qui répète « Je cherche tes lunettes… »).
  private enum PrimaryAction {
    case connect, allowCamera, save(Int)
  }

  private var primaryAction: PrimaryAction? {
    if !model.isRegistered { return .connect }
    if model.sessionState == .started, !model.isCameraGranted { return .allowCamera }
    guard recorder.isActive, recorder.availableSeconds > 0 else { return nil }
    return .save(recorder.availableSeconds)
  }

  @ViewBuilder private var primaryButton: some View {
    switch primaryAction {
    case .connect:
      primaryStyle("Connecter mes lunettes") { model.register() }
    case .allowCamera:
      primaryStyle("Autoriser la caméra…") { confirmCameraRedirect = true }
    case .save(let seconds):
      primaryStyle(recorder.isSaving ? "Sauvegarde…" : "Sauver les \(min(seconds, Int(recorder.bufferSeconds))) s") {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        Task { await recorder.save(trigger: .manual) }
      }
      .disabled(recorder.isSaving)
    case nil:
      EmptyView()
    }
  }

  /// Barre fixe en bas, toujours sous le pouce : l'action du moment (Sauver les N s, Connecter,
  /// Autoriser la caméra) puis Démarrer / Arrêter la dashcam.
  private var dashcamBar: some View {
    VStack(spacing: 8) {
      primaryButton
      if !model.isRegistered {
        EmptyView()
      } else if model.wantsSession {
        Button(role: .destructive) { model.stopSession() } label: {
          Label("Arrêter la dashcam", systemImage: "stop.fill")
            .font(.headline)
            .foregroundStyle(Palette.warn)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Palette.warn, lineWidth: 1.5))
        }
      } else {
        let ready = model.isRegistered && model.hasActiveDevice
        Button { model.startSession() } label: {
          Label("Démarrer la dashcam", systemImage: "record.circle")
            .font(.headline)
            .foregroundStyle(ready ? Palette.onHound : Palette.ink)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(ready ? Palette.hound : Palette.houndSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .disabled(!ready)
      }
    }
    .buttonStyle(.plain)
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .background(.bar)
  }

  private func primaryStyle(_ title: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(title)
        .font(.title2.bold())
        .monospacedDigit()
        .foregroundStyle(Palette.onHound)
        .frame(maxWidth: .infinity, minHeight: 72)
        .background(Palette.hound, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
    .buttonStyle(.plain)
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
