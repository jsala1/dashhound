// Écran unique (docs/UI_Dashhound.md) : mascotte + chiffre, jauge « 45 s en mémoire », action
// principale selon l'état (connecter → démarrer → sauver), dernier clip ; détails lunettes/session en dessous ; réglages derrière l'engrenage.
import SwiftUI

struct ContentView: View {
  @Bindable var model: WearablesModel
  @State private var confirmCameraRedirect = false
  @State private var confirmMicrophoneRedirect = false
  @State private var showSettings = false
  @AppStorage("disclaimerAccepted") private var disclaimerAccepted = false

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
          row("Appareil", model.deviceName ?? (model.hasActiveDevice ? "…" : String(localized: "aucun")))
          row("Batterie", model.batteryLevel.map { "\($0) %" } ?? "—")
          DisclosureGroup("Détails techniques") {
            row("Thermique", model.thermal)
            row("Session", model.sessionState.description)
            row("Stream", String(describing: model.streamState))
            row("Bouton des lunettes", model.inputsStatus)
            row("« Hey Meta »", model.voiceStatus)
            row("Meta AI", model.registrationLabel)
          }
          .font(.subheadline)
        }
      }
      .scrollContentBackground(.hidden)
      .background(Palette.bg)
      .safeAreaInset(edge: .bottom) { dashcamBar }
      .navigationTitle("Dashhound · Rewind")
      .toolbar {
        Button { showSettings = true } label: { Image(systemName: "gearshape") }
          .accessibilityLabel("Réglages")
      }
      .sheet(isPresented: $showSettings) { SettingsView(model: model) }
      .fullScreenCover(isPresented: Binding(get: { !disclaimerAccepted }, set: { _ in })) {
        DisclaimerView { disclaimerAccepted = true }
      }
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
      primaryStyle(Text("Connecter mes lunettes")) { model.register() }
    case .allowCamera:
      primaryStyle(Text("Autoriser la caméra…")) { confirmCameraRedirect = true }
    case .save(let seconds):
      primaryStyle(recorder.isSaving ? Text("Sauvegarde…") : Text("Sauver les \(min(seconds, Int(recorder.bufferSeconds))) s")) {
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
        Button { model.userStartSession() } label: {
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

  private func primaryStyle(_ title: Text, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      title
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
        (clip.savedToPhotos ? Text("Dans Photos") : Text("Gardé dans l'app (pas dans Photos)"))
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

  private func row(_ label: LocalizedStringKey, _ value: String) -> some View {
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
          Text("Le son est coupé pendant un appel : les conversations ne sont jamais enregistrées.")
        }
        Section {
          Toggle("Détection de choc", isOn: $recorder.impactDetectionEnabled)
          Picker("Seuil", selection: $recorder.impactThreshold) {
            ForEach(ImpactThreshold.allCases) { Text($0.label).tag($0) }
          }
          .disabled(!recorder.impactDetectionEnabled)
        } header: {
          Text("Choc (iPhone) — bêta")
        } footer: {
          Text("Un choc sauve automatiquement, 10 s après : environ 35 s avant et 10 s après. En test : sur un vrai trajet, téléphone en poche, les nids-de-poule montent jusqu'à ~9 g — d'où 12 g par défaut.")
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
        Section {
          Link(destination: Feedback.url(template: "bug")) {
            Label("Signaler un bug", systemImage: "ladybug")
          }
          Link(destination: Feedback.url(template: "idea")) {
            Label("Suggérer une idée", systemImage: "lightbulb")
          }
        } header: {
          Text("Aide")
        } footer: {
          Text("Ouvre un ticket GitHub pré-rempli avec la version de l'app, le modèle d'iPhone et la version d'iOS — rien d'autre n'est envoyé. \(Feedback.versionLine)")
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

/// Premier lancement : Dashhound est expérimental — il faut l'avoir lu avant de s'en servir.
private struct DisclaimerView: View {
  let onAccept: () -> Void

  var body: some View {
    VStack(spacing: 24) {
      Spacer(minLength: 12)
      Image("dashhound-face-wink").resizable().scaledToFit()
        .frame(width: 160, height: 160)
        .background(Palette.mascotPaper, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityHidden(true)
      Text("Avant de commencer").font(.title.bold()).foregroundStyle(Palette.ink)
      Text(
        "Dashhound est un logiciel expérimental, fourni tel quel. Il peut ne pas réussir à sauver un clip. Ce n'est pas un dispositif de sécurité et il ne remplace pas une dashcam certifiée. Tu es responsable de l'utiliser légalement là où tu vis."
      )
      .font(.body)
      .foregroundStyle(Palette.ink)
      .multilineTextAlignment(.center)
      .fixedSize(horizontal: false, vertical: true)
      Spacer()
      Button(action: onAccept) {
        Text("J'ai compris")
          .font(.title3.bold())
          .foregroundStyle(Palette.onHound)
          .frame(maxWidth: .infinity, minHeight: 60)
          .background(Palette.hound, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
      }
      .buttonStyle(.plain)
    }
    .padding(24)
    .background(Palette.bg)
    .interactiveDismissDisabled()
  }
}

/// Liens vers les tickets GitHub pré-remplis (formulaires .github/ISSUE_TEMPLATE/).
enum Feedback {
  static let repo = "https://github.com/jsala1/dashhound"

  static var appVersion: String {
    let info = Bundle.main.infoDictionary
    let version = info?["CFBundleShortVersionString"] as? String ?? "?"
    let build = info?["CFBundleVersion"] as? String ?? "?"
    return "\(version) (\(build))"
  }

  static var deviceModel: String {
    var system = utsname()
    uname(&system)
    return withUnsafeBytes(of: &system.machine) { raw in
      String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
    }
  }

  static var versionLine: String {
    "Dashhound \(appVersion) · \(deviceModel) · iOS \(UIDevice.current.systemVersion)"
  }

  static func url(template: String) -> URL {
    var components = URLComponents(string: "\(repo)/issues/new")!
    components.queryItems = [
      URLQueryItem(name: "template", value: "\(template).yml"),
      URLQueryItem(name: "app-version", value: appVersion),
      URLQueryItem(name: "iphone", value: deviceModel),
      URLQueryItem(name: "ios", value: UIDevice.current.systemVersion),
    ]
    return components.url!
  }
}
