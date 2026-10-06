# Saved-connection synchronization development

## Current credential bridge candidate

The credential bridge uses system generic-password keychain items. Cloud items explicitly use
`kSecAttrSynchronizable = true`, the provisioned shared access group, the data protection keychain,
and AfterFirstUnlock accessibility. Local pending/cache items explicitly disable synchronization
and use AfterFirstUnlockThisDeviceOnly. Security calls disallow interactive authentication.
Writes update before insert and retry a duplicate insert without first deleting the old value.
[Apple: synchronizable keychain items](https://developer.apple.com/documentation/security/ksecattrsynchronizable)
and [access groups](https://developer.apple.com/documentation/security/ksecattraccessgroup)
describe the required signed capabilities; none have been enabled by this development phase.

The service namespace hashes the configured container and previously verified metadata owner.
Secrets, private keys, passphrases and their parent digests stay in encrypted keychain records;
preferences contain only a bounded UUID/kind queue index. VNC/Mac passwords and SSH credentials
bind to the complete saved connection, including the jump configuration. Presentation changes do
not invalidate that binding. SSH host-key approvals remain in the separate local SSH store and
are never migrated, replaced or synchronized by this bridge.

The actual DeviceStore save, edit, clear, delete and connection-read paths use the configured
provider. Local legacy entries cannot follow an edited endpoint/account, including after restart.
A new imported computer can read only a matching bound keychain credential; otherwise existing
invalidation still prevents reuse of a UUID-only legacy secret. Explicit clear/delete operations
leave empty keychain tombstones so older local installations cannot bootstrap the removed secret.
Permanent metadata deletions remove pending values for both credential kinds.

The app controller can recover the LOCAL encrypted queue for its prior bound owner before offline
edits, without enabling cloud access. After metadata fetch, import, conditional publication and
account verification, it enables the provider, retries pending records and bootstraps legacy
values insert-only. Storage/background/account changes disable cloud access while retaining
locally saved credentials for the same owned library; metadata never automatically rebinds to a
new account. A credential failure cannot report the configured exchange as synchronized. Two
new user-facing error messages have English and Simplified Chinese translations.

A failed cloud write preserves the encrypted local queue. Retry checks the cached parent and
reports a known conflict instead of overwriting a known newer remote value; only a new explicit
save may rebase it. A changed/deleted connection cannot relabel or upload a stale secret. These
checks are local safeguards, not distributed compare-and-swap: the operating system's eventual
keychain synchronization still needs real multi-device race/account acceptance. Simulated restart
and failed-write tests do not prove signed-app termination, disk power-loss durability, iCloud
Keychain delivery or account-switch behavior on actual devices.

The production transport and credential factories still default to nil. No user's password,
private key, host-key approval or CloudKit document was accessed or uploaded. The code is awaiting
registered container/shared access-group provisioning and real signed-app acceptance. Headless
credential tests use injected fake backends and synthetic generated keys; UI automation must
still run in macos27, and the two physical iPhones require separate input acceptance.

Evidence for this source is recorded under build/credential-sync-qa. The older merged source198
and signed diagnostic build4 remain immutable historical input/preference acceptance candidates.
This credential phase changes no release number, provisioning profile, signing capability, phone
installation or website. All full UI and physical gates remain open.

## Historical development stages

The notes below describe their original stages and do not replace the current candidate gates.

This work lives in the isolated `screens-sync` worktree. The main workspace stays at the frozen
pinch/click candidate so its outstanding VM and physical-device checks can continue unchanged.

The implementation adds a credential-free `DeviceSyncDocument`, an offline `DeviceSyncStore`,
an account-bound transport, and a replica adapter for the actual `DeviceStore` saved library.
The storage selector and foreground coordinator are connected to app settings.
The current build has no provisioned CloudKit transport; it displays a localized unavailable
state without constructing CKContainer or accessing an iCloud account.
No saved user data has been uploaded, and this is not end-to-end sync acceptance.

The library defaults to local storage. Explicit `selectStorage(.iCloud)` prepares its replica
without cloud I/O. Normal add/edit/delete and saved preferences then capture offline changes.
`synchronizationReplica()` supplies the exchange with the current library at each boundary,
so foreground edits during fetch/publication are retained. Fetched data is materialized into
the saved list before publication; publication failure cannot turn an unseen imported row into
a deletion on retry. Switching back to local storage invalidates the previous replica adapter.

One local checkpoint contains the library and document together; the previous list is a
compatibility mirror. Restart can recover the checkpoint if that mirror write was interrupted.
Stale extra instances and malformed checkpoints are reported and cannot replace newer data.
An invalid checkpoint is retained while local edits remain available in the existing list.
These are tested logical consistency and simulated interrupted-write boundaries; signed-app
termination, real disk durability, settings UI, and live-account acceptance remain required.

Cloud endpoint edits and new/deleted cloud IDs invalidate local password/SSH associations.
They do not read, delete, synchronize or export the actual secret. Explicit local replacement
can restore access. Runtime status, connection history and these invalidations stay local.
`build/sync-library-qa/targeted-library-verified.json` records 64 passing cases: 14 new saved-library
integration cases, 27 prior sync cases and 23 existing DeviceStore cases.

Each replica has a durable UUID and a Lamport clock. Connection identity (host, port,
authentication/account, and SSH configuration) is an atomic register. Other saved preferences
are independent registers so concurrent name and cursor/clipboard edits both survive.
For concurrent edits to the same register, the counter and replica UUID determine the same winner
on every replica. Revisions with different values at the identical counter/replica are rejected.
Machine clock time is not used for conflict resolution.

Deletion leaves a permanent tombstone. It wins against delayed updates, including offline updates
with larger counters. Adding that computer again must create a new device UUID. Tombstones cannot
be discarded without a separate acknowledgement/retirement protocol for all offline replicas.
Screen preferences carry their connection identity so an old server's monitor ID cannot apply to
a changed endpoint. Reachability and last connection time remain local and are not exported.

The durable store owns one local replica. It checks for another instance's newer stored document
and rejects a stale write. The eventual app coordinator must be the sole writer for its defaults
domain; this in-process guard is not an interprocess file lock. A local corrupt ledger is preserved
and reported rather than reset to an empty list. Import, quota failures, and conflicting revisions
leave the current document intact. Credentials/private keys and host-key trust are separate from
this schema and still require their own Keychain sync implementation and acceptance.

Remaining integration gates:

- Verify the conditional per-replica transport and total account/container quota with real CloudKit
  in the signed apps. Pure record-codec and controlled-transport tests do not accept cloud I/O.
- Verify the account-change observer and preserved account binding with a real signed-in account;
  switching accounts must not mix private documents.
- Verify the new app settings/controller and saved-library notifications in the VM; remote imports
  and runtime connection history must not produce an automatic synchronization feedback loop.
- Complete native local/iCloud settings acceptance in both languages, including unavailable state,
  retry, switching back to local and restart; a local status never proves remote execution.
- Configure and verify shared iOS/macOS capabilities/profiles, then test actual signed apps with
  the same account on both devices, offline editing/deleting, restart, and account switching.
- Implement and verify encrypted Keychain password/SSH-key sync separately. Do not put secrets
  in the metadata document, diagnostics, or test fixtures.

Relevant primary references:

- [Apple: Storing Preferences in iCloud](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/UserDefaults/StoringPreferenceDatainiCloud/StoringPreferenceDatainiCloud.html)
- [Screens: Data and Credentials Synchronization](https://help.edovia.com/en/screens-5/features/sync)

The app coordinator pauses automatic exchange when the scene leaves the foreground. Local
metadata edits are debounced; remote imports and connection-history writes do not schedule
feedback uploads. Account-change notifications cancel the old exchange, and existing account
binding is preserved. Typed localized failures cannot display raw transport account details.
The foreground controller has 11 passing headless tests; its current source and UI gate are
tracked separately under `build/sync-controller-qa`. The earlier 189-source library snapshot
and 356-pass full-unit receipt remain historical stage evidence after these new UI changes.

Preference schema development adds document version 2 for app language and saved-computer
toolbar overrides. Layout/order/visibility is one atomic group; size, position, hardware mappings,
repeat controls and Pencil actions merge independently. Absent factory toolbar defaults do not
create overrides. A common baseline prevents first customizations from overwriting other
unchanged controls. Old metadata without these fields remains byte-stable version 1.
Clearing an override is a revisioned value; deleting a computer removes its toolbar and retains
the deletion tombstone. Malformed/oversized layouts, invalid controls or conflicting revisions
reject the whole import. The offline DeviceSyncStore and controlled transport carry version 2.

This schema work is recorded separately in `build/sync-preferences-qa`. It is not yet connected
to the actual AppLanguageSettings/KeyboardToolbarStore or the DeviceStore checkpoint mirror;
that bridge, restart consistency and live-session refresh are still required. No credentials,
API tokens, clipboard/input text or host-key trust are added to the document. Old version-1-only
clients must reject version 2 rather than silently drop its preferences. The earlier 192-source
controller and native UI receipts are historical after this new schema change.


## Native preference-store bridge candidate

This candidate connects the version-2 preference document to the actual
AppLanguageSettings and per-computer KeyboardToolbarStore. Native saved edits
are captured while offline and at every exchange boundary. Factory toolbar
loads and unrelated/temporary keys do not create cloud overrides. A shared
preference lock prevents an import from overwriting an in-flight native write.

The authoritative DeviceStore checkpoint now pairs the visible computer list,
convergent document, native preference snapshot and its prior mirror values.
Imported preferences are applied before publication. Restart recovery completes
interrupted mirror writes per key; values that differ from both the previous
and imported value remain local edits. Choosing Local clears the recovery
snapshot so subsequent local preferences cannot be replayed from an old cloud
import. Corrupt native preferences preserve local computer edits and prevent
export until corrected; corrupt/mismatched checkpoints are retained.

Typed notifications refresh retained language and session objects without
saving an imported toolbar back into the ledger, regenerating factory item IDs
on language-only changes, or reconnecting a session. Temporary sessions do not
receive these per-computer preference updates. The normal existing modifier
release behavior still applies when toolbar layout changes.

Evidence belongs to build/sync-preference-bridge-qa, independently of the
previous source-193 schema and source-192 UI receipts. Headless tests and an
iOS compile do not accept visible UI, real process-kill durability, real
CloudKit accounts, encrypted Keychain credential sync, or physical iPhone input.
The app still has no configured CloudKit transport/container. No phone build,
public version, provisioning setting or website is changed in this phase.
