# Vladimir Garenitsa
### `MalwareDante` — vulnerability research engineer

I don't do origin stories in READMEs. What I did before going public is a
conversation, not a landing page — ask me directly and you'll get a straight
answer. What I'll say here: the work below ran privately, on my own
infrastructure, on my own time — and as of October 2026, part of it is
public. The platform, the methodology, the findings I've chosen to show.

What you see is the floor, not the ceiling. The scoring model, the mutator
internals, and the unannounced part of the queue stay with me — that's not
mystique, that's pricing.

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

*Open to vulnerability research / product security roles — remote.
This page is the audition, not the inventory. The unpublished parts —
the queue, the thresholds, the second metric — come with the hire, not
with the browse. For interviews, collaborations, or the direct version of
"what else do you have": malwaredante@proton.me or a GitHub issue.*
