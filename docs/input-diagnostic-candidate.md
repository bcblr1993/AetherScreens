# Merged input and preferences diagnostic candidate

The candidate combines the independently verified source-195 native preference
bridge with the frozen build-3 input/Return fixes and payload-free diagnostics.
The main C137 source and the input D3_184 source are unchanged. Three-way merge
evidence is in build/merged-input-preferences-qa/three-way-input-merge.json.

Ordinary app bundles still require the explicit launch environment
AETHERSCREENS_INPUT_DIAGNOSTICS=1. A separately signed development diagnostic
package can instead contain the Boolean Info.plist key
AetherScreensDevelopmentInputDiagnostics=true. This lets a physical tester
open the installed diagnostic app normally while collecting the same bounded
input-v1.json file. Missing/false flags keep ordinary startup disabled.

Only the existing typed stages/flags, bounded button masks, Return down/up,
Apple status values and random diagnostic session IDs can enter the schema.
Passwords, committed text, clipboard contents, key values, pointer coordinates,
remote addresses and account names are not diagnostic fields. Local network
send completion still does not prove remote input execution.

Build 4 is a development diagnostic package, not a public release. Packaging
copies the freshly built app into a separately named immutable output, sets
its Boolean diagnostic flag, re-signs it using the same development identity
and verifies its exact signature, bundle version, profile eligibility and
source manifest. The normal app build is left with the flag absent. No public
version, entitlement, profile capability or release configuration is changed.

The actual CloudKit signing profile is not yet configured: inspection of the
frozen D3 profile found no CloudKit container/service entitlement. Native
metadata/preferences sync implementation does not accept real iCloud or
credential sync. Current-source complete VM UI, two physical iPhones, actual
Apple dual displays, typing/Return/IME and fluid interaction remain required.
Previous separate candidate UI results cannot be counted for this merged source.
