# Dashhound · Rewind

**Proof, 45 seconds early.** A retroactive dashcam for Ray-Ban Meta glasses.

Dashhound keeps the last 45 seconds of what your glasses see in memory (30 to 120, your choice) — and only saves them when you ask. Double-tap the temple, tap *Save* on your lock screen, or let a hard jolt trigger it. For the next time, it won't be your word against theirs.

*It looks back so you don't have to. It keeps. It doesn't watch.*

> **Dashhound is experimental software, provided as is. It may fail to save a clip. It is not a safety device and does not replace a certified dashcam. You are responsible for using it lawfully where you live.**

## How it works

1. Your glasses stream video (and their microphone) to your iPhone, using Meta's [Wearables Device Access Toolkit](https://github.com/facebook/meta-wearables-dat-ios).
2. Dashhound keeps a rolling memory in RAM — nothing is written to disk. Choose the clip length in the settings: **30, 45, 60, 90 or 120 seconds** (45 by default).
3. When you trigger a save, the last seconds of that length (a few more, so the clip always starts on a clean frame) go to **Photos**:
   - **double-tap the temple** of your glasses — recording never stops;
   - **Save** on the lock screen / Dynamic Island (Live Activity);
   - **impact detection** on the iPhone (beta) — saved 10 s after the jolt, so the clip holds the chosen length before *plus* the 10 s after;
   - a long press on the glasses' capture button (saves before the glasses take the camera back).

The dashcam only stops when you tap **Stop**. If the glasses are busy or out of range, it keeps what it filmed and resumes on its own.

The capture LED of your glasses stays on the whole time. Dashhound never hides it — the app even shows it.

## Status

Built in the first week of Meta's DAT 1.0.0 (released 24 Sep 2026), every blocker documented: see [`P0_VERDICT.md`](P0_VERDICT.md) and [`P1_VERDICT.md`](P1_VERDICT.md) (**provisional** — the list of tests still to run is in the file). Measured so far: clips of 45–48 s at 24 fps with no dropped frames, working with the screen locked; the double tap saved 4/4 times on a real ride.

## Known limitations

Honest list, updated as we learn. Most come from the glasses platform (Meta developer preview), not from the app.

- **Any other app using the glasses microphone (WhatsApp call, voice message, dictation) ends the camera stream;** Dashhound keeps what it filmed and resumes ~4 s after the mic is released.
- **No music or voice navigation in the glasses while Dashhound runs.** When the glasses camera streams, the glasses stop playing Bluetooth audio (Meta issue [#256](https://github.com/facebook/meta-wearables-dat-ios/issues/256), reported with measurements in [#312](https://github.com/facebook/meta-wearables-dat-ios/issues/312)). Audio routed to another speaker keeps working.
- **A single tap on the temple pauses the glasses camera** (~4 s gap while Dashhound resumes). The clip is saved anyway, but **use a double tap**: it saves without any gap.
- **No official background mode.** To keep filming with the screen locked, Dashhound plays silence in a loop (inaudible, and it doesn't stop your other apps' audio).
- **Battery:** a full charge of the glasses lasts roughly **35 to 43 minutes** of dashcam — about one ride.
- **Impact detection is in beta.** The threshold (**16 g by default**, adjustable) comes from real rides with the phone in a pocket, where potholes reached 9–14 g; it may miss an event or trigger when it shouldn't.
- **Video is 360×640** at 24 fps: at higher resolution the glasses drop quality on their own.
- **Not on the App Store.** Meta's toolkit is in developer preview: you build and install Dashhound yourself with Xcode, and with a free Apple account the app must be re-installed **every 7 days**.
- **"Hey Meta, start Dashhound"** is wired in the app but can't be enabled yet: Voice Invocations is not available in Meta's Developer Center ([#311](https://github.com/facebook/meta-wearables-dat-ios/issues/311)).
- iPhone only. Tested with one pair of Ray-Ban Meta glasses and iOS 27.

## What we need from Meta

Most limitations above can only be lifted by Meta: keeping the camera running while another app uses the microphone, receiving a single tap without pausing the stream, Bluetooth audio during a stream, and an official background mode. The full list — prioritized, each with its measurement — is in [`docs/Meta_Asks.md`](docs/Meta_Asks.md); the tap and audio issues are filed as [#312](https://github.com/facebook/meta-wearables-dat-ios/issues/312).

## Install

Step by step, no prior coding needed: **[INSTALL.md](INSTALL.md)** (about 30 minutes the first time).

## Privacy

No account, no server, no analytics; clips stay on your phone and calls are never recorded. Details: [PRIVACY.md](PRIVACY.md) · legal notice: https://dashhoundrewind.com/legal

## Feedback

In the app: **Settings › Help › Report a bug / Suggest an idea** (opens a pre-filled issue). Or [open an issue](https://github.com/jsala1/dashhound/issues/new/choose) — there is a form for installation help too.

## License

[MIT](LICENSE) for the code in this repository. Meta's toolkit is fetched at build time and stays under the Meta Wearables Developer Terms.

Dashhound is an independent project. It is not affiliated with, endorsed by or sponsored by Meta or Ray-Ban.
