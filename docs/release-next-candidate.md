# Next release candidate

User authorized a new release after this phase is complete (2026-10-09). Current public release is v1.0.0. Candidate metadata is synchronized to 1.1.0, build 2026100901.

## Candidate behavior to verify

- Standard RFB advertises bounded Tight decoding with ZRLE/Zlib/Raw fallbacks. Fill, copy, palette, gradient, JPEG and four persistent streams are implemented.
- Optional automatic compression uses actual completed pixel payload receive duration. Three slow samples downgrade, eight fast samples recover, and a ten-second cooldown prevents repeated switching. Idle/small transfers do not indicate congestion.
- Compression hints update on the existing TCP socket without changing desktop size or manual color precision. A server may ignore hints. Native Apple sessions retain their own display configuration.
- Preferences are independent per computer; temporary sessions do not save them. Foreground, connection and quality generations reject stale callbacks.

## Evidence and remaining gates

The complete Tight receive gate passed 752 tests with 28 explicitly skipped and no failures before automatic-quality integration: /tmp/aetherscreens-full-core-tight-20261009.log. Automatic-quality preference/policy regression passed eight tests, and the generic unsigned iOS build succeeded: /tmp/aetherscreens-automatic-quality-preferences-20261009.log and /tmp/aetherscreens-ios-automatic-quality-20261009.log.

Same-socket quality messages passed actual TCP verification: /tmp/aetherscreens-quality-same-socket-20261009.log. Corrected slow-transfer downgrade and same-socket regression passed two tests: /tmp/aetherscreens-automatic-quality-slow-network-final-20261009.log. Recovery after fast transfers is being verified at /tmp/aetherscreens-automatic-quality-network-recovery-20261009.log.

Before publication, complete the latest full regression, real server interoperability and final installed-candidate UI/device acceptance. Review all intended changes in this dirty checkout before committing; preserve unrelated files. Synchronize version/build metadata, pass remote CI, sign/notarize/staple the final app, inspect the mounted DMG and checksum, publish matching assets, update the website and verify live downloads. Earlier v1.0.0 acceptance is historical and does not accept this candidate. iOS source builds do not constitute an App Store/TestFlight release.

Latest checkpoint: actual TCP downgrade and recovery passed with matching server-received hints (-26 then -23), one socket and byte-correct final pixels. Nine related tests passed in /tmp/aetherscreens-automatic-quality-recovery-full-write-20261009.log. The fast phase flushes complete rectangles; the slow phase withholds half the payload for 350 ms. Earlier split-write recovery fixtures produced approximately 100 ms receives that correctly interrupted consecutive fast samples; those failures are retained as diagnostic evidence. The production thresholds were not relaxed. The iOS native-mode switch-state build passed at /tmp/aetherscreens-ios-quality-native-state-20261009.log. Latest full regression passed 759 tests, 28 explicit skips, zero failures in 200.353 seconds: /tmp/aetherscreens-full-core-adaptive-quality-20261009.log.

No new version has been published. Full Screens parity, actual motion/typing/pointer behavior and energy/hitch measurements remain separate acceptance requirements.

The current candidate also passed a 60-second authenticated, read-only Mac mini session at 192.168.50.226, receiving 3840×2160 frames. This verifies default RFB interoperability, not server adoption of JPEG hints or native/UI acceptance. Log: /tmp/aetherscreens-macmini-current-candidate-20261009.log. Candidate packaging uses a separate output directory to preserve previous release artifacts.

User directed packaging/publication to pause on 2026-10-09. Finish compilation/tests and submit/push this phase first. Version 1.1.0/build 2026100901 remains candidate metadata; no tag, public release or website download update is authorized in this paused step.

Pause-and-submit checkpoint: Debug regression completed 759 tests with 28 explicit skips and zero failures in 244.150 seconds (/tmp/aetherscreens-package-1.1.0-2026100901.log). The packaging parent was stopped before signing, allowed its test child to finish, and then terminated; no signing/notarization/publication was performed for this candidate. Updated-metadata iOS Release compilation passed (/tmp/aetherscreens-ios-1.1.0-build-2026100901.log). Original upstream license/notice whitespace is preserved verbatim; source whitespace checks excluding those notices pass.

macOS arm64 Release build passed in 70.80 seconds (/tmp/aetherscreens-macos-compile-20261009.log). Debug and Release regression, iOS Release compilation and macOS Release compilation are now locally green. Packaging remains paused; committing/pushing does not release version 1.1.0.

Initial remote CI exposed an older-SDK compilation failure: IntentModes is absent from its AppIntents SDK. Removed the redundant supportedModes declaration while retaining openAppWhenRun=true for foreground launch across supported SDKs. Validate focused saved-computer intent tests and rebuild before the corrective push; remote CI will rerun the full suite.

Corrective validation passed: SavedComputerIntentTests (2 tests, zero failures), macOS arm64 Release build (73.04 seconds), and iOS Release build. Logs: /tmp/aetherscreens-ci-intent-sdk-fix-20261009.log, /tmp/aetherscreens-macos-intent-sdk-fix-20261009.log and /tmp/aetherscreens-ios-intent-sdk-fix-20261009.log.
