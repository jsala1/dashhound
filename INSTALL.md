# Install Dashhound

About **30 minutes** the first time, no coding. You need: a **Mac**, an **iPhone** (iOS 17.2 or later) with its cable, **Ray-Ban Meta glasses** paired with the **Meta AI** app, and a free **Apple ID**. Nothing to pay.

Stuck at a step? [Open an installation issue](https://github.com/jsala1/dashhound/issues/new?template=install.yml) with the step number and the exact error.

## 1. Install Xcode

Install **Xcode** from the Mac App Store (free, large download). Open it once and accept everything it asks to install (including the **iOS** platform). Then open **Terminal** (⌘ Space, type *Terminal*) and run:

```
sudo xcodebuild -license accept
```

(type your Mac password — nothing shows while you type, that's normal).

## 2. Turn on Developer Mode on the iPhone

Plug the iPhone into the Mac and unlock it; tap **Trust** if asked. On the iPhone: **Settings › Privacy & Security › Developer Mode › On**. The iPhone restarts; after restart, confirm **Turn On**.

## 3. Turn on Developer Mode in the Meta AI app

In **Meta AI**, make sure your glasses and their firmware are up to date. Then: **Settings › App info**, tap the **version number 5 times**, and turn on **Developer Mode** (on some versions: **Settings › your glasses › Developer Mode**). It may switch off after a firmware update — turn it back on.

## 4. Download Dashhound

On [the repository page](https://github.com/jsala1/dashhound): **Code › Download ZIP**, then double-click the ZIP. Move the `dashhound-main` folder somewhere easy, e.g. your **Documents** folder.

## 5. Run the setup script

In **Terminal**, type `cd ` (with a space), **drag the `dashhound-main` folder onto the Terminal window**, press Enter, then run:

```
scripts/bootstrap.sh
```

It checks Xcode, installs **XcodeGen** (needs [Homebrew](https://brew.sh) — install it first if the script asks) and generates the Xcode project. It never deletes anything.

## 6. Add your Apple ID to Xcode

In Xcode: **Settings › Accounts › + › Apple ID**, sign in. A free account gives you a **Personal Team**. Then run the script again:

```
scripts/bootstrap.sh
```

It finds your Team ID and writes it, with a unique app identifier, into `Config.xcconfig` (a file that stays on your Mac).

## 7. Check the app identifier

Open `Config.xcconfig` (in the `dashhound-main` folder) with TextEdit. You should see your Team ID and an identifier like `com.dashhound.uabcde12345`. It must be unique to you — if Xcode later says the identifier *is not available*, change the end of it (letters and digits only), save, and run `scripts/bootstrap.sh` again.

## 8. Run it on the iPhone

Open the project: `open Dashcam.xcodeproj` (or double-click `Dashcam.xcodeproj`). At the top of Xcode, pick **your iPhone** as the destination, then press **▶︎ Run**. The first build downloads Meta's toolkit and takes a few minutes.

If the iPhone says the developer is not trusted: **Settings › General › VPN & Device Management ›** your Apple ID **› Trust**, then press **▶︎ Run** again.

With a free Apple account, the app stops opening after **7 days**: just press **▶︎ Run** again with the iPhone plugged in.

## 9. First launch

Read and accept the notice. Put your glasses on, then: **Connect my glasses** → approve Dashhound in Meta AI → come back. Tap **Start dashcam**, then allow the **camera** and the **glasses microphone** when Dashhound asks (it opens Meta AI each time), and allow Photos, Bluetooth and local network when iOS asks. The dog should say *"Watching."* and the gauge fills up to 45 s.

## 10. First save

Wait until the gauge shows **45 s**, then **double-tap the temple** of your glasses. The iPhone vibrates, the dog says *"Saved!"*, and a 45–48 s clip appears in **Photos**. Try it with the screen locked too: the **Save** button on the lock screen does the same.

That's it. Please read the [Known limitations](README.md#known-limitations) — especially: no music in the glasses while Dashhound runs, and a battery that lasts about one ride.
