# Apple Curtain protocol candidate

This candidate adds an independently written, normal authenticated Apple RFB
console-visibility request. It does not change Remote Management settings,
authenticate differently, install a helper, or run a privileged server command.
The existing **Lock Remote Mac** shortcut and its local notice remain independent.

Protocol reference: [Rootshell VNC's AppleCurtainProtocol.swift](https://github.com/kitknox/rootshell-vnc/blob/3950a452ad6ed75f82177964418092d1fa88a929/Sources/RFBTransport/Session/AppleCurtainProtocol.swift),
[TransportSession.swift](https://github.com/kitknox/rootshell-vnc/blob/3950a452ad6ed75f82177964418092d1fa88a929/Sources/RFBTransport/Session/TransportSession.swift)
and [VNCSession.swift](https://github.com/kitknox/rootshell-vnc/blob/3950a452ad6ed75f82177964418092d1fa88a929/Sources/rootshellVNC/API/VNCSession.swift).

- Client type 12, padding 0, big-endian u16 visible (0 hides, 1 restores),
  big-endian u16 UTF-8 note length. This implementation always sends an empty note:
  hide `0c 00 00 00 00 00`; restore `0c 00 00 01 00 00`.
- DisplayInfo2 is framebuffer rectangle encoding `0x451`. Its version-5 body,
  after the u16 length prefix, carries the big-endian session flags at offset 14.
  Capability `0x02` must be set; login flags `0x08` and `0x10` must both be clear.
  `0x04` is on-console. Per-monitor flags are unrelated. Unknown versions and
  alternate byte orders are not inferred or enabled by this candidate.
- An initial non-console report never confirms our request. Confirmation requires
  a later accepted report after a request on the same authenticated connection,
  matching its visibility, capability and non-login flags. There is no documented
  transaction ID; fresh decoded metadata is a bounded state confirmation, not
  independent proof of physical privacy or causal execution.
- Ordinary switches have a 20-second budget. Closing a connection supersedes a
  pending hide with restore, first releases held input, keeps reads open for at
  most two seconds, then drains the existing final input/action transaction on
  that socket. Abrupt/immediate disconnect attempts an eligible empty restore in
  its final write but cannot wait for confirmation. Timeout, write failure,
  capability/login changes, or disconnect with unresolved restoration remain
  visibly unknown; a reconnect does not silently clear the recovery warning.
  Timers and completions retain both request and connection identity.

- Recovery obligations also live in process-local memory, independently of session
  windows. A dismissed or deallocated view model cannot discard the transport's
  recovery result. The library shows unresolved restoration for the original
  device/endpoint/authenticated account/SSH target; reopening that same target
  offers Restore rather than Hide. Edited or deleted targets keep their warning
  but cannot silently reconnect to another address/account. No credentials are
  stored or looked up by the recovery ledger, and nothing is written to disk.
- Each accepted hide starts a new obligation epoch. Restore binds the epochs
  already present before its bytes are sent, and only a fresh matching restore
  metadata confirmation can clear those epochs. Ready/initial visible reports,
  send processing, timeouts, stale client callbacks and older restore confirmations
  cannot clear later hides from another client. This guards local bookkeeping;
  server execution order and physical recovery still need real acceptance.
  Bookkeeping retains only the latest hide/restore scope per living source and
  the newest unresolved obligation per target/source. A source-lifetime revision
  cursor rejects old callbacks even after a closed ledger row is removed; no
  permanent request-history set is accumulated.
  The memory warning ends when the app process ends; it is not durable recovery
  evidence across relaunches.

## Real acceptance still required

No packet, reducer test, existing compile, old QA result or server metadata proves
that this feature works on macOS27. The existing client's Apple banner / RFB3.8
reply route differs from the reference client and needs actual compatibility
acceptance. Remote Management availability must come from current metadata, not a
device name, OS version, or ordinary Screen Sharing setting.

Verify the actual Mac's **physical screen is black while the session remains
unlocked and remotely controllable**, both monitor/all-monitor configurations,
fresh frames and input during the hidden period, restore with a fresh on-console
report and physical visibility, normal close, background expiration, timeout,
network loss and reconnect. A lock/login surface is not black-screen acceptance.
The reference sources and [Edovia's documentation](https://help.edovia.com/en-GB/screens-5/features/curtain-mode)
permit a locked or blank physical surface; pure black is therefore an open gate.
Server automatic restoration on disconnect is unproven. [Apple's documented
logout limitation](https://support.apple.com/en-us/101217) is another recovery
case; this candidate does not attempt logout to work around it.

## Reference notice

The wire contract was used as a factual reference; this candidate's encoder,
reducer and UI were written independently. The MIT notice below is retained as
provenance for the upstream implementation.

MIT License

Copyright (c) 2026 Rootshell LLC, Kit Knox

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
