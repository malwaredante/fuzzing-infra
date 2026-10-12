# Vladimir Garenitsa
### `MalwareDante` — vulnerability research engineer

I don't publish origin stories; I publish results. What ran before this page
existed was mine to keep — what appears here, I've decided is ready to be
seen. October 2026: the platform, the methodology, and the findings worth
showing.

There's more behind it — there usually is, when the work is real. It will
surface in its own time, or in the right conversation.

**Rule:** no claim without an artifact. Everything stated reproduces.

---

### The platform — built solo, end to end

```
 targets            12 libFuzzer harnesses + AFL++ CmpLog + guided MSan
 sanitizers         ASan · UBSan · MSan — three bug classes in parallel
 operations         4 systemd scopes, CPU quotas, watchdog restarts
 refresh            daily git pull → rebuild → relaunch (bleeding edge)
 coverage           ~30k 8-bit counters on primary heif surfaces
 triage             stack-signature dedup, append-only crash index
```

→ **[fuzzing-infra](https://github.com/malwaredante/fuzzing-infra)** — full
source, harnesses, methodology, findings log.

### What I hunt — the public version

- **AOSP vendor divergence** — `external/` forks where upstream fixes
  never landed (libexif frozen at 0.6.21/2015, FLAC 1.4.3 vs 1.5.0).
  I've measured more libraries than I've named.
- **The write path** — decode→re-encode→serialize→reparse round-trips;
  the least-exercised code in mature media libraries.
- **MSan-class bugs** — the bug class most setups physically cannot see.
  There is a second reason I run MSan; it stays mine for now.
- **Fresh upstream surface** — the window between commit and coverage.

### Surfaces

HEIF/HEIC · H.265 · AV1 · FLAC · JPEG · PNG · WebP · EXIF · MIDI/synth.
Queued for divergence analysis: `external/libpng` · `external/jpeg-turbo` ·
`external/zlib`. Among others.

### Reported upstream

| Where | What | Status |
|---|---|---|
| [strukturag/libde265#546](https://github.com/strukturag/libde265/issues/546) | attacker-controlled invalid enum load in SEI `decoded_picture_hash` | open · live in 1.1.2 & master · PoC attached |

*One report made public so far. The index holds more — timing, mostly.*

### Writing & interviews

- [Android's `external/` libraries: hunting n-days in code that upstream
  already fixed](https://dev.to/malwaredante/androids-external-libraries-hunting-n-days-in-code-that-upstream-already-fixed-159l) — dev.to ·
  [Medium](https://medium.com/@malwaredante/androids-external-libraries-hunting-n-days-in-code-that-upstream-already-fixed-243e1791a387)
- [Interview Q&A](https://github.com/malwaredante/fuzzing-infra/blob/main/INTERVIEW_QA.md) ·
  [RU version](https://github.com/malwaredante/fuzzing-infra/blob/main/INTERVIEW_QA_ru.md)

### Stack

C/C++ · Python · Bash · libFuzzer · AFL++ (CmpLog) · SanitizerCoverage ·
ASan/UBSan/MSan · Linux/systemd/cgroups · CMake/Ninja/Meson ·
AOSP build internals · Git

---

*Open to vulnerability research / product security — remote.
If something here raises a question, the honest version of the answer is a
conversation: malwaredante@proton.me, or a GitHub issue. I answer serious
inquiries personally.*
