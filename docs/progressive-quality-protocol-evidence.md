# Progressive adaptive quality — protocol evidence and release gate

Reviewed 2026-10-05. Real progressive adaptive quality remains an open first-release requirement. The new capability report and negotiation checks prevent an incorrect success claim; they do not implement progressive image decoding.

## Evidence

- [Edovia's official feature description](https://help.edovia.com/en/screens-5/features/images-quality/) describes Mac Adaptive Quality as multiple passes with increasing detail. The same page describes Compression separately as a server-produced 50% desktop. A confirmed `ScaleFactor` change therefore proves compression only.
- [The IANA RFB registry](https://www.iana.org/assignments/rfb#rfb-4) assigns image encodings 1000–1002 and 1011 to Apple. It does not specify their payload grammar, a capability acknowledgement or a decoder.
- [The protocol maintainers' encoding list](https://github.com/rfbproto/rfbproto/blob/master/rfbproto.rst) likewise identifies these as Apple-assigned encodings. Its `SetPixelFormat` section forbids switching formats with an outstanding framebuffer request. Changing colour depth while Apple push updates may still be in flight is not a safe substitute for progressive refinement.
- [iShareScreen's original protocol research, section 8.9.4](https://github.com/renegadelink/iShareScreen/blob/main/docs/apple_vnc_rfc.md#894-multi-variant-scaled-0x3f3), describes 1011 (`0x3f3`) as a tile codec and explicitly retains a command-code mapping gap. It also says its captured session emitted no `0x3f3` rectangle. This is research evidence of missing information, not an Apple specification or a validated decoder to port.
- [The same author's current session implementation](https://github.com/renegadelink/iShareScreen/blob/main/src/isharescreen/proxy/session.py) skips the 1011/`0x3f3` group rather than decoding image pixels; its displayed image path is HEVC media. Its skip branch assumes a 16-bit length whereas the research describes a 32-bit MVS body length. That branch is not a reusable MVS decoder or sufficient evidence for blindly skipping a received TCP image rectangle.

The current client implements Raw, CopyRect, Zlib and ZRLE image decoding. Apple display-layout metadata and server scaling do not add a progressive codec. There is no verified progressive decoder or multi-pass pixel reconstruction in this client.

## Implemented boundary

`RFBEncoder.sessionEncodings(supportsAppleDisplayMetadata:)` is the single source used by `RFBClient.setupSession` for supported encodings. It excludes unimplemented Apple image codecs. An unexpected encoding still terminates the connection because its payload cannot safely be skipped.

`RFBClient.imageQualityCapabilities` reports `progressiveAdaptiveQuality` as `notConnected` or `clientDecoderUnavailable`. This reports a client limitation; it must not be interpreted as a claim that the remote Mac lacks encoder support. `supportsServerScaling` independently requires an active Apple connection and an actual Apple layout.

The added protocol tests cover exact negotiation bytes, real TCP negotiation with no 1000–1002/1011 advertisement, unchanged progressive availability after confirmed half-size scaling, and rejection of an opaque unexpected 1011 payload without publishing it as pixels. These tests are queued for the isolated Mac mini run; they have not been run on the development Mac.

## Required next evidence

1. In the authorized controlled Mac mini environment, use a test account and a known visual pattern with the native client to compare Adaptive Quality on/off while keeping server scaling constant. Retain the negotiated encoding list and image rectangle types. Exclude authentication material from shared captures.
2. Establish the actual payload grammar from a complete original implementation or controlled encoder/decoder analysis. Obtain real full/partial update and quantization-table vectors, including every command type and cache/reset behavior. The missing command mapping must be resolved before 1011 is advertised.
3. Implement the codec with explicit payload-size, tile-count, cache-index and state-reset bounds. A frame from an older connection must not update a replacement connection. Each pass must preserve the image detail already reconstructed.
4. Replay real sanitized vectors and compare against the native result. On the live target, show a coarse pass followed by finer pixels for the same source image and region at constant geometry, including text and colour patterns. Verify final pixel fidelity, input during refinement, malformed input rejection and reconnect/display-switch recovery.

A synthetic decoder fixture, smaller framebuffer, ordinary successive changed-screen updates, lower colour depth or a codec registration number alone does not satisfy this gate.
