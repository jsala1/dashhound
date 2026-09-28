# Dashhound · Rewind

**Proof, 45 seconds early.** A retroactive dashcam for Ray-Ban Meta glasses.

Dashhound keeps the last 45 seconds of what your glasses see in memory — and only saves them when you ask. Double-tap the temple, tap *Save* on your lock screen, or let a hard jolt trigger it. For the next time, it won't be your word against theirs.

*It looks back so you don't have to. It keeps. It doesn't watch.*

> **Dashhound is experimental software, provided as is. It may fail to save a clip. It is not a safety device and does not replace a certified dashcam. You are responsible for using it lawfully where you live.**

## How it works

1. Your glasses stream video (and their microphone) to your iPhone, using Meta's [Wearables Device Access Toolkit](https://github.com/facebook/meta-wearables-dat-ios).
2. Dashhound keeps a rolling **45-second memory** in RAM — nothing is written to disk.
3. When you trigger a save, the last **45–48 seconds** (always starting on a clean frame) go to **Photos**:
   - **double-tap the temple** of your glasses — recording never stops;
   - **Save** on the lock screen / Dynamic Island (Live Activity);
   - **impact detection** on the iPhone (beta) — saved 10 s after the jolt, so the clip holds the moment before *and* just after;
   - a long press on the glasses' capture button (saves before the glasses take the camera back).

The capture LED of your glasses stays on the whole time. Dashhound never hides it — the app even shows it.

## Status

Built in four days on a four-day-old SDK, every blocker documented: see [`P0_VERDICT.md`](P0_VERDICT.md) and [`P1_VERDICT.md`](P1_VERDICT.md) (**provisional** — the list of tests still to run is in the file). Measured so far: clips of 45–48 s at 24 fps with no dropped frames, working with the screen locked; the double tap saved 4/4 times on a real ride.

## Known limitations

Honest list, updated as we learn. Most come from the glasses platform (Meta developer preview), not from the app.

- **No music or voice navigation in the glasses while Dashhound runs.** When the glasses camera streams, the glasses stop playing Bluetooth audio (Meta issue [#256](https://github.com/facebook/meta-wearables-dat-ios/issues/256), reported with measurements in [#312](https://github.com/facebook/meta-wearables-dat-ios/issues/312)). Audio routed to another speaker keeps working.
- **A single tap on the temple pauses the glasses camera** (~4 s gap while Dashhound resumes). The clip is saved anyway, but **use a double tap**: it saves without any gap.
- **Battery:** a full charge of the glasses lasts roughly **20 to 45 minutes** of dashcam — about one ride.
- **Impact detection is in beta.** The threshold (12 g by default, adjustable) comes from one real ride with the phone in a pocket; it may miss an event or trigger when it shouldn't.
- **Video is 360×640** at 24 fps: at higher resolution the glasses drop quality on their own.
- **Not on the App Store.** Meta's toolkit is in developer preview: you build and install Dashhound yourself with Xcode, and with a free Apple account the app must be re-installed **every 7 days**.
- **"Hey Meta, start Dashhound"** is wired in the app but not validated yet.
- iPhone only. Tested with one pair of Ray-Ban Meta glasses and iOS 27.

## Install

Step by step, no prior coding needed: **[INSTALL.md](INSTALL.md)** (about 30 minutes the first time).

## Privacy

No account, no server, no analytics; clips stay on your phone and calls are never recorded. Details: [PRIVACY.md](PRIVACY.md) · legal notice: https://dashhoundrewind.com/legal

## Feedback

In the app: **Settings › Help › Report a bug / Suggest an idea** (opens a pre-filled issue). Or [open an issue](https://github.com/jsala1/dashhound/issues/new/choose) — there is a form for installation help too.

## License

[MIT](LICENSE) for the code in this repository. Meta's toolkit is fetched at build time and stays under the Meta Wearables Developer Terms.

Dashhound is an independent project. It is not affiliated with, endorsed by or sponsored by Meta or Ray-Ban.
