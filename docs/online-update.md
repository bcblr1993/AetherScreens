# macOS online updates

AetherScreens 1.1.0 introduces Sparkle 2.10.0. Select **AetherScreens → Check for Updates…** to check the HTTPS appcast, download a signed update and install/relaunch through Sparkle's standard UI. Automatic background checks/downloads are disabled by default. Sparkle manages busy state, errors and installation permissions.

The public appcast is https://aethernative.com/apps/aetherscreens/appcast.xml. Package Info.plist contains SUFeedURL, SUPublicEDKey and SUVerifyUpdateBeforeExtraction. The signing private key stays in the login Keychain under account `com.aethernative.aetherscreens`; `assets/update/sparkle-public-key.txt` is the public key only. Preserve the Keychain key for future releases; do not replace it casually or export it into this repository.

`scripts/package_release.sh` embeds/signs the Sparkle framework and nested installation helpers, notarizes/staples the app, generates archives/checksums and signs the final DMG using the official sign_update tool. `sparkle-signature.txt` contains public signature metadata to include in the release's aethernative block. The website release-sync tool verifies this signature before adding the update to its appcast.

Existing 1.0.0 installations have no updater. Install 1.1.0 manually once; subsequent releases can be installed from the app. This update mechanism applies to macOS, not iOS/TestFlight/App Store distribution. It does not load replacement Swift code into a running process; application updates become active after restart.

Do not claim full download/install/relaunch acceptance merely from compilation, notarization or a successful feed fetch. Verify those stages independently using an isolated older installed app on the authorized Mac mini.
