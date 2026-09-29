# What Dashhound needs from Meta's Wearables toolkit

Dashhound is a retroactive dashcam for Ray-Ban Meta glasses: the glasses stream to the iPhone, the app keeps the last 30–120 s in memory and saves a clip on a double tap, a lock-screen button or an impact. Built on DAT 1.0.0 (iOS) in its first week, every blocker measured — see `P0_VERDICT.md` and `P1_VERDICT.md`. This is the list of what would turn it from a working prototype into something people can rely on, most important first.

Setup for all measurements: DAT iOS 1.0.0, one pair of Ray-Ban Meta glasses, iPhone 16 Pro on iOS 27, hvc1 360×640 @ 24 fps with PCM audio from the stream, Developer Mode.

## 1. Keep the camera stream when another app uses the microphone (calls, voice messages, dictation)

**Today:** anything that uses the glasses **microphone** in another app — a WhatsApp call or voice message, iOS dictation, a phone call to voicemail — switches the glasses to the hands-free profile and ends the camera session about 1 s later (`Session ended by device`); new sessions fail with `Device unavailable` until the microphone is released. (One regular phone call on 27/09 kept the stream; a call to voicemail on 29/09 did not.)
**Why it matters:** a dashcam must keep watching while you are on a call — that is when attention drops.
**Ask:** keep an active camera stream alive during VoIP calls (the audio side can stay with the call), or at least expose a clear session state/reason ("glasses busy: call") and resume automatically when the call ends.

## 2. Let the app receive a single tap / capture press without pausing the stream

**Today:** a single touchpad tap or a short capture press never reaches `MWDATInputs` while streaming — the device pauses the session instead, and the app may not resume it. Our workaround (save on pause, stop, start a new session after the 2 s floor from #231) leaves a **~4.3 s gap**. A **double tap** arrives as `.select(captouch)` without any pause — so the input path exists.
**Ask:** an `InputsConfiguration` option (e.g. `consumeTap`, `consumeCapture`) so an app with an active stream receives the event instead of the device pausing. Filed as **#312**.

## 3. Allow Bluetooth audio playback while the camera streams

**Today:** music and navigation prompts stop in the glasses ~2 s after the stream starts and stay silent when resumed — identical at 24, 15 and 7 fps and with no audio codec at all (stop 0.01 s after `.streaming`); the same playback routed to another speaker works. The app receives no audio interruption. Known as **#256**, measurements added in **#312**.
**Why it matters:** riders listen to music or GPS; today they must choose between that and the dashcam.
**Ask:** keep A2DP playback running during a camera stream (even at reduced quality), or document the constraint and a supported alternative.

## 4. A supported way to stream in the background

**Today:** with the documented background modes, iOS suspends the app ~2 s after the screen locks; the glasses then end the session ~20 s later. The only thing that works is playing silent audio in a loop (measured: 2 min 53 s locked, 0 suspension, 24 fps).
**Ask:** an officially supported background mode or entitlement for DAT streaming apps, so apps don't rely on a silent-audio workaround.

## 5. Open Voice Invocations, Inputs and Motion in the Developer Center

**Today:** the docs say to request these capabilities, but the Developer Center only shows *Camera access* and *Microphone access* — no entry for Voice Invocations (same as **#311**), Inputs or Motion. Inputs happen to work in Developer Mode; "Hey Meta, start Dashhound" cannot be tested.
**Ask:** expose these capabilities (or document how to get them), so "Hey Meta, save that" becomes possible.

## 6. Keep a small buffer on the glasses

**Today:** everything depends on the phone link. When it drops — a call, Bluetooth loss, folding the glasses — nothing is filmed until it comes back (reconnection itself works: 5.7 s after unfolding).
**Ask (bigger):** an API to keep the last N seconds on the glasses and transfer them on request, so a clip survives short link losses.

## 7. Smaller things we hit

- **Keyframe flag missing:** hvc1 `VideoFrame.sampleBuffer`s have no `kCMSampleAttachmentKey_NotSync`, so apps must parse NAL units to find keyframes (the sample app does the same). Setting the attachment would make passthrough recording simpler and safer.
- **Silent resolution changes:** at 504×896 with stream audio, the stream drops to 360×640 and ~15 fps on its own (22 % of the time) with no event — a mid-clip format change can break passthrough writing. An event, or a "don't adapt" option, would help.
- **Wi-Fi transport and free Apple accounts:** the sample's Hotspot / Wi-Fi Information entitlements are refused for Personal Teams, so hobbyists stay on Bluetooth only (lower resolution). A path that doesn't need them would help.
- **Battery:** ~2.3–2.8 %/min while streaming (≈ 35–43 min from full). Power-saving stream options or guidance would help riders plan.
- **Device name:** `Device.name` returns "0018", not the name the user gave the glasses in Meta AI.
- **Microphone permission flow:** once, `requestPermission(.microphone)` switched to Meta AI and never came back to the app.
- **Distribution:** no way to share a build with testers outside Xcode (developer preview): a TestFlight-compatible path for DAT apps would open it to non-developers.

## What already works well

Registration, sessions and hvc1 streaming were solid from day one; reconnection after folding the glasses is automatic (5.7 s); the double tap arrives cleanly; stream audio is in sync; passthrough recording produced clips of 45–48 s with no dropped frames across dozens of saves.

*Julian Salaun — Dashhound · Rewind — github.com/jsala1/dashhound*
