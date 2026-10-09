# Native file-transfer implementation evidence

Date: 2026-10-08. Native drag/drop file transfer remains incomplete.

## Product requirement

Screens exposes file drag/drop to and from the remote desktop, with progress.
Its iPhone download flow detects a remote file drag and presents a drop target;
this is not an SFTP browser. Official reference:
https://help.edovia.com/en/screens-5/features/file-transfers
https://help.edovia.com/en/screens-5/features/file-transfers-iphone

## Read-only target evidence

On the authorized Mac mini, static system-binary inspection found:

- screensharingd contains `HandleFileCopyMessage`, `ServerProcessFileCopyCmd`,
  `RFBFileCopy_StartFileReceiveMessage` and `com.apple.screensharing.filecopy`.
- Its bundled `SSFileCopySender` and `SSFileCopyReceiver` executables both exist.
- Receiver static strings include `kRFBFileCopy_StartFileReceive`,
  `kRFBFileCopy_ItemInfo`, and a session-ID/version format string.
- Sender static strings refer to `RFBFileCopy_NewItem` structure sizing.
- No matching named symbols were obtained from the symbol-table searches.

Evidence files:
`/tmp/aetherscreens-native-file-symbols-20261008.log`
`/tmp/aetherscreens-native-file-helper-symbols-20261008.log`

Only bundled executable strings/symbols were read. No helper was launched,
no user files/clipboard were read, no system settings changed, and no guessed
file-transfer packet was sent. These names establish implementation entry
points; they do not establish packet byte values, layouts or live interoperability.

## Remaining transport evidence

Before enabling native transfer, establish authenticated message framing,
message kinds/lengths, session-ID and version byte order, item metadata encoding,
drag offer/request handshake, acknowledgement/EOF/finalization, failure/cancel
semantics, and encryption/record-layer integration. Validate with owned fixture
files and byte-for-byte upload/download checks on a real Mac, including folders,
empty files, overwrite decisions and cancellation. Do not infer message numbers
from string names or port claims from unrelated clients.

The current public experimental high-performance implementation specification
was also reviewed; a verified file-copy grammar was not obtained from it:
https://github.com/renegadelink/iShareScreen/blob/main/docs/apple_vnc_rfc.md

## Current reusable components

`FileTransferJob` tracks acknowledged bytes, conflict decisions and per-attempt
callback identity. `FileTransferRelativePath` provides lexical path validation.
Neither is a native wire implementation or a filesystem writer. The future writer
must prevent symlink traversal at creation time. Native transport and drag/drop UI
are not implemented; this research does not close file-transfer parity.

## Static client-to-server envelope evidence

Read-only `xcrun llvm-objdump --macho --arch=arm64e --disassemble
--symbolize-operands` inspection of the same authorized target's system binaries
yielded the following concrete offsets. Addresses refer only to this binary
build; they are evidence locations, not stable API entry points.

The server dispatcher at `0x1000366e8` reads a one-byte RFB type and selects a
signed 32-bit jump-table entry from `0x1000404e8`. Entry 34 at `0x100040570`
contains `0x8d0`; added to the dispatch base `0x100036714`, it reaches
`0x100036fe4`, whose strings identify `HandleFileCopyMessage`. Thus this observed
client-to-server type is `0x22`. No reverse-direction type is established here.

| Offset | Width | Observed client-to-server envelope field |
| --- | --- | --- |
| 0 | 1 | RFB message type `0x22` |
| 1 | 1 | Uninterpreted prefix byte; no semantic assumption |
| 2 | 4 | Big-endian payload length, excludes six-byte prefix |
| 6 | 2 | Big-endian version |
| 8 | 2 | Big-endian command |
| 10 | 4 | Big-endian session ID |
| 14 | variable | Command body |

`HandleFileCopyMessage` reads the six-byte prefix at `0x100039dd8`, reverses the
length at `0x100039dec`, then consumes exactly `length + 6` at `0x10003a3a8`.
`ServerProcessFileCopyCmd` at `0x100061554` reverses version/command/session
fields before dispatch. Its branches identify commands 1=start send,
2=start receive, 3=pause, 4=continue, 5=stop. This does not establish which commands
are supported in a negotiated client session, or their complete bodies.

The receiver helper's `GetNextMessage` at `0x1000050fc` reads the same-sized
prefix from stdin, but does not reverse its length. The parent passes it native
order fields. Do not send that helper's local process framing directly to RFB.
Its dispatcher uses command 100 for item info and 102 for file data, with explicit
file-fork state checks before writing. Item info logs distinguish logical size,
physical size, file count, fork count, folder count and allocation size; treating
all data as a flat stream would lose native metadata and resource forks.

Evidence:
`/tmp/aetherscreens-file-server-disassembly-20261008.log`
`/tmp/aetherscreens-file-receiver-disassembly-20261008.log`
`/tmp/aetherscreens-file-sender-disassembly-20261008.log`.
Only static bundled executable contents were inspected. No helper execution,
file-transfer packet or user-file access occurred.

An internal offline `AppleFileCopyMessage` decoder now represents these
fields and bounds the payload at 1 MiB. Four synthetic-fixture tests cover every
fragment boundary, coalesced trailing bytes, nonzero Data indices, invalid/large
lengths and opaque versions/commands. All four passed:
`/tmp/aetherscreens-file-copy-envelope-tests-20261008.log`.
The literal fixtures are derived from static offsets, not captured successful
transfers. The decoder is not integrated into RFBClient and does not advertise
file-copy capability. Bidirectional negotiation, metadata, compression/forks,
acknowledgement and real upload/download verification remain required.

## Server-to-client status bodies

The same static server binary now establishes reverse status framing. In
`FileReceiveToolListenerThread`, instructions `0x10006495c`–`0x10006499c`
construct and enqueue an RFB type `0x22` message with version 1, command 300,
payload length 16, session ID and one eight-byte big-endian IEEE-754 double.
The receiver helper at `0x1000070c4`–`0x1000070d4` computes a ratio and stores
that double before its separate logging multiplication by 100. Its pipe write
at `0x100007194`–`0x1000071a0` sends command 2 followed by the original ratio.
The wire value is therefore a fraction, not a displayed percentage.

Instructions `0x100064c20`–`0x100064d20` construct the separate end-status
message: type `0x22`, version 1, command 200, payload length `13 + nameLength`,
session ID, signed big-endian 16-bit error code, big-endian 16-bit name length,
name bytes, then a NUL terminator. The producer rejects names longer than 1023
bytes. The name encoding is not independently established, so the decoder
preserves raw bytes instead of declaring UTF-8 support.

Both messages enter the queue routine at `0x10001d4d0`. That routine routes
plaintext payloads starting at its queue-object offset 14 through the existing
encrypted-record path when enabled; its allocation/queue bookkeeping is not
part of RFB framing. This observation does not verify our client's live
integration with encryption or capabilities.

`AppleFileCopyServerStatus` decodes these two bodies only for version 1 and the
expected session ID. It rejects malformed lengths, missing NUL terminators and
non-finite/out-of-range progress. Progress 1 remains a progress event; only an
explicit end status carries a completion result. Unknown versions/commands and
unrelated sessions are ignored. No transfer/job/UI integration is enabled.

Tests use literal synthetic status packets and cover signed errors, raw name
bytes, empty names, progress 0.5/1, session isolation and malformed bodies.
They are not captured successful transfers. Native metadata negotiation,
drag initiation, data/fork/compression grammar and real byte-integrity checks
remain open.

## File-data body validation

Receiver dispatch at 0x1000022d8 identifies command102. At
0x100002350 it reverses the UInt32 byte count at full-message offset14;
0x10000236c checks the active fork's remaining bytes, and 0x10000238c
passes data beginning at offset18 to FSWriteFork. Sender instructions
0x10000435c-0x100004364 set payload size to raw count plus12 (eight common
header bytes and four count bytes). Thus the raw body is UInt32 length
followed by exactly that many bytes.

Receiver dispatch at 0x100002734 selects command103. The body begins with
a big-endian UInt16 algorithm at offset14, expanded UInt32 length at16,
compressed UInt32 length at20, then compressed bytes at24. Algorithm1
is checked at0x100002da4-0x100002db0 before the zlib path. The stateful
inflater behavior/reset/finalization still requires complete verification.

AppleFileCopyDataBlock validates these offline bodies against declared lengths,
an expanded-size budget and the caller's active-fork remainder. It preserves
compressed bytes without claiming inflation. It represents versions1/2 as
experimental profiles; real negotiation/support is not established by this
parser. Four new tests plus existing envelope/status tests passed12/12, with
zero failures: /tmp/aetherscreens-file-copy-data-tests-20261008.log.
Synthetic compressed bytes test framing only, not valid zlib or wire acceptance.
No filesystem writer, live file-copy messages or UI integration is enabled.

## Persistent zlib expansion experiment

Static sender instructions0x10000445c-0x100004464 call deflate with
flush2 (Z_SYNC_FLUSH). Receiver0x100002dc4 tests its initialized flag,
initializes only on first compressed data at0x100002e6c, then feeds the
existing stream at0x100002e90 with the same flush value. This establishes
persistent compressed-block state; it does not establish every item/fork
or reconnect reset boundary. No inflateReset/inflateEnd named call was found
in these disassembly searches; absence is not a complete lifetime proof.

AppleFileCopyInflater now provides an isolated experimental context with a
bounded exact output, independent of framebuffer dictionaries. It accepts raw
blocks without modifying zlib state, requires complete Z_SYNC_FLUSH payloads,
rejects unexpected expansion and poisons the context after errors. It does not
automatically reset mid-stream or return partial bytes on failure. Integration
must instantiate/dispose it at verified negotiation boundaries. The complete
item/fork lifecycle and actual native transfer remain unverified.

All16 envelope/status/data/inflater tests passed, zero failures:
/tmp/aetherscreens-file-copy-inflater-tests-20261008.log. Fixtures contain
actual synthetic compressed streams, not packets accepted from a Mac server.

## Item-name and lifecycle follow-up

### Receiver hierarchy follow-up (2026-10-09)

Retained receiver disassembly confirms an additional destination-name rule:
0x100003370 tests decoded level; nonzero levels copy the packet name through
0x10000340c–0x100003428. Level zero tests a separate mode byte at context
offset 0x191 (0x100003438–0x10000343c); when enabled it duplicates a supplied
name pointer at 0x100003440–0x100003448 instead. The mode's negotiation meaning
is still unverified, so no unconditional top-level renaming rule is implemented.

The native directory branch stores the created 80-byte FSRef at index
`level + 1`: 0x100003adc–0x100003b08 calculates `level * 0x50 + 0x50`
and copies the reference into that destination. This supports a depth-indexed
directory-reference stack rather than flattened names. Parent selection,
maximum depth, ascent rules and legacy colon/slash conversion still require
verification before implementing a directory writer. Ordinary staging retains
the original item metadata and has no automatic hierarchy finalization.
Evidence: /tmp/aetherscreens-file-receiver-disassembly-20261008.log.

Parent selection is now independently observed: the regular-file branch at
0x1000039f0–0x100003a14 and directory branch at 0x100003a78–0x100003aa0
pass the reference at `level * 80` into the creation helper. Together with
the directory write to `(level + 1) * 80`, this establishes the parent stack.
AppleFileCopyHierarchy implements only that structural plan with bounded
depth/item count and rejection of missing parents. Ascent discards obsolete
deeper branch references. Two tests cover nested/sibling/multiple-root entries,
missing parents, depth/count limits and unchanged state after rejection:
/tmp/aetherscreens-file-hierarchy-tests-20261009.log. It is not yet connected
to the receive writer or UI, and does not implement native filename conversion.

Filename handling follow-up: 0x10000390c–0x100003950 creates a CFString using
UTF-8 (0x08000100), checks its UTF-16 length against 255, and copies its UTF-16
characters for the creation helper. The final helper dispatches directly to
FSCreateFileUnicode (0x100006bd4–0x100006bf0) or FSCreateDirectoryUnicode
(0x100006bf8–0x100006c18). No colon-to-slash byte rewrite occurs in this
observed name-to-creation path. This does not prove that raw POSIX names can
be used unchanged: the legacy filesystem APIs may supply the representation
conversion. A POSIX writer must verify that conversion separately instead of
blindly applying a reverse replacement. The native 255 UTF-16-unit bound is
also distinct from the envelope's 1023-byte name bound.

Real filesystem probe on the authorized Mac mini (2026-10-09): an isolated
temporary directory was passed through FSPathMakeRef, FSCreateFileUnicode
and FSRefMakePath. `literal:colon.txt` returned -37; `literal/slash.txt`
succeeded and its POSIX basename was `literal:slash.txt`; `percent%2Fname.txt`
remained unchanged. Created files, directory and compiled probe were cleaned
after terminal exit zero. This proves the legacy API representation mapping
on that OS, not the end-to-end packet-name rule. The earlier sender slash-to-
colon observation cannot yet be reconciled with the directly observed receiver
path; no blanket wire-name replacement has been enabled. Actual packet capture
or additional parent/helper conversion evidence is required.

The conflict above was resolved by checking the sender branch predecessor:
0x100003658–0x100003668 gates slash-to-colon rewriting on item type 3;
ordinary files/directories skip it through 0x1000037b8–0x1000037c4. Thus the
real FSUnicode probe establishes ordinary-item conversion: wire slash becomes
a literal POSIX colon; wire colon is rejected. AppleFileCopyOrdinaryName now
implements that conversion as a single FileTransferRelativePath component,
rejects NUL/dot traversal/native-invalid colon/over-255 UTF-16 names and does
not handle symbolic links. Two Unicode/percent/boundary/rejection tests passed:
/tmp/aetherscreens-file-name-tests-20261009.log. Destination filesystem limits
and final metadata/hierarchy/session integration remain separate requirements.

Staging integration (2026-10-09): ordinary item names are now validated and
converted before any staging directory is created. Staging retains the derived
destinationName and offers a macOS default-name commit overload while retaining
explicit user rename support. A filesystem regression verifies invalid names
leave no directory and the default atomic commit preserves Chinese, literal
colon and percent bytes. All 66 file-copy/transfer tests passed:
/tmp/aetherscreens-file-name-integration-tests-20261009.log. Native session
negotiation, directory writer and public UI remain unimplemented.

Integrated verification (2026-10-09): eight synthetic TCP file-copy tests
passed after name validation/default destination integration:
/tmp/aetherscreens-file-name-wire-regression-20261009.log. Generic unsigned
iOS compilation of the hierarchy, totals and name/staging changes passed:
/tmp/aetherscreens-file-manifest-ios-build-20261009.log. The first UInt32 in
ItemInfo remains rawHeaderValue, not an assumed capability flag; two decoder
tests passed after that naming correction:
/tmp/aetherscreens-file-item-info-final-tests-20261009.log.

Start-message encoder (2026-10-09): AppleFileCopyStart now constructs command
1/2 messages from explicit direction/session/options/raw path. It preserves
reserved/trailing bytes and rejects invalid reserved length, NUL-containing
paths, UInt16 path overflow and payload overflow before constructing the body.
Four start-codec tests passed, including independent literal expected bytes:
/tmp/aetherscreens-file-start-encoding-tests-20261009.log. No start message is
sent to a live server and no destination/capability semantics are inferred;
the negotiated owner still needs verified session initiation and policy.

Synthetic start-wire integration (2026-10-09): a loopback native-banner fixture
receives command 2 encoded by AppleFileCopyStart through RFBClient's internal
send path. It compares the complete independently specified 28-byte packet,
including envelope length, session and raw path. Nine native file-copy TCP
tests passed: /tmp/aetherscreens-file-start-wire-tests-20261009.log.
This proves local transport framing, not live-server start acceptance or
capability negotiation. No live start command was sent.

Ordinary manifest planning (2026-10-09): AppleFileCopyManifest combines the
verified parent stack and ordinary-name conversion into complete relative
paths while retaining each catalog/extension block. Depth, item count and
retained metadata/path byte totals are bounded. Failed name, hierarchy or
budget validation does not advance structural state. Two regressions cover
nested Unicode/literal-colon/percent paths, sibling ascent, orphan rejection
and budget failures: /tmp/aetherscreens-file-manifest-tests-20261009.log.
This planner creates no directories/files and is not yet installed in the
receive session; directory disk operations and metadata finalization remain open.

Session manifest integration (2026-10-09): the receive session now plans each
ordinary item before staging and clears manifest/hierarchy state with staging
on cancellation/failure. A missing-parent regression proves an orphan after
an already prepared file fails the session and removes both previous staging
and retained entries. All 70 file-copy/transfer tests passed:
/tmp/aetherscreens-file-manifest-session-tests-20261009.log. This supersedes
the planner-disconnected statement above. Directories/symlinks still require
their own disk writer; no complete native-transfer capability is advertised.

Directory staging (2026-10-09): the existing staging owner now supports
directory items with zero data/resource fork sizes. It creates a private
0700 payload directory, opens it with O_DIRECTORY/O_NOFOLLOW, applies known
extended attributes through that descriptor and commits with existing
RENAME_EXCL semantics. There is no resource sidecar for directory entries.
An actual-filesystem regression confirms ordinary-name default commit,
existing-folder/content preservation and cancellation after commit. All 71
file-copy/transfer tests passed:
/tmp/aetherscreens-file-directory-staging-tests-20261009.log.
This supersedes the absence of directory staging above. Full-tree finalization,
directory catalog metadata, symlinks and live negotiation remain incomplete.

Directory receive integration (2026-10-09): a command101 directory followed
by a depth-one file, command102 bytes and successful command104 preserves
manifest paths/parent index and exact child bytes, hands off a real directory
plus file, and cleans all private staging after cancellation. Twenty-two
receive-session/worker/staging tests passed:
/tmp/aetherscreens-directory-session-integration-tests-20261009.log.
The prepared child remains separate from the directory payload until tree
finalization; this does not establish a saved complete tree or live acceptance.

macOS prepared-tree assembly (2026-10-09): takePreparedTrees moves nested
prepared entries into their still-owned parent payloads in reverse order,
then hands off only roots. The receive worker uses this path on macOS; iOS
still hands off separate staging pending its export implementation. Existing
exclusive rename rules reject duplicate children. Assembly failure cleans
the entire owned attempt and now reports onFailure even after sender-end
closed admission. Actual-filesystem tests verify a two-level tree's exact
child bytes before/after root commit and worker conflict cleanup without
handoff. All 74 file-copy/transfer tests passed:
/tmp/aetherscreens-file-tree-assembly-tests-20261009.log.
This establishes ordinary tree assembly in synthetic reception, not final
catalog metadata, live capability negotiation or public transfer completion.

Ownership state (2026-10-09): taking prepared files/trees now transitions the
receiver from senderFinished to handedOff. Repeated takes fail unavailable
without marking the successfully handed-off session failed or touching its
new owner's files. Cancelling the old receiver clears retained manifest state
only. File/tree regressions cover repeated takes and ownership preservation;
all 74 file-copy/transfer tests passed:
/tmp/aetherscreens-file-ownership-handoff-tests-20261009.log.

Directory extension verification (2026-10-09): the existing directory commit
test now supplies a version-one ext1 binary attribute, then reads it from the
committed directory with getxattr and compares the exact NUL/0xff-containing
value. The real-filesystem test passed:
/tmp/aetherscreens-directory-xattr-tests-20261009.log. This establishes raw
directory xattr preservation through commit; it does not establish Finder
catalog flags, timestamps, permissions or actual-server metadata compatibility.

Catalog layout follow-up (2026-10-09): a compiled SDK offsetof probe reports
FSCatalogInfo date offsets 16/24/32/40/48, permissions 56, Finder info 76/92,
and textEncodingHint 144; within FSPermissionInfo userAccess is 9 and mode 10.
Matched against retained sender code, command101 body layout is now confirmed:
Finder blocks at 2/18 (16 bytes each), create/content-mod/attribute-mod/access/
backup UTCDateTime records at 50/58/66/74/82 (eight bytes each), node flags 90,
depth 92, permission mode 94 (UInt16), encoding hint 96 (UInt32); body byte 1
copies userAccess. The first body byte retains a separate item-option field.
Sender helper 0x100004ecc–0x100004ef4 swaps each UTCDateTime record as
UInt16/UInt32/UInt16, rather than one UInt64. Finder fields receive mixed
16/32-bit conversion, so copying the wire block directly to com.apple.FinderInfo
is not yet justified. Dates and permissions must be restored after tree
assembly to avoid subsequent child moves changing directory metadata.
Probe binary was removed; no catalog metadata is applied by this checkpoint.

Typed catalog decoder (2026-10-09): AppleFileCopyCatalogMetadata validates
the exact 104-byte header and parses the known node/mode/encoding/access
fields and all five UTCDateTime records. Each timestamp preserves high/low
seconds and its 16-bit fraction; no epoch conversion or filesystem write is
assumed. Finder bytes remain explicitly in wire representation. Two literal
mixed-width-endian and header-boundary regressions passed:
/tmp/aetherscreens-catalog-metadata-tests-20261009.log.

Timestamp conversion (2026-10-09): a compiled native
UCConvertUTCDateTimeToCFAbsoluteTime probe confirms zero maps to Unix
-2082844800, raw seconds 2082844800 maps to Unix zero, and fraction 32768
adds 0.5 seconds. Timestamp.date implements that epoch offset plus fraction
/65536 and includes high seconds. Three catalog tests passed:
/tmp/aetherscreens-catalog-date-conversion-tests-20261009.log.
The temporary probe binary was removed. Zero has not been interpreted as an
unset/sentinel timestamp; metadata option semantics and restoration remain open.

Real Finder byte-order probe (2026-10-09, authorized Mac mini): a uniquely
owned ordinary file received a synthetic 32-byte com.apple.FinderInfo value.
FSGetCatalogInfo(FinderInfo|FinderXInfo) returned:
attribute: 4142434445464748123456780000000011220000000000000000334455667788
catalog:   4443424148474645341278560000000022110000000000000000443388776655
The sender's observed rev32/rev16 conversions restore the original attribute
bytes exactly. For ordinary files this resolves the earlier uncertainty:
the resulting wire Finder block already has the xattr byte representation.
Directory Finder records still need a separate probe because their field
layouts differ. The file, temporary directory and compiled probe were cleaned
with verified terminal exit zero. No Finder metadata is applied yet; native
metadata-option semantics remain to be checked.

Directory Finder probe (2026-10-09, authorized Mac mini) returned the same
attribute fixture but catalog bytes starting 4241444346454847 instead of the
ordinary file's 4443424148474645. The folder rectangle is swapped as four
UInt16 fields by FSGetCatalogInfo, while the sender always rev32-swaps those
first eight bytes. Consequently directory wire data needs each first UInt32's
two UInt16 words exchanged to recover xattr representation. The remaining
24 bytes match the established conversion. finderInfoAttribute now handles
this distinction using the directory node flag. Four catalog regressions,
including both real-probe fixtures, passed:
/tmp/aetherscreens-finder-attribute-conversion-tests-20261009.log.
Temporary directory/binary cleanup passed. No Finder attribute is written by
this helper until metadata-option semantics and finalization are integrated.

Native restoration masks (2026-10-09): SetMetaData at
0x100006458–0x100006464 passes mask 0x1be3 to FSSetCatalogInfo. SDK constants
show this includes encoding/node flags, creation/content/attribute/backup
dates and both Finder blocks, but excludes permissions (0x400) and access
date (0x100). End-session reapplies dates/Finder blocks with mask 0xbe0 at
0x10000431c–0x100004328, and a separate pass applies node flags with mask 2
at 0x1000043d8–0x1000043e4. SetUNIXPermissions (entry 0x100006664)
loads the decoded UInt16 mode from receiver context +0xa6e6, clears
0x0c00 (setuid/setgid, octal 06000), and calls chmod at 0x100006754.
The fchmod call at 0x100008d08 belongs to LFOpen and uses constant 0666;
it is not restoration of the received catalog mode. The catalog helper now
exposes ordinary/sticky permission bits with the native privilege-bit policy.
It does not apply permissions yet: restrictive directory permissions must
be deferred until children and catalog metadata are finalized.
This narrows finalization order and prevents treating all parsed metadata as
one unconditional restoration operation. Extended Finder attribute precedence
also requires tracing CheckForExtendedFileAttribute before enabling writes.

Permission policy regression (2026-10-09): independent wire modes cover regular
executables, setgid files, sticky directories, read-only files and zero access.
The decoder retains the original mode; restoredPermissions strips file type
and privilege bits without granting new access. All 88 selected file-copy,
transfer-job/path and transport tests passed in
/tmp/aetherscreens-transfer-current-tests-20261009.log. This remains an internal
receive implementation; real negotiated transfer and destination metadata
finalization are not yet accepted.

### Outgoing item/attribute framing (2026-10-09)

Added command-101 encoding from an exact 104-byte catalog header, explicit
level, UTF-8 wire name, optional opaque link target and extension bytes.
Derived lengths/level replace stale header fields; all other catalog bytes
are retained. Names use the receiver's 1023-byte bound, link lengths use
UInt16, NULs/empty links are rejected, and the common 1 MiB payload limit
is checked before body assembly. This does not derive wire names from local
paths or authorize sending symlinks.

Added ext1 version-one table encoding with binary names/values and a UInt16
total-envelope bound checked before allocation. Tests use independent literal
tables, exact 65535-byte envelopes and one-byte overflow, including empty
tables/values. A synthetic native-banner TCP receiver captured command 101
with the encoded table byte-for-byte against an independent 150-byte fixture.
All 93 selected transfer/codec/transport tests passed:
/tmp/aetherscreens-outgoing-wire-tests-20261009.log.
This proves framing through RFBClient, not native server acceptance, catalog
collection, session negotiation, upload acknowledgements or user-facing upload.

### Bounded outgoing fork reader (2026-10-09)

AppleFileCopyForkReader now opens ordinary local files through O_NOFOLLOW,
validates regular-file type and exact logical length with fstat, then emits
command-102 blocks (64 KiB default, common-payload bound enforced). It reads
data before resource bytes, emits no empty data block, retains opened file
identity across path replacement, and fails/closes the attempt on truncation.
Cancellation only closes source handles. The caller must retain each packet
until queue admission and supply session negotiation/item/end messages.
Content mutation through an already-open source is not a snapshot guarantee.

Five real-filesystem regressions cover bounded binary blocks/fork order,
empty data forks, path replacement, symlink/directory/length rejection,
truncation/cancellation and sender-reader → receiver → final commit. The last
checks both ordinary and named resource-fork bytes after commit and preserves
both source files. All 98 selected codec/transfer/transport tests passed:
/tmp/aetherscreens-upload-roundtrip-tests-20261009.log.
No live native server or public upload UI is involved in this test.

### Outgoing session sequencing and queue retry (2026-10-09)

AppleFileCopySendSession now sequences a bounded manifest of ordinary files
and directories: command 101, data/resource command 102 blocks, then one
command 104. Sources are opened/length-checked before their item header is
admitted. A rejected send retains the exact pending packet and does not read
the next block. Each pump admits at most one packet, and reentrant pumping is
rejected; the owner still supplies scheduling, native negotiation and pacing.

queuedBytes is explicitly queue admission, not acknowledged saved bytes.
The sender enters awaitingResult after command 104 admission and completes
only on a matching command-200 zero result after all declared bytes were
queued. Premature success, malformed result and native errors fail the
attempt. Progress is the native fraction, never converted to saved-byte ACKs.
Cancellation invalidates callbacks and closes source handles.

Five new regressions cover identical retry of every packet, result-only
completion, wrong-session/late result rejection, premature success/native
failure, reentrant cancellation, changed source/budget failure, and directory
plus child sequencing through receiver assembly/final filesystem commit.
All 103 selected transfer/transport tests passed:
/tmp/aetherscreens-send-tree-tests-20261009.log.
This session is internal and is not wired to a public upload action; native
session negotiation, source catalog collection and live server result remain
required before enabling that action.

### Read-only native source catalog collection (2026-10-09)

Added the macOS-only AetherScreensCatalog C bridge because Swift does not
import the packed Carbon file catalog structures. It calls the same
FSGetCatalogInfo/gettable mask as the retained native sender, serializing
Finder fields with the observed mixed-width swaps, UTCDateTime components,
logical fork lengths, node flags, permissions/access and encoding hint.
This is a local package target using the system CoreServices framework,
not a third-party production dependency; it is excluded from the iOS core
dependency graph. Item options remain an explicit owner parameter, not an
assumed negotiated value.

AppleFileCopySourceCollector verifies ordinary file/directory type and source
identity, collects xattrs through a read-only descriptor within ext1 limits,
excludes ResourceFork from the attribute table, and supplies the named fork
URL to the bounded reader. POSIX colon names convert to catalog/wire slash
names. It neither follows a leaf symlink nor creates/modifies source files.
Mutable files remain mutable; collection is not a content snapshot.

Four real-filesystem tests cover Unicode/colon names, file/folder Finder bytes,
permissions/timestamps, binary attributes, both actual source forks,
symlink/oversized-attribute rejection, and collected source → sender → receiver
→ committed destination. The latter checks the ordinary/resource bytes,
attribute and destination name while the sender still awaits remote result.
All 107 selected transfer/transport tests passed:
/tmp/aetherscreens-source-catalog-roundtrip-20261009.log.
Generic unsigned iOS build passed:
/tmp/aetherscreens-source-catalog-ios-build-20261009.log.
Live negotiation, destination catalog restoration and public transfer UI remain
unaccepted; the synthetic round trip is not native-server interoperability.

### Catalog restoration ordering (2026-10-09)

Native CheckForExtendedFileAttribute calls ExtendedAttributes_Write at
0x10000655c (helper 0x100001408, setxattr at 0x100001980), returns to
0x100006388, then reconstructs the received Finder blocks and calls
FSSetCatalogInfo at 0x100006464. Thus the received catalog Finder fields are
authoritative after ext1 writes; an ext1 Finder value does not override them.

Added descriptor-based ae_restore_catalog_metadata and explicit
AppleFileCopyStagingFile.restoreCatalogMetadata for owned, prepared payloads.
It restores creation/content/attribute/backup dates, Finder blocks and encoding
using native mask 0x1be1 (node/lock flags deferred). Access date and permissions
are not applied. The descriptor's actual path/inode/type are checked, and the
Swift entry opens without following a leaf symlink. Invocation is explicit;
the receiver does not silently finalize incomplete trees.

Three additional real-filesystem regressions verify file creation/modification
dates, catalog priority over a conflicting ext1 Finder value, folder mtime
restoration after child assembly and final move, post-commit rejection, and
replaced symlink payload rejection without source-target metadata changes.
All 110 selected transfer/transport tests passed:
/tmp/aetherscreens-catalog-ownership-regression-20261009.log.
Generic unsigned iOS build passed:
/tmp/aetherscreens-catalog-finalization-ios-build-20261009.log.
This restores the explicitly selected prepared item's catalog. Recursive tree
metadata ownership/order, restrictive permissions and locked flags still need
integration before claiming complete receive finalization or live parity.

### Recursive catalog and restrictive permissions (2026-10-09)

Prepared-child assembly now transfers relative catalog records and original
device/inode identities to the new tree owner. restoreCatalogMetadata walks
the complete assembled tree from children to parents using descriptor-relative
O_NOFOLLOW traversal. Every final descriptor must still match the originally
created staging inode; replaced symlink/hardlink payloads cannot redirect
metadata writes. A failed repeat restoration clears the catalog-ready state.

Explicit restorePermissions follows catalog restoration, strips setuid/setgid
and type bits, and applies descendant modes before their parents. Directory
descriptors are retained until cancellation or final commit. Cancellation
restores private directory traversal through those descriptors before cleanup.
No committed destination's modes are relaxed by sidecar cleanup.

Actual macOS test evidence exposed renameatx_np EACCES for a zero-access root
directory. The root therefore retains owner 0700 during private staging and
receives its exact requested mode through its retained descriptor immediately
after successful rename. Conflict leaves staging available for another-name
retry. If that post-move chmod fails, committedMetadataFailure carries the
destination URL and errno; the moved payload is preserved, not reported as a
successful finalized download or deleted by cancellation.

Three added regressions cover multi-level dates/Finder ownership after receiver
cancellation, intermediate symlink rejection, zero-access descendant cleanup,
native privilege stripping, conflict retry and exact zero-access destination
modes surviving repeated cancellation. The hardlink test snapshots its target
after link creation, because link creation itself changes attribute time.
All 113 selected transfer/transport tests passed:
/tmp/aetherscreens-recursive-permission-final-tests-20261009.log.
Generic unsigned iOS build passed:
/tmp/aetherscreens-recursive-permission-ios-build-20261009.log.
Locked flags, negotiated options, server interoperability and UI integration
remain pending; these explicit finalizers do not advertise completed parity.

Mac mini acceptance checkpoint (2026-10-09): current SSH endpoint
100.64.0.3 reported macOS 27.0.1. The refreshed local XCTest bundle ran seven
file-transfer suites there, including the native C catalog bridge, recursive
restoration, zero-access directory cancellation/conflict retry and final modes.
All 44 selected real-filesystem tests passed, no skips/failures:
/tmp/aetherscreens-macmini-catalog-permission-tests-20261009.log.
The exact uniquely created remote QA bundle/archive directory was validated
and removed after the test process exited zero. No live RFB transfer, desktop
interaction or system clipboard mutation was exercised by this gate.

### Native item kind correction (2026-10-09)

The earlier rawOptions interpretation of command-101 body byte zero was
incorrect. SendAFile inspects permission type bits at 0x100002d40–0x100002d54,
passes w4=1 for ordinary files, and passes w4=3 for symlinks at 0x100002ddc.
The directory dispatch passes w4=2 at 0x100002844. SendNewItemMessage stores
that argument in the first body byte at 0x1000033d4. It is an item kind, not a
negotiated metadata option. Start-command flags remain a separate field.

The catalog bridge/collector now derives file=1/directory=2 and no longer
accepts an arbitrary option parameter. The decoder names the preserved byte
rawItemKind; AppleFileCopyItem exposes the three known kinds and retains
unknown bytes without guessing. The sender rejects unknown/symlink kinds and
kind/node-flag contradictions before opening or sending sources.

Real source tests assert file/directory kind, and synthetic unknown/contradictory
kind tests prove they cannot start an ordinary upload. All 115 selected
transfer/transport tests passed:
/tmp/aetherscreens-native-kind-final-tests-20261009.log.
This corrects a concrete invalid-native-upload framing risk; it does not prove
startup flags, complete negotiation or actual RFB server acceptance.

### Item-info totals (2026-10-09)

Receiver command 100 at 0x100002520 checks a payload length of at least 60
(common eight bytes plus 52 body bytes). At 0x100002598–0x1000025d0 it
byte-swaps UInt32 at full offset 14, five UInt64 values at offsets 22, 30,
38, 46 and 54, and UInt32 at offset 62. The native log at 0x1000025f4–
0x1000026a4 labels the five values logical size, physical size, file count,
fork count and folder count; the final UInt32 is allocation size. Logical
size is copied into the total-size field at 0x1000026ac–0x1000026b0.
AppleFileCopyItemInfo decodes these known fields, preserves the four reserved
bytes at body offset 4 and any trailing data, and filters version/session.
Two literal-endian/truncation tests passed:
/tmp/aetherscreens-file-item-info-tests-20261009.log. The totals are sender
claims, not receiver acknowledgements; UI/session negotiation remains open.

Static SendNewItemMessage confirms an explicit UTF-8 conversion for the new
item's name at0x10000354c-0x100003560, followed by an "unable to get utf8
string" error branch. This is a command101 name field, not proof that the
separate command200 final-name field has identical semantics. At
0x100003674-0x100003694, slash bytes in that name are translated to colon
bytes only for the type-3 symbolic-link branch: 0x100003658–0x100003668
loads the item type, compares it to 3 and skips to 0x1000037b8 otherwise.
The earlier unconditional interpretation was incorrect. Treating this legacy Apple filename representation
as an ordinary relative path without conversion could alter names; the exact
receiver conversion and hierarchy/level semantics must be established first.
The subsequent optional symlink branch makes a flat-name-only writer
insufficient for complete native-transfer parity.

The new-item path clears item catalog temporary storage but the compressed
block path's initialization flag is in a different context. No verified reset
boundary was extracted from this inspection. Do not reset the transfer inflater
per item based solely on the new-item event. Exact item/fork lifecycle remains
open, and no live writer/transfer is enabled.

## New-item envelope parsing experiment

Receiver command101 reads hierarchy level at full-message offset106
(0x100003174), name byte length at114 (0x100003224), symbolic-link length
at116 (0x1000032b4), and copies name bytes from118 (0x100003414). The
sender starts the name at queue-object offset138, while its RFB message
starts at queue-object offset20. These independently agree on full-message
name offset118, or body offset104. Sender strlen and next-pointer arithmetic
at0x100003698-0x1000036a8 include a NUL after the name. A symbolic-link target
follows that terminator, with its advertised length excluding its final NUL
(0x100003854-0x10000386c). Additional attributes follow; their grammar remains
unverified and must not be silently dropped.

AppleFileCopyItem now parses version1 command101 for an expected session,
preserving the104-byte catalog header, wire name, hierarchy level, optional
raw link target and remaining extension bytes. It validates UTF-8 names,
name/link boundaries and terminators, without translating legacy names or
creating paths/links. Catalog flags, fork lengths/times/permissions and attribute
semantics are not implemented; parsed metadata alone cannot close parity.
Three new cases plus existing codecs/inflater tests passed19/19, zero failures:
/tmp/aetherscreens-file-copy-item-tests-20261008.log. Synthetic metadata only;
no Mac-server captured fixture or actual destination-file verification.

### Logical fork sizes and directory flags (2026-10-08)

Local SDK CoreServices FSCatalogInfo offsets were checked by compiling a C
offsetof probe: dataLogicalSize = 108 (0x6c), rsrcLogicalSize = 124 (0x7c),
nodeFlags = 0. Native sender 0x10000343c..450 loads these logical sizes,
byte-swaps them, and writes full-message offsets 0x30 and 0x38 respectively.
Consequently command-101 body offsets 34 and 42 contain resource and data fork
sizes in that order. Sender 0x1000034a8..4b4 copies nodeFlags to full offset
0x68 (body offset 90); the SDK directory bit is 0x0010.

AppleFileCopyItem now exposes both UInt64 logical sizes and preserves all node
flags while identifying directories. Four item tests passed, including distinct
big-endian sizes, UInt64.max, unknown flag preservation and empty regular files:
/tmp/aetherscreens-file-copy-catalog-tests-20261008.log. No allocation is based
on these values yet. Real transfer negotiation, item/fork lifecycle, filesystem
writing and resource-fork fidelity remain incomplete.

### Extended-attribute envelope (2026-10-08)

Sender 0x1000037d8..386c reads a symlink's data fork immediately after
name+NUL, then advances its append pointer before attributes are added.
0x100003924..93c writes ASCII ext1, flags zero, version one, and a big-endian
UInt16 length including the ten-byte header. 0x100003a34..40 appends this block
at the resulting pointer. Receiver CheckForExtendedFileAttribute at
0x1000060ac..0ec verifies ext1 and byte-swaps flags/version/length; at
0x1000061a4..1b0 it checks the declared block fits available bytes.

AppleFileCopyAttributeBlock parses this envelope with bounded length, retaining
raw payload and trailing bytes. Unknown magic returns nil; unknown flags/version
are retained without interpreting or applying them. The table within the payload
is not decoded yet. The combined offline AppleFileCopy tests passed 23/23:
/tmp/aetherscreens-file-copy-attributes-tests-20261008.log. This is static framing
validation, not proof of native file transfer interoperability.

### Start-command path framing (2026-10-08)

ServerProcessFileCopyCmd dispatches commands 1/2 to StartFileSend/Receive.
Both read UInt32 flags at full offset 14 and UInt16 path length at full offset
22 (0x1000619a0..a8, 0x100061ab0..ac0, 0x100061e5c..e6c). Receive uses
full offset 24 as destination path and explicitly requires NUL at its declared
end (0x1000624d4, 0x100062508..514). The four bytes at full offsets 18..21
are not yet assigned semantics. The path encoding and empty-path behavior remain
unknown; do not manufacture a filesystem destination from them.

AppleFileCopyStart retains flags, reserved bytes, raw path and trailing bytes,
with bounded length/NUL checks, for offline version-1 commands only. The complete
AppleFileCopy test selection passed 26/26, including all truncated start bodies,
embedded/missing NUL, oversized declared path and session/version filtering:
/tmp/aetherscreens-file-copy-start-tests-20261008.log. No start command was sent
to a real server and capability negotiation is still unverified.

### Outbound envelope and session initialization (2026-10-08)

Native server lazily creates viewer->fileCopyInfo at 0x1000625e8..5f4 and
0x100062a20..a2c when starting sessions; this is not itself a capability
advertisement. No capability bitmap bit was established in this inspection.
The app must not expose supported native transfer merely because a native-auth
session exists.

AppleFileCopyMessage now encodes the verified common envelope: type 0x22,
zero padding, big-endian payload length excluding the six-byte prefix, then
version/command/session/body. Length is checked before body copy and UInt32
conversion. Tests compare output with independent literal bytes and exercise
exact budgets, negative budgets and an empty-body control envelope. Combined
AppleFileCopy tests passed 27/27 in file-copy-encode-tests-20261008.log.
RFBClient still neither advertises native transfer nor sends these messages.

### Version-one attribute table (2026-10-08)

Receiver ExtendedAttributes_ByteSwap reverses the first two UInt32 words and
then each eight-byte length record. ExtendedAttributes_Validate uses size and
entry count at offsets 0/4, with eight-byte key/value length records starting at
8 (0x100001204..210, 0x1000012ac..2cc). ExtendedAttributes_Write consumes a
key including its NUL (0x100001830..844), passes the immediately following value
and its record length to setxattr (0x100001968..980), then advances to the next
key (0x100001988..994). Values are raw bytes, not text.

AppleFileCopyAttributeBlock.entries now decodes zero-flags/version-one tables,
checking table size, count bounds, each key/value length and key termination.
Names and values remain bytes, order is retained, and unsupported flags/version
return nil rather than guessing. The original payload remains preserved even
when bytes beyond the declared table are present. No filesystem attributes are
applied. Combined offline tests passed 28/28 in
/tmp/aetherscreens-file-copy-attribute-table-tests-20261008.log; multi-entry,
embedded binary data, zero-length value, every truncated table and malformed
length records are covered. Native transfer interoperability remains unverified.

### Ordinary-file fork ordering (2026-10-08)

Receiver ProcessNewItemMessage chooses fork 1 when the data fork is nonempty,
otherwise fork 2 for a nonempty resource fork (0x100003db8..3dd4,
0x100003e18..3e28). OpenFileFork maps fork 1 to the unnamed data fork
(0x10000659c..5c4), fork 2 to FSGetResourceForkName (0x1000065c8..5f8,
0x10000664c..660). After a data block exhausts the current fork, receiver closes
it and switches from 1 to 2 if resources remain (0x1000037a8..7d8).

AppleFileCopyForkProgress now tracks separate UInt64 remaining counts, exposes
the active fork in this order, skips zero-length forks and rejects writes across
a fork boundary without mutating progress. It deliberately avoids a potentially
overflowing combined size. This is ordinary-file write accounting only: directories,
symlinks, negotiated session lifecycle and filesystem writes are not implemented.
Combined AppleFileCopy tests passed 31/31:
/tmp/aetherscreens-file-copy-fork-tests-20261008.log. Fork completion alone is
not a server confirmation of successful transfer.

### Disk staging pipeline (2026-10-08)

AppleFileCopyStagingFile connects item fork sizes, data-block validation,
transfer-owned inflater and acknowledged-write progress to real FileHandle writes.
It creates a unique private directory with fixed data/resource filenames, opens
files with O_EXCL/O_NOFOLLOW and mode 0600, and never derives a filesystem path
from the wire name. Declared combined sizes must fit an explicit caller budget
without overflow before creating anything. Directory/link items are unsupported.
After successful writes the corresponding fork count advances. Malformed blocks
or write errors invalidate and remove the attempt; an early finish cannot mark
incomplete data successful. Completed files are synchronized and closed but still
owned by the staging object, whose cancel/deinit removes them.

Tests compare actual disk bytes for two forks and persistent compressed blocks,
verify malformed boundary cleanup leaves an unrelated sibling intact, and check
quota/overflow rejection plus lifetime cleanup. Combined AppleFileCopy selection
passed 35/35: /tmp/aetherscreens-file-copy-staging-tests-20261008.log.
Resource bytes are stored separately, not yet materialized as a destination Mac
resource fork. Final destination overwrite/metadata commit, negotiated transport,
cancellation on the wire and live native byte-integrity acceptance remain open.

### macOS resource-fork materialization (2026-10-08)

Finishing an ordinary Mac staging file now streams its separate resource data
into the owned data file's ..namedfork/rsrc. Copy buffers are at most 64 KiB;
expected source length is enforced before success and the destination fork is
synchronized. A missing/truncated/extra resource source invalidates and cleans
only that staging attempt. No untrusted filename enters the fork path.

The ordinary data contents and actual named resource fork were compared against
source bytes, including a 135111-byte resource spanning multiple copy buffers.
A truncated source was rejected and another completed staging file remained
intact. Combined AppleFileCopy tests passed 36/36:
/tmp/aetherscreens-resource-materialization-tests-20261008.log.
This path is macOS-only. iOS still retains separate resource bytes pending its
export policy. Extended Finder metadata, final destination commit/overwrite,
negotiated native transport and real two-machine acceptance remain incomplete.

### macOS extended-attribute application (2026-10-08)

Completed Mac staging now applies recognized zero-flags/version-one ext1 tables
using fsetxattr on the owned data-file descriptor. Raw attribute names and binary
values are retained. Unknown envelopes/flags/version, extra unrepresented table
bytes, empty names and an attribute competing with the separate ResourceFork
stream are rejected rather than silently discarded or allowed to overwrite a
fork. Any attribute-write failure cancels the staging attempt. No final user
file is modified. The file is synchronized after metadata writes.

A test read the actual binary attribute back through getxattr and verified the
data fork remained unchanged. Unsupported metadata cancelled only its own
staging and left the completed sibling intact. Combined AppleFileCopy tests
passed 37/37, followed by staging tests 6/6 after the table representation check:
/tmp/aetherscreens-extended-attribute-write-tests-20261008.log and
/tmp/aetherscreens-extended-attribute-write-final-tests-20261008.log.
Catalog Finder information/date/permissions remain unapplied; iOS export policy,
final destination overwrite/commit and live negotiated transfer remain incomplete.

### Atomic Mac destination commit (2026-10-08)

Prepared staging can now be moved to a chosen directory with renameatx_np and
RENAME_EXCL, using directory descriptors opened with O_NOFOLLOW. Only a single
validated filename is accepted. A conflict preserves both the existing file and
the prepared staging for retry under another name. Successful cleanup removes
only the private staging sidecar/directory, never the committed destination.
Destination URL validation occurs before the filesystem mutation. Cross-volume
rename errors remain explicit and preserve staging; no copy fallback is claimed.

Tests verify commit-before-finish rejection, existing-file preservation, Unicode
retry names, resource-fork preservation, cancellation after commit, and rejection
of destination directory symlinks and occupied symlink filenames. Initial
AppleFileCopy selection passed 39/39 in
/tmp/aetherscreens-atomic-file-commit-tests-20261008.log. The coordinator still
must confirm the session and apply catalog metadata before calling this helper.
Native transport integration, overwrite UI and physical acceptance remain open.

### End-session error field investigation (2026-10-08)

The captured arm64e sender constructs version-one command 104 with a twelve-byte
common payload at 0x100001788–0x100001794. At 0x10000197c–0x100001988 it reverses
the common payload length, then writes the error register w20 directly at
buffer offset 0x22 (wire body offset zero), without a REV instruction. The
receiver checks native IPC payload length against twelve at
0x10000422c–0x100004238, reads the signed error at full message offset fourteen
at 0x1000042c4 and branches to failure when nonzero. Shorter payloads take a
separate path. These observations show that assuming every body integer is
big-endian would be unsafe: the common header and command body have distinct
conversion rules. They do not yet establish the final wire error byte order
across sender queue and parent IPC forwarding.

No guessed command-104 decoder or live packet was added. Before integration,
trace the remaining sender queue and parent forwarding paths, then independently
verify a nonzero-error fixture. A successful data/resource-fork count cannot
substitute for the explicit session result. Evidence is retained in
/tmp/aetherscreens-file-sender-disassembly-20261008.log and
/tmp/aetherscreens-file-receiver-disassembly-20261008.log.

### End-session queue and inbound forwarding trace (2026-10-08)

SendBuffer (0x100003004) links the allocated buffer without transforming its
message bytes. Its worker removes that buffer at 0x100002ab8–0x100002adc and
passes buffer+0xe and the recorded count directly to WriteToStreamSocket at
0x100002ae8–0x100002af4. The writer at 0x100004958 reaches write at
0x1000049c8–0x1000049d4 with that pointer; short-write handling advances the
pointer without transforming contents. Thus the captured sender-to-parent IPC
path preserves the directly stored command-104 error bytes.

In the inbound parent path, unrecognized control commands (including 104) take
0x100061ff0: the parent sets the IPC type, resolves the session helper, and
passes the same message buffer/count to WriteToStreamSocket at
0x100062008–0x100062014. That writer reaches write directly at
0x100056640–0x10005664c. The earlier common-header conversion changes version,
command and session ID only. This confirms inbound error body bytes are passed
through to the native receiver rather than globally reversed by the parent.

The remaining direction is parent handling of sender IPC for outbound RFB.
Until that path is traced, wire end-error decoding remains deliberately absent.
These conclusions are static evidence from the retained captured binaries, not
a real transfer or a claim of cross-version protocol compatibility.

### Outbound parent path located (2026-10-08)

The outbound helper path is ServerFileSenderThread (starting near
0x100062b3c), not FileReceiveToolListenerThread at 0x100064760. The latter
constructs progress/final-result messages and is a different direction. The
sender thread hands its prepared buffer x24 to 0x10001d4d0 at
0x100063b88–0x100063b90 while holding the output lock. The same output entry
is used at 0x10006361c–0x100063624 and 0x100063dbc–0x100063dc4 under different
backpressure branches. Follow the prepared-buffer read and output entry before
concluding command-104 body byte order. Do not infer it from the unrelated
command-200 final-result construction.

### End result parser and outbound copy evidence (2026-10-08)

ServerFileSenderThread copies IPC buffer+6 into the output buffer at
0x100063090–0x1000630bc, excluding only the tool prefix. It records the output
size and forwards that buffer through 0x10001d4d0. The plain output branch
0x10001d5e0–0x10001d614 forwards the same buffer to 0x10001e7c8; the encrypted
branch consumes its byte range rather than converting command-specific fields.
This closes the parent-copy question: the observed command-104 error body is
not normalized by this copy path.

AppleFileCopyEndSession now recognizes version-one command 104 for the expected
session. Empty bodies are resultAbsent, four zero bytes are success, and four
nonzero bytes are failure with raw bytes retained. Other lengths are rejected.
Zero/nonzero classification avoids guessing numeric error semantics or byte
order across versions. This sender-end event does not substitute for complete
item bytes, metadata application or receiver command-200 acknowledgement.
Literal-frame, absent-result, malformed-length, nonzero-byte-position and
version/session filtering tests passed with the AppleFileCopy selection 41/41:
/tmp/aetherscreens-end-session-tests-20261008.log. No live transport was enabled.

### Receive-session staging coordination (2026-10-08)

AppleFileCopyReceiveSession coordinates negotiated version-one ordinary-file
messages on one transfer worker. It rejects overlapping unfinished items, bounds
aggregate declared data/resource bytes and item count before creating staging,
uses its separate persistent inflater, and advances acknowledged byte counts
only after real staging writes. Completed forks are synchronized/materialized
by the existing staging finish before another item is admitted. Empty ordinary
files also become prepared staging.

Sender-end success is separate from readiness and final destination commit.
Missing/nonzero end results, malformed blocks, unfinished-item end and budget
failures discard only this session's active and prepared staging. Successful
end permits explicit ownership transfer to a finalization coordinator; later
session cancellation cannot delete files whose ownership has transferred.
Tests read actual multiple-file data/resource bytes, exercise incomplete-next
item cleanup while preserving an unrelated sibling, reject missing/failed end
results and enforce byte/item budgets. AppleFileCopy selection passed 44/44:
/tmp/aetherscreens-file-copy-receive-session-tests-20261008.log.

The class is not yet wired to RFBClient or a UI. Directory/symlink hierarchy,
catalog metadata, native total-manifest validation and cross-item inflater
lifecycle compatibility remain incomplete. Other control/totals commands are
left to the negotiated owner; no arbitrary inbound session opens files. Actual
server transfer and physical UI acceptance remain required.

### Cross-item compression checkpoint (2026-10-08)

The captured sender tests its context initialization flag at x19+0x208
(0x100004180–0x100004184); deflateInit2 is reached only when uninitialized.
The receiver similarly tests x23+0x3a at 0x100002dc4–0x100002dc8 and stores
that flag at 0x100002e40. Only one deflateInit2/inflateInit call site was
found, with no named deflateReset/inflateReset/end call sites in the captured
disassembly. This supports retained contexts but does not exclude an opaque
whole-context reset or prove cross-version lifetime.

A new receive-session regression uses one persistent Z_SYNC_FLUSH deflater
for two ordinary items. The second packet cannot inflate with a fresh inflater,
but succeeds through the session after the first item has been prepared; both
disk files compare byte-exact and acknowledged bytes match. Four session tests
passed: /tmp/aetherscreens-cross-item-compression-tests-20261008.log. This is
synthetic cross-item coverage; actual native sender lifetime remains an
interoperability gate.

### Bounded file-worker bridge (2026-10-08)

AppleFileCopyReceiveWorker supplies quick thread-safe admission to a dedicated
serial utility worker. File decode/staging stays off RFB's connection worker;
queued and in-flight wire bytes share an explicit pending-memory budget
(default 4 MiB). Overflow closes admission and cancels owned staging instead
of silently dropping a block or growing an unbounded queue. Wrong sessions
are rejected at admission. User cancellation invalidates queued work and
cleans up on the file worker; reentrant cancellation at the sender-end event
prevents prepared-file ownership handoff. Files in the prepared callback must
be finalized/retained/cancelled on that worker by their new owner.

Four worker tests plus four receive-session tests passed, including deliberately
suspended queues for cancellation/overflow and reentrant end cancellation:
/tmp/aetherscreens-file-worker-cancellation-tests-20261008.log. Ordinary-file
worker processing, pending budget, cleanup and ownership are verified locally.
There is no installed product coordinator/hook or live native negotiation yet.
No measured rendering/input-latency improvement is claimed until that integration
and actual-server acceptance are complete.

### RFB receiver installation and lifecycle (2026-10-08)

A negotiated owner can now explicitly install one receive worker in a connected
native-banner RFBClient. Matching session commands 101...104 are admitted to
that worker; totals/status/control messages still reach the owner hook and
are not mistaken for writes after sender completion. Admission failure fails
the connection instead of dropping a file block. Explicit disconnect and
connection failure cancel/detach the installed receiver. Removal checks worker
identity so an obsolete owner cannot detach a replacement. No public UI starts
or installs a receiver before actual transfer negotiation.

A real loopback TCP integration test holds the file queue while receiving
item/data/resource/end and a following control frame. The following frame
arrives before any disk write; releasing the worker produces exact data and
resource bytes. A command-200 result after sender completion remains readable
and leaves the RFB session connected. A separate test disconnects after staging
but before sender-end and verifies cleanup/closed admission. These tests plus
existing native dispatch/worker coverage passed 12/12:
/tmp/aetherscreens-file-receiver-lifecycle-tests-20261008.log. This establishes
the internal connection/file-worker bridge with synthetic frames, not actual
Apple transfer negotiation, catalog completion, final UI or native acceptance.


### Outbound totals and helper framing checkpoint (2026-10-09)

Command 100 now has a bounded outbound encoder. It preserves the opaque flags,
four reserved bytes and trailing extension bytes, emits the five UInt64 totals
and allocation size in big-endian order, and includes the common eight-byte
header in its allocation bound. Invalid reserved lengths are rejected. An
independent literal full-RFB-frame fixture covers nontrivial byte order,
UInt64.max and an extension byte; boundary and malformed-input coverage passed
4/4 in /tmp/aetherscreens-totals-encoder-tests-20261009.log. These totals are
reported metadata, not acknowledged progress or evidence of remote completion.

The native helper must not be driven with unmodified RFB frames. In the retained
receiver disassembly, GetNextMessage (0x1000050fc) reads a six-byte local prefix,
uses native-order UInt16 command and UInt32 size, and reads size bytes after it
(0x100005330..0x1000053c0). Local command 1 reaches the abort branch
(0x100004068); the regular receive loop then dispatches the native-order common
command at offset 8. StartFileReceive command 2 checks the common version at
offset 6: version >= 2 enters a different length check with two native-order
UInt16 lengths at offsets 22 and 24 (0x100002998..0x1000029b8). This indicates
parent/helper initialization needs tracing before a direct-helper probe can
represent the network path. It does not establish public RFB version 2 support.
No helper has been launched by this checkpoint.

Verification for this encoder checkpoint: all 99 AppleFileCopy-selected tests
passed (/tmp/aetherscreens-totals-transfer-regression-20261009.log); generic
unsigned iOS build succeeded (/tmp/aetherscreens-totals-ios-build-20261009.log).
This is scoped regression evidence; the full-app Keychain SSH gate and physical
iPhone/native-server acceptance remain outstanding.


### Mac mini direct-helper probe is rejected by launch constraints (2026-10-09)

On the authorized Mac mini (100.64.0.3), sw_vers reported 27.0.1 and the SSH
process UID was 501. A small read-only CFPreferences probe queried exactly
ARDCollectLogs / com.apple.RemoteManagement / AnyUser / CurrentHost and found
logging disabled. A unique temporary destination was created, then the installed
SSFileCopyReceiver executable was launched with a local initialization frame
and immediate abort, under a ten-second subprocess deadline. It exited by
SIGKILL (-9) immediately, with no stdout/stderr or destination entries.

The current unified log at 2026-10-09 01:28:48 explicitly reports AMFI Launch
Constraint Violation (enforcing), Constraint not matched, for launching this
helper from the Xcode Python process. Thus the probe did not exercise helper
framing, version handling, destination parsing or file receipt. Repeating direct
launches or changing the system helper signature would not validate the normal
server path. The exact owned temporary directory and its five known children
were validated and removed; no user destination was used. The OS-generated
DiagnosticReports entry was left intact.

The live RFB negotiation probe then succeeded for both client 003.008 and
003.889, observing server 003.889, security types 30/33/36/31/32/2/35 and an ARD
DH challenge (generator 5, 512-byte key length). No credentials were submitted.
Evidence: /tmp/aetherscreens-native-negotiation-20261009.json. This establishes
server availability and authentication challenge only, not file-copy capability.
Future native receipt validation must use an authenticated server-owned launch.

Parent trace checkpoint: StartFileReceive validates the network destination
NUL at path + length (0x100062508..0x100062514), allocates a session context,
and resolves the active user's UID/GID through SSAgent_GetUserAndGroup_rpc
(0x10006260c..0x100062618). This adds a user-session prerequisite to the formal
server path; standalone helper initialization is not equivalent.


### Receive-side native item-kind admission (2026-10-09)

The negotiated ReceiveSession now rejects unknown or symbolic-link item kinds,
and mismatches between file/directory kind and catalog directory flags, before
manifest admission or staging creation. This matches the outbound kind check;
the raw codec still preserves opaque kinds for inspection. Rejection transitions
the session to failed and discards only its owned staging. A dedicated test
covers kind 0, 255, symlink 3 and both file/directory contradictions, verifying
empty manifest and no filesystem entries after each failure. Existing synthetic
receive/worker/fork-reader/TCP fixtures now explicitly use native kind 1 for
files and kind 2 for directories instead of historical zero placeholders.

A first regression run found one remaining zero-kind fork-reader fixture
(131 selected tests, one failure); that fixture was corrected and the same
selection rerun. Generic unsigned iOS build succeeded in
/tmp/aetherscreens-receive-kind-ios-build-20261009.log. Real native-server
file receipt remains unverified: the startup destination/version transformation
must be established before sending a controlled destination through that path.

Final receive-kind regression: 131/131 selected AppleFileCopy and
PointerTransport tests passed, including 31 loopback transport tests
(/tmp/aetherscreens-receive-kind-final-tests-20261009.log). git diff --check passed.


### Local upload transport completion (2026-10-09)

RFBClient.sendAppleFileCopy now accepts an optional processed(Bool) callback.
A false admission return does not schedule it. For an admitted packet, queue
invalidation after reconnect/observe-mode generation change reports false;
network write error, encryption failure or lost connection identity also report
false, and Network.framework contentProcessed success reports true. This is
local transport completion only, never server persistence or a byte ACK.
The sender owner can use it to pace a subsequent pump instead of filling the
network queue based on admission alone. No automatic sender worker or public
capability advertisement has been enabled by this change.

The existing held-connection-queue loopback test now asserts stale generation
callback=false and fresh generation callback=true, exactly once through XCTest
expectations, while only the fresh frame reaches the peer. Focused test passed
in /tmp/aetherscreens-file-send-completion-tests-20261009.log.

The completion-callback change passed 131 selected AppleFileCopy/transport
tests (/tmp/aetherscreens-send-callback-regression-20261009.log) and the
generic unsigned iOS build (/tmp/aetherscreens-send-callback-ios-build-20261009.log).
No measured input-latency or native-file-acceptance improvement is claimed.


### Paced upload worker (2026-10-09)

AppleFileCopySendWorker runs source reading and session pumping on a serial
utility queue. The negotiated owner supplies its transport closure and starts
it after start/totals negotiation. At most one file packet is in flight; only
its successful local transport callback releases the next pump. Queue admission
rejection or local write failure stops the attempt and closes its reader.
Callback tokens ignore duplicates and late completions. Synchronous callbacks
are serialized after pump commits admission, including callback-before-false
admission rejection. Cancellation closes admission immediately and suppresses
late callbacks. Inbound status admission is bounded to 32 pending messages,
with each status body at most 64 KiB; wrong-session/non-status frames are rejected.

Server success can arrive before the final local callback, but completion is
reported only after both server success and the last local write complete.
This prevents a locally failed final write being presented as a completed job.
No payload/source deletion occurs. Existing SendSession still owns raw packet
production and validates sources/hierarchy/aggregate byte budget. The worker
has no public UI or automatic RFB installation yet, and does not implement a
remote resume protocol.

Focused worker tests cover one-at-a-time item/data/end order, duplicate callbacks,
final local-write plus remote-result gating, source preservation, write failure,
explicit cancellation and rejected admission with a synchronous callback.

Paced-worker checkpoint passed 134 selected file-copy/transport tests
(/tmp/aetherscreens-send-worker-regression-20261009.log), generic unsigned
iOS build (/tmp/aetherscreens-send-worker-ios-build-20261009.log), and
git diff --check. RFB owner/lifecycle integration and native-server receipt
remain outstanding; perceived input/rendering latency is not yet measured.


### RFB upload owner and connection lifecycle (2026-10-09)

A negotiated owner can explicitly install one AppleFileCopySendWorker into a
connected native-banner, input-enabled RFBClient. Installation does not start
it, negotiate, or advertise file-copy support. Sender and receiver cannot own
the same session ID. Matching command 200/300 server statuses are admitted to
the sender while the existing owner hook still observes the messages. Terminal
or rejected status admission does not fail the desktop connection; the worker
reports its own failure. Explicit disconnect and connection failure detach and
cancel the sender. Removal checks object identity so an obsolete owner cannot
cancel its replacement. A completed owner must remove its sender before another
upload is installed.

A real loopback TCP test uploads an item, two one-byte blocks and sender-end;
the synthetic peer returns command 200, and completion leaves the desktop RFB
connection active. It then removes that owner, installs a replacement, verifies
old-owner removal is harmless, disconnects and checks the replacement rejects
start/status admission with the source file unchanged. Focused test passed:
/tmp/aetherscreens-upload-lifecycle-focused-20261009.log. This tests the internal
lifecycle and local TCP bridge, not native-server negotiation, destination
selection, public UI, measured input latency or physical-device acceptance.

Upload-lifecycle regression passed 135 selected file-copy/transport tests
(/tmp/aetherscreens-upload-lifecycle-regression-20261009.log), generic unsigned
iOS build (/tmp/aetherscreens-upload-lifecycle-ios-build-20261009.log), and
git diff --check. Full-app/physical/native acceptance gates remain open.


### Upload wait deadlines (2026-10-09)

The paced sender now bounds waiting for each local transport callback (default
30 seconds) and for the final server result after sender-end's local write
(default 60 seconds). Both are configurable finite positive values up to one
hour. They are not a total-file-size deadline; status/progress updates do not
renew the final-result deadline. A single reusable monotonic DispatchSourceTimer
per worker prevents accumulating a timer closure for every file block. Timer
events verify the current absolute deadline, and completion/failure/cancellation
cancel that timer. A timeout stops the attempt and closes its source reader,
without treating queued bytes or server progress as successful saving.

Focused tests passed 4/4 in /tmp/aetherscreens-upload-deadline-tests-20261009.log,
covering absent local callbacks and absent final results, late completion after
expiry, original source preservation and the existing pacing/failure cases.
Cancellation coverage also uses a short write deadline and an inverted failure
expectation extending beyond it. These deadlines bound asynchronous wait phases;
they do not interrupt synchronous filesystem reads or a misbehaving blocking
transport closure on the serial worker. Default timeout durations still need
real native-server/large-transfer acceptance before public exposure.

Deadline checkpoint passed 136 selected file-copy/transport tests
(/tmp/aetherscreens-upload-deadline-regression-20261009.log), generic unsigned
iOS build (/tmp/aetherscreens-upload-deadline-ios-build-20261009.log), and
git diff --check. This does not establish native-server or iPhone acceptance.


### Final-write deadline gate on Mac mini (2026-10-09)

An additional worker test admits sender-end without its local completion,
then receives successful server command 200. The local write deadline still
fails the attempt; a subsequent late end-write callback cannot revive it or
produce completion. The worker selection now passes 5/5 on the host
(/tmp/aetherscreens-final-write-gate-final-tests-20261009.log) and the authorized
Mac mini via CLI xctest (/tmp/aetherscreens-worker-mini-tests-20261009.log).
The latter uses actual macOS filesystem/temp fixtures and background timers,
without GUI or system clipboard interaction. Exact owned QA root/bundle/archive
were validated and removed after the terminal test run. This confirms portable
worker/deadline behavior, not actual native-server file receipt. Only test code
changed since the previous passing iOS build.


### Receiver startup destination mapping (2026-10-09)

Retained target disassemblies now resolve an important version-one ambiguity.
The local IPC command written as UInt16(2) at server 0x1000618dc is separate
from the common message version at local-buffer offset 6. It is not evidence
that the server upgrades the message to version two. The parent reverses
flags and path length, passes the path at offset 24 to the helper opener,
and forwards the local six-byte prefix plus payload at 0x100062774–784.

The receiver reads the common version at 0x100002998. For version less than
two, its old-profile branch at 0x100003654 uses the path at offset 24 and
length at offset 22, then calls GetDestinationFolderFSRefFromPath at
0x10000368c–690. Thus this branch does consume the supplied destination;
it does not unconditionally select Desktop. For version two and above,
the path starts at offset 26 and an additional length participates in
validation. This does not authorize generating a version-two message.

GetDestinationFolderFSRefFromPath (0x100005484) recognizes a leading tilde
and resolves it through FSFindFolder and FSRefMakePath before appending
its suffix. Other paths are rebuilt by components and resolved with
FSPathMakeRef; a bare slash takes a direct FSPathMakeRef branch. Component
processing includes a special /Volumes startup-volume case. The next
component offset is explicitly masked with 0xff at 0x100005688, so a long
path must not be assumed safe merely because wire length fits UInt16.
Any live fixture should use a short absolute unique owned path, avoid
/Volumes and tilde semantics, and verify its resulting location independently.
The existing raw framing codec deliberately remains unchanged.

FileCopyTool_OpenReceiverWithUIDAndGID (0x100060d70) retains the tool state
and UID/GID arguments but does not retain its incoming destination pointer
before calls. Its spawn argument vector at 0x10006109c–0bc contains the
helper executable plus the two formatted numeric arguments; no destination
argument is added. The destination therefore travels in the subsequent IPC
start message, rather than this observed command-line argument vector.

Evidence: /tmp/aetherscreens-file-server-disassembly-20261008.log and
/tmp/aetherscreens-file-receiver-disassembly-20261008.log. These are static
facts for the inspected target build. No helper was launched or transfer
packet sent in this checkpoint. The previous direct-launch AMFI constraint
failure remains valid; native acceptance still requires the authenticated
server to launch its own helper and an owned-fixture receipt comparison.


### First authenticated native upload receipt (2026-10-09)

NativeFileUploadLiveTests.testOwnedNativeUpload now provides an explicitly
opted-in probe, limited to the authorized LAN Mac and a short UUID-owned
/tmp/aetherscreens-native-upload-UUID/destination path. It creates only its own
512-byte local fixture (bytes 0...255 twice), collects real catalog metadata,
authenticates through RFBClient, sends version-one start-receive and command100
totals, then uses the paced worker for item/data/end. All local writes have
bounded waits and successful final server result is required; the test does
not claim that result alone proves remote persistence.

The real run at 02:58:10–12 passed 1/1 without a skip in 1.815 seconds. The
server returned version1 command200 with a 16-byte body. A separate SSH Python
read found exactly fixture.bin in the owned remote destination, a regular
non-symlink 512-byte file with mode0644. Its entire content equaled the expected
byte sequence, SHA256
110009dcee21620b166f3abfecb5eff7a873be729d1c2d53822e7acc5f34eb9b.
The RFB test also verified the desktop connection remained connected and its
original local source remained byte-identical. This exercised server-owned
helper startup, not a direct helper invocation or system-signature change.
Before connection, console owner was root and pgrep found no SSAgent; this
observation therefore must not be used by itself to prohibit the authenticated
server path, which successfully resolved this attempt.

After comparison, the exact unique remote directory, its sole destination
child and sole matching fixture were validated and removed. Local test fixtures
are removed by defer. Evidence: /tmp/aetherscreens-native-upload-live-20261009.log;
build/opt-in skip verification:
/tmp/aetherscreens-native-upload-probe-build-20261009.log. git diff --check passed.
This establishes single ordinary-file upload interoperability only. Empty files,
folders, resource forks, overwrite rejection, cancellation, native download,
public drag/drop UI and physical iPhone acceptance remain unproven.


### Native nested-folder and empty-file upload receipt (2026-10-09)

The explicit owned-fixture probe now also exercises a level0 folder, level1
empty file, level1 nested folder, level2 131073-byte binary file, then a level1
three-byte sibling. This includes an ascent after nested content and three
standard-size data chunks in the large file. Original local contents are
checked after completion. No product UI or negotiation preference changed.

At 03:00:18–20 the real LAN folder probe passed 1/1 without skips in 1.778s,
with version1 command200 body length19 and the RFB connection still connected.
Independent SSH validation found exactly five expected destination entries,
no symlinks, the correct two-folder hierarchy, an actually zero-byte empty
file, exact sibling bytes 00 ff 2a, and all 131073 binary bytes equal to the
expected repeating byte pattern plus its final zero. The large file SHA256 is
59143c73fbc669c18bdeb36c7cfa13888c03a2d935b18d939c628692360c16ff.
The exact UUID root, full expected tree and contents were revalidated before
removing only that owned tree. Log:
/tmp/aetherscreens-native-folder-live-20261009.log.

The final Release build succeeds; without explicit opt-in both native probes
skip without network/file-transfer activity:
/tmp/aetherscreens-native-folder-final-build-20261009.log. An initial fixture
tuple Int/UInt16 inference compile error was corrected with explicit UInt16
levels. git diff --check passed. This establishes ordinary nested directories,
empty files and multiple-block uploads for this target. Resource forks,
attributes/permissions, conflicts, cancellation, downloads and public UI still
need their own real acceptance evidence; no broad parity claim is made.


### First authenticated native download receipt (2026-10-09)

The explicit download probe restricts its source to the authorized LAN Mac's
short /tmp/aetherscreens-native-download-UUID/fixture.bin path. This fixture is
created by the authorized SSH caller, never chosen from user files. Start-send
uses version1 command1 and flags1: the inspected parent tests flags bit0 at
0x100062370–378 and its unset branch logs "do not start file send". The
receiver is installed before the request, uses a 131073-byte/one-item budget,
and commits through the existing private staging/RENAME_EXCL path.

At 03:02:19–21 the real probe passed 1/1 without skips in 1.737s. Received
commands were version1 100(body52), 101(body116), 102(body65540),
102(body65540), 102(body5), and 104(body4). The committed file name was
fixture.bin; all 131073 local bytes matched the expected repeating pattern
plus final zero. The desktop connection remained connected. Independent SSH
read afterward confirmed the remote source byte-identical, SHA256
59143c73fbc669c18bdeb36c7cfa13888c03a2d935b18d939c628692360c16ff.
The exact remote directory and sole expected source were validated before
cleanup, and local staging/committed test output were removed by the test defer.

Evidence: /tmp/aetherscreens-native-download-live-20261009.log. Release build
and default explicit skips (three probes) passed in
/tmp/aetherscreens-native-download-build-20261009.log; git diff --check passed.
This establishes actual ordinary-file download through the network, receiver,
private staging and final commit. It does not establish a final client-to-server
receiver acknowledgment or server session retirement; this probe disconnects
its owned connection at completion. Download folders/resource forks/metadata
acceptance, conflicts, cancellation and product drag/drop UI remain separate
gates. No overall Screens parity or physical-device acceptance is claimed.


### Download session reuse without desktop disconnection (2026-10-09)

Static ServerFileSenderThread teardown explicitly removes the ID from its
session list at 0x100064608–614, shuts down the helper when appropriate at
0x100064618–62c and releases session state at 0x100064630–634. This supplies
an actual server-side retirement path; client command200 must not be invented
as mandatory solely from the upload receiver's status grammar.

The live download probe now reuses one session ID for two sequential requests
on the same authenticated desktop connection, installing/removing each local
receiver and committing into separate empty owned directories. No client200
or intervening desktop disconnect is sent. At 03:04:34–36 it passed 1/1 in
1.803s, without skips: two complete 100/101/three102/104 sequences were received
and both newly committed 131073-byte files were fully compared. Connection
remained connected after each attempt. This proves repeated same-ID transfers
work in this target build, rather than relying on disconnection to clear state;
it does not directly measure all server allocations or long-run leakage.

Log: /tmp/aetherscreens-native-download-reuse-live-20261009.log.
Release/default-skip gate: /tmp/aetherscreens-download-reuse-build-20261009.log.
The independent remote source was verified unchanged before removing its exact
owned UUID directory. Local attempt directories are removed by defer.
Formatting and git diff --check passed. Earlier acknowledgment/session-retirement
uncertainty is narrowed by this evidence; cancellation, conflicts, resources,
folder download and public drag/drop remain open.


### Typed controls and stopped-transfer recovery (2026-10-09)

AppleFileCopyControl represents version1 header-only pause3/resume4/stop5,
with no implicit public support. ServerProcessFileCopyCmd at 0x100061734–73c
applies the larger start-message size check specifically to commands1/2;
command5 reaches 0x100061848–854, supplying sessionID and state5 to the session
control function at 0x10006075c. No path/body field is consumed by that branch.
Independent literal stop wire bytes and unknown version/session/body/command
rejection pass 2/2 in /tmp/aetherscreens-file-control-tests-20261009.log.

A real probe starts an empty receive session, locally completes stop5 on that
ID, then starts a different upload ID on the same desktop connection. At
03:07:21–23 it passed 1/1 without skip in1.718s. The new transfer returned
successful command200, desktop stayed connected, and independent SSH confirmed
exactly fixture.bin with all512 expected bytes in the owned destination. The
complete owned tree was verified and removed. Evidence:
/tmp/aetherscreens-native-stop-recovery-live-20261009.log.

This proves header-only stop does not break this desktop connection and the
following upload can complete. It is not proof of mid-stream cancellation,
server helper allocation release, partial-file cleanup, pause/resume timing or
same-ID stop reuse. Worker cancellation remains explicit/local; controls alone
never claim acknowledged cancellation. File-copy Release regression passed
110/110 in /tmp/aetherscreens-control-file-regression-20261009.log.

iOS generic unsigned build also passed: /tmp/aetherscreens-control-ios-build-20261009.log. git diff --check passed.


### Mid-upload stop leaves a partial remote file (2026-10-09)

The new explicit probe sends native start/totals/catalog for an owned512-byte
partial.bin, then one raw128-byte data block and stop5 without sender-end104.
It subsequently uploads a separate fixture.bin on the same desktop connection.
At03:09:38–40 the recovery test passed1/1 in1.731s, without skips: source contents
were unchanged and the subsequent512-byte upload completed with command200.
Log: /tmp/aetherscreens-native-partial-stop-live-20261009.log.

Independent SSH inspection contradicts automatic-cleanup assumptions:
destination contained fixture.bin512 bytes AND partial.bin128 bytes. The
partial contents exactly equaled the first128 source bytes. Thus native stop
on this inspected build preserves an unfinished remote file under its final
ordinary name. Successful test here proves desktop/recovery behavior, NOT clean
cancellation. Product handling must preserve this distinction and must not
advertise remote cleanup from local worker cancellation or stop write completion.
A safe remote cleanup/finalization mechanism still needs explicit protocol
research; deleting an arbitrary matching destination would be unsafe because
identity/ownership cannot be inferred from filename alone.

Both known files, bytes, non-symlink status, exact parent and expected children
were checked before removing only the UUID-owned test root. Release/default-skip
build passed /tmp/aetherscreens-partial-stop-build-20261009.log. git diff --check
passed. No production cancellation UI or arbitrary remote deletion was added.


### Native same-name conflict preserves existing file by renaming (2026-10-09)

A fresh owned UUID destination was seeded through authorized SSH with
fixture.bin containing28 sentinel bytes QA-existing-do-not-overwrite. The
existing explicit single-file upload probe then uploaded512 different bytes
under the same requested name. At03:10:57–58 it passed1/1 without skips in
1.676s, returning command200 body length18 with the desktop still connected.
Independent remote inspection found exactly fixture.bin28 bytes (sentinel
unchanged) and fixture 2.bin512 bytes (all expected upload bytes identical).
Thus this target's default flags0 ordinary-file conflict policy auto-renames
rather than overwriting or rejecting. Evidence:
/tmp/aetherscreens-native-conflict-live-20261009.log.

The future coordinator/UI must consume the worker's successful destination-name
bytes instead of assuming the requested name is the committed name. This does
not establish overwrite authorization, Unicode result decoding, folder conflict
policy or user-selectable replacement. The exact parent, two expected entries,
regular/non-symlink files and both contents were verified before removing only
the owned fixture tree. No product overwrite behavior changed.

Receiver abort investigation found sender/user-abort branches at
0x100004068/08c converging on0x100004960; these observed entry points alone do
not establish a deletion command. Together with the actual128-byte residual
probe, remote cleanup remains unaccepted. Do not delete a matching arbitrary
remote filename as a substitute for establishing ownership and safe cleanup.


### Actual data/resource-fork upload (2026-10-09)

The opt-in probe now creates an owned512-byte data fork plus257-byte real macOS
named resource fork, collects catalog metadata through the existing collector,
and sends it through the existing fork-aware worker. The aggregate budget is
769bytes and totals report two forks; no product default or public UI changed.
At03:14:23–25 it passed1/1 without skips in1.935s, receiving successful200.
Independent SSH read found exactly fixture.bin, matching all512 data bytes and
all257 resource bytes read via ..namedfork/rsrc. Local source and resource bytes
remained identical and desktop state remained connected. The full owned tree,
file type and both fork contents were verified before cleanup.

Evidence: /tmp/aetherscreens-native-resource-live-20261009.log.
Release/default-skip build: /tmp/aetherscreens-native-resource-build-20261009.log.
git diff --check passed. This proves resource-fork upload preservation on this
Mac target, not resource-fork download, arbitrary extended attributes, Finder
metadata dates, ACLs, lock semantics or public drag/drop acceptance.


### Real resource-fork download and final materialization (2026-10-09)

The explicit download fixture now also supports512 data bytes and257 resource
bytes with a769-byte aggregate receive budget. At03:15:53–54 its real test passed
1/1 without skips in1.781s, performing two downloads with the same sessionID
and desktop connection. Each received100/101/102(body516)/102(body261)/104,
committed into a different owned local directory, and compared all512 data
bytes plus257 bytes read from the committed file's actual ..namedfork/rsrc.
Desktop remained connected after each attempt. Independent SSH confirmed both
remote source forks unchanged before validating/removing the sole owned source.
Local completed outputs/staging are removed by defer.

Log: /tmp/aetherscreens-native-resource-download-live-20261009.log.
Release/default-skip build: /tmp/aetherscreens-resource-download-build-20261009.log.
git diff --check passed. Resource-fork preservation is now directly established
for both upload and download on this target, including local receive final
materialization. Extended attributes, Finder dates, ACLs, directory downloads,
clean cancellation and public file-transfer UI remain separate unmet gates.


### Actual nested-folder download and assembly (2026-10-09)

The explicit directory source fixture contains fixture-folder, empty.bin,
sibling.bin(three bytes), nested and nested/fixture.bin(131073bytes). The
receiver has five-item/131076-byte budgets and finalizes through existing tree
assembly and exclusive root commit. At03:17:22–24 its real probe passed1/1
without skips in1.834s. Two sequential requests reused one ID on the same
desktop connection and committed into separate local destinations. Each
committed tree's exact recursive entry set matched the fixture, with empty
file length0 and every sibling/large binary byte equal to the expected data.
Desktop remained connected. Native sender traversal order differed from the
upload fixture order, still producing the same final tree.

Log: /tmp/aetherscreens-native-folder-download-live-20261009.log.
Release/default-skip build: /tmp/aetherscreens-folder-download-build-20261009.log.
Independent SSH verified the full original remote tree and all contents
unchanged before checking/removing its exact UUID-owned root. Local staging and
completed trees are removed by defer; git diff --check passed. Ordinary nested
directories and empty files are now demonstrated in both directions on this
target. Clean remote cancellation, directory name conflicts, symlink policies,
additional metadata and publicly integrated drag/drop remain unaccepted.


### Unicode upload and successful-result name encoding (2026-10-09)

The explicit ordinary-file probe now also uploads 测试-屏幕😀.bin and requires
the worker completion's raw destination-name bytes to equal the original UTF8
encoding exactly. At03:19:06–08 the real test passed1/1 without skips in1.829s,
with command200 body26 and connected desktop state. Independent SSH found the
exact expected Chinese/emoji name and all512 binary contents equal. Local
source stayed unchanged. Exact owned directory/file types, name and contents
were checked before cleanup; git diff --check passed.

Log: /tmp/aetherscreens-native-unicode-upload-live-20261009.log.
Release/default-skip build: /tmp/aetherscreens-unicode-upload-build-20261009.log.
This directly establishes UTF8 successful destination-name bytes and ordinary
Chinese/emoji upload naming on this inspected Mac target. It does not prove
other server profiles, normalization-equivalent spellings, slash/colon result
conversion, Unicode path requests or Unicode same-name auto-rename policy.
Retain raw bytes in the model; a display decoder should fail cleanly on unknown
encodings rather than use replacement decoding or construct a filesystem path.


## Native sender xattr whitelist inspection (2026-10-09)

The inspected helper disassembly at
`/tmp/aetherscreens-file-sender-disassembly-20261008.log` shows
SendNewItemMessage calling ExtendedAttributes_Read at 0x10000387c.
ExtendedAttributes_Read (0x10000511c) reads only
`com.apple.quarantine` and `com.apple.metadata:kMDItemWhereFroms`
through its getxattr helper (0x10000549c; getxattr at 0x100005500).
The inspected routine counts the nonempty results of these two reads;
it does not enumerate arbitrary xattr names. This explains the observed
zero extension bytes for the owned com.aethernative.qa fixture without
assuming an undocumented protocol version or flag. This finding applies
to this inspected sender, not every Screen Sharing server version.

The coordinated live test now has a separate opt-in
AETHERSCREENS_QA_DOWNLOAD_WHEREFROMS=1 for a binary-plist source URL
attribute. It checks the saved attribute through an O_NOFOLLOW descriptor
and parses the plist to compare the owned public QA URL. The original
arbitrary-xattr opt-in remains distinct; a whitelist check cannot prove
arbitrary attribute fidelity. Physical iOS/provider metadata acceptance
remains outstanding.


2026-10-09 05:13 — native WhereFroms acceptance
The separately opted-in coordinated folder download passed against the
actual Mac mini: 1 test, zero skips/failures, 1.965 seconds. Three requests
used the same native ID/connection: two complete saves and one protected
destination conflict. Each nested file emitted 137 extension bytes.
Both successful saves retained the binary-plist WhereFroms URL; data,
resource fork, mode and modification-time assertions also passed.
Log: /tmp/aetherscreens-wherefroms-native-live-20261009.log.
SSH independently verified the exact owned source tree, all bytes, resource
fork, mode, time and source plist before removing only that UUID fixture.
The arbitrary com.aethernative.qa attribute limitation remains; this test
does not replace its failed acceptance. Physical iOS/provider/UI acceptance
and the wider Screens alignment remain incomplete.
