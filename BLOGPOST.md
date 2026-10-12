# Blog post draft — post on dev.to / Habr / Medium to get indexed fast

## Title
**"Android's `external/` libraries: hunting n-days in code that upstream already fixed"**

*(Alternative: "I built a fuzzing platform on a 2-core VPS. Here's what actually works for solo vuln research")*

## Draft text

> By Vladimir Garenitsa / MalwareDante

Everyone hunting memory-corruption bugs in open-source media libraries
competes with Google's OSS-Fuzz — a cluster running the same fuzzers on the
same code, 24/7. On a 2-core VPS you lose that race by definition.

So I stopped racing and changed the question: **not "how do I fuzz more", but
"what does nobody fuzz?"**

### Three surfaces that aren't crowded

**1. Vendor forks, not upstream.**
AOSP ships vendored copies of parsing libraries under `external/` — and they
lag upstream, sometimes catastrophically:

- `external/libexif` is **0.6.21 — last upgraded June 2015**. Eleven years of
  upstream fixes never merged (though Google cherry-picks CVE fixes — the
  hot paths are patched; the rest is a gray zone).
- `external/flac` is **1.4.3 vs upstream 1.5.0**, which includes real
  parser-hardening: residual-in-32-bit-overflow checks, metadata
  over-read/allocation guards. Those checks do not exist in shipped code.

If you fuzz the *shipped* version instead of upstream, you hunt in
pre-mapped territory — and a hit is an **n-day on every Android device**.

**2. The write path.**
Nearly every media-fuzzer feeds files into decoders. Almost nobody fuzzes
**encode→serialize→reparse** loops — yet that path touches different
machinery (box writers, CRC builders, metadata serialization). I built a
round-trip harness (decode HEIF → re-encode via x265 → write → reparse →
decode). On a mature decoder, the write path is the least-exercised code in
the tree.

**3. Sanitizer classes people skip.**
Everyone runs ASan+UBSan. Fewer run **MemorySanitizer** — it requires
building the entire dependency tree under `-fsanitize=memory`, which is
tedious, so coverage stays thin. UMR-class bugs hide precisely there.

### The platform

- 12 libFuzzer targets + AFL++ CmpLog + guided MSan, in `systemd-run` scopes
  with CPU quotas (a 2-core VPS shares it fine)
- Daily `git pull → incremental rebuild → relaunch` via systemd timer —
  "bleeding edge" commits get fuzzed hours after landing
- Automated triage: stack-signature dedup, append-only crash index, 1-minute
  telemetry, watchdog restarts. I check in twice a day; the fleet runs itself.

### Honest results (as of writing)

778 triaged artifacts, 97 signatures — all UB-class, zero memory corruption
*so far*. One real unfixed bug reported upstream:
**[libde265#546](https://github.com/strukturag/libde265/issues/546)** —
attacker-controlled invalid enum load in SEI `decoded_picture_hash`, live in
release 1.1.2 and git master.

The honest pitch: solo fuzzing won't out-muscle OSS-Fuzz, but it can
out-*position* it. The edge isn't compute — it's surface selection.

**Source, harnesses and methodology:**
[github.com/malwaredante/fuzzing-infra](https://github.com/malwaredante/fuzzing-infra)

*Vladimir Garenitsa / MalwareDante — independent vulnerability research.*
