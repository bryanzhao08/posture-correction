# FormCoach: Xcode Deployment Guide

This guide will walk you through getting the FormCoach iOS app running on your own iPhone. It is written for first-time iOS developers. You will need a Mac (Apple Silicon, macOS 15.6) with Homebrew installed, about 50 GB of free disk space, your iPhone, and a cable to connect them.

## 1. Installing Xcode

Xcode is Apple's official development environment for iOS.

1. Open the **Mac App Store**.
2. Search for **Xcode** and click **Get** / **Install**. Note: This is a massive download and will require about 50 GB of free disk space to complete the installation.
3. Once installed, open Xcode from your Applications folder. It will prompt you to install additional required components. Agree to the prompts and let it finish.
4. Open the **Terminal** app and run the following command to ensure the command-line tools point to your new Xcode installation:
   ```bash
   sudo xcode-select -s /Applications/Xcode.app
   ```
5. You may need to open Xcode once to accept the license agreement, or run `sudo xcodebuild -license accept` in the terminal.

## 2. Generating the Xcode Project

Instead of checking the raw `.xcodeproj` into version control, FormCoach uses `xcodegen` to generate it from a clean configuration file.

1. In your Terminal, install XcodeGen via Homebrew:
   ```bash
   brew install xcodegen
   ```
2. Navigate to the `ios` directory in the FormCoach project:
   ```bash
   cd /path/to/FormCoach/ios
   ```
3. Generate the project:
   ```bash
   xcodegen generate
   ```
4. This will create a `FormCoach.xcodeproj` file. Open it in Xcode:
   ```bash
   open FormCoach.xcodeproj
   ```

## 3. Signing with a Free Apple ID

To run an app on a real device, it must be "signed" with an Apple Developer account. You can use your standard Apple ID as a free "Personal Team".

1. In Xcode, go to **Xcode > Settings** (or Preferences) in the menu bar.
2. Select the **Accounts** tab.
3. Click the **+** button at the bottom left, choose **Apple ID**, and sign in with your Apple account.
4. Close the Settings window.
5. In the left sidebar (Project Navigator), click on the top-level **FormCoach** project to open the settings.
6. Select the **FormCoach** target, and go to the **Signing & Capabilities** tab.
7. Check the box for **Automatically manage signing**.
8. In the **Team** dropdown, select your personal account (e.g., "Your Name (Personal Team)").
9. Change the **Bundle Identifier** to something unique so it doesn't conflict with others (e.g., `com.yourname.FormCoach`).

> **Note on Free Accounts:** A free Apple ID allows you to run the app on your device, but the app will expire and stop launching after 7 days (requiring you to plug in and rebuild). You are also limited in how many App IDs you can register per week. The paid Apple Developer Program ($99/year) removes these limits and is required for distributing via TestFlight or the App Store.

## 4. Preparing your iPhone

1. Connect your iPhone to your Mac using a USB cable.
2. If prompted on your iPhone, tap **Trust This Computer** and enter your passcode.
3. Enable **Developer Mode**:
   - On your iPhone, go to **Settings > Privacy & Security**.
   - Scroll down to **Developer Mode** and turn it on.
   - Your iPhone will prompt you to restart. After restarting, unlock it and confirm you want to enable Developer Mode.
4. Trust your Developer Certificate:
   - Go to **Settings > General > VPN & Device Management** (or Profiles & Device Management).
   - Under "Developer App", tap your Apple ID email.
   - Tap **Trust "[Your Email]"** to allow apps signed by your account to run.

## 5. Build and Run

1. In Xcode, look at the top center of the window. You will see a device selector (next to the Play button). Click it and select your physically connected iPhone.
2. Click the **Play button** (▶) or press `Cmd + R` to build and run the app.
3. Wait for the build to finish. Once done, FormCoach will launch on your iPhone.

> **Why not use the Simulator?** While Xcode includes an iOS Simulator, FormCoach relies on the iPhone's camera and Apple's Vision framework for pose tracking. The Simulator does not support the camera, so motion tracking requires a physical device.

## 6. Pointing the App at the Backend

FormCoach needs a backend server to store sessions and send emails. Since you're running it locally:

1. Open a Terminal and start the Python backend on your Mac. Ensure it listens on all network interfaces:
   ```bash
   cd /path/to/FormCoach/backend
   # Assuming you have set up the virtual environment
   .venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000
   ```
2. Find your Mac's local network IP address (e.g., go to System Settings > Network > Wi-Fi > Details, looking for an IP like `192.168.1.50`).
3. Ensure your iPhone is connected to the **same Wi-Fi network** as your Mac.
4. Open the FormCoach app on your iPhone, go to its Settings, and update the backend URL to `http://<your-mac-ip>:8000`.

## 7. Troubleshooting

| Problem | Solution |
|---|---|
| **"Failed to create provisioning profile"** (Xcode) | Ensure your Bundle Identifier is completely unique (e.g., `com.yourfirstname.formcoach123`). |
| **"Untrusted Developer"** pop-up on iPhone | Go to Settings > General > VPN & Device Management on your iPhone and trust your developer certificate. |
| **iPhone does not appear in Xcode's device list** | Unplug and replug the cable. Ensure the phone is unlocked and you've tapped "Trust This Computer". Restart Xcode. |
| **Developer Mode is missing in iOS Settings** | Your phone needs to be recognized by Xcode first. Connect the phone, open Xcode, wait a minute, then check Settings again. |
| **Camera permission denied** | Go to iOS Settings > FormCoach and toggle Camera permission on. |
| **Cannot reach backend / Network Error** | Verify your Mac and iPhone are on the same Wi-Fi. Ensure the backend is running with `--host 0.0.0.0`. Try accessing the URL in Safari on your iPhone. |

## 8. Shipping to the App Store

If you decide to distribute FormCoach to other users via TestFlight or the App Store, you will need to:
1. Enroll in the paid Apple Developer Program ($99/year).
2. Create App Store Connect records (App IDs, Provisioning Profiles).
3. Add App Store screenshots, privacy policies, and a description.
4. Archive the app in Xcode (`Product > Archive`) and distribute it to App Store Connect.
5. Pass Apple's App Review process.
