// Extension widget : Live Activity de la dashcam (écran verrouillé + Dynamic Island).
// Palette reprise de docs/UI_Dashhound.md ; carte « papier » fixe comme la MascotCard.
import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct DashhoundWidgetBundle: WidgetBundle {
  var body: some Widget {
    DashhoundLiveActivity()
  }
}

private enum Tone {
  static let paper = Color(red: 0xFC / 255, green: 0xF8 / 255, blue: 0xF4 / 255)
  static let ink = Color(red: 0x1E / 255, green: 0x1A / 255, blue: 0x17 / 255)
  static let inkMuted = Color(red: 0x7A / 255, green: 0x6F / 255, blue: 0x66 / 255)
  static let hound = Color(red: 0xF8 / 255, green: 0x75 / 255, blue: 0x21 / 255)
  static let led = Color(red: 0x4D / 255, green: 0xA3 / 255, blue: 0xFF / 255)
}

struct DashhoundLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: DashcamActivityAttributes.self) { context in
      LockScreenView(state: context.state, startedAt: context.attributes.startedAt)
        .activityBackgroundTint(Tone.paper)
        .activitySystemActionForegroundColor(Tone.ink)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          Image("dashhound-face-alert").resizable().scaledToFit()
            .frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 10))
        }
        DynamicIslandExpandedRegion(.trailing) {
          Text(context.attributes.startedAt, style: .timer).font(.title3.bold().monospacedDigit())
            .multilineTextAlignment(.trailing)
        }
        DynamicIslandExpandedRegion(.center) {
          Text(statusLine(context.state)).font(.headline)
        }
        DynamicIslandExpandedRegion(.bottom) {
          SaveButton(state: context.state)
        }
      } compactLeading: {
        Circle().fill(Tone.led).frame(width: 8, height: 8)
      } compactTrailing: {
        Text(context.attributes.startedAt, style: .timer).monospacedDigit().frame(maxWidth: 56)
      } minimal: {
        Circle().fill(Tone.led).frame(width: 8, height: 8)
      }
    }
  }
}

private func statusLine(_ state: DashcamActivityAttributes.ContentState) -> String {
  state.isPaused ? String(localized: "Reprise automatique…") : String(localized: "Je regarde")
}

private struct LockScreenView: View {
  let state: DashcamActivityAttributes.ContentState
  let startedAt: Date

  var body: some View {
    HStack(spacing: 12) {
      Image("dashhound-face-alert").resizable().scaledToFit()
        .frame(width: 52, height: 52)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 6) {
          Circle().fill(Tone.led).frame(width: 8, height: 8)
          Text("Dashhound regarde").font(.headline).foregroundStyle(Tone.ink)
        }
        HStack(spacing: 6) {
          Text(statusLine(state))
          Text(startedAt, style: .timer).monospacedDigit()
        }
        .font(.subheadline).foregroundStyle(Tone.ink)
        if let last = state.lastClipAt {
          Text("Dernier clip à \(last.formatted(date: .omitted, time: .shortened))")
            .font(.caption).foregroundStyle(Tone.inkMuted)
        }
      }
      Spacer(minLength: 8)
      SaveButton(state: state)
    }
    .padding(14)
  }
}

private struct SaveButton: View {
  let state: DashcamActivityAttributes.ContentState

  var body: some View {
    Button(intent: SaveClipIntent()) {
      (state.isSaving ? Text(verbatim: "…") : Text("Sauver"))
        .font(.headline)
        .foregroundStyle(Tone.ink)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Tone.hound, in: Capsule())
    }
    .buttonStyle(.plain)
    .disabled(state.isSaving)
  }
}
