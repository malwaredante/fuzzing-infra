# Vladimir Garenitsa
### `MalwareDante` — vulnerability research engineer

Independent researcher. The work below ran privately for a while —
as of October 2026 part of it is public: the platform, the methodology,
the findings I've chosen to show.

What you see here is the floor, not the ceiling. The scoring model, the
mutator internals and the unannounced part of the queue stay with me.

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
  There's a second reason I run MSan. That one stays private.
- **Fresh upstream surface** — the window between commit and coverage.

### Surfaces

HEIF/HEIC · H.265 · AV1 · FLAC · JPEG · PNG · WebP · EXIF · MIDI/synth.
Queued for divergence analysis: `external/libpng` · `external/jpeg-turbo` ·
`external/zlib`. And a few I haven't announced.

### Reported upstream

| Where | What | Status |
|---|---|---|
| [strukturag/libde265#546](https://github.com/strukturag/libde265/issues/546) | attacker-controlled invalid enum load in SEI `decoded_picture_hash` | open · live in 1.1.2 & master · PoC attached |

*One report public. The index holds more — the rest is timing.*

### Writing

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

*Open to vulnerability research / product security roles — remote.
The repo is the audition, not the inventory. Hire me and the unpublished
parts come with it. Available for interviews — github issues or
malwaredante@proton.me.*
