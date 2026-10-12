# Vladimir Garenitsa
### `MalwareDante` — vulnerability research engineer

Independent researcher. The work below ran privately for a while —
as of October 2026 it's public: platform, methodology, findings, writeups.

My ground rule: **no claim without an artifact.** Every bug has a reproducer,
every number is pullable from the repo, every report exists upstream.

---

### The platform — built solo, end to end

An autonomous fuzzing operation for media-parsing code, running unattended
on commodity hardware:

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

### What I hunt

- **AOSP vendor divergence** — `external/` forks where upstream fixes
  never landed (libexif frozen at 0.6.21/2015, FLAC 1.4.3 vs 1.5.0)
- **The write path** — decode→re-encode→serialize→reparse round-trips;
  the least-exercised code in mature media libraries
- **MSan-class bugs** — full dependency trees under `-fsanitize=memory`;
  the bugs most setups physically cannot see
- **Fresh upstream surface** — sequences/track API, new codec paths,
  code that is hours-to-days old

### Surfaces

Media parsers & codec stacks: HEIF/HEIC · H.265 · AV1 · FLAC · JPEG ·
PNG · WebP · EXIF · MIDI/synth.
Queued for divergence analysis: `external/libpng` · `external/jpeg-turbo` ·
`external/zlib`.

### Reported upstream

| Where | What | Status |
|---|---|---|
| [strukturag/libde265#546](https://github.com/strukturag/libde265/issues/546) | attacker-controlled invalid enum load in SEI `decoded_picture_hash` | open · live in 1.1.2 & master · PoC attached |

### Writing

- [Android's `external/` libraries: hunting n-days in code that upstream
  already fixed](https://dev.to/malwaredante/androids-external-libraries-hunting-n-days-in-code-that-upstream-already-fixed-159l) — dev.to ·
  [Medium](https://medium.com/@malwaredante/androids-external-libraries-hunting-n-days-in-code-that-upstream-already-fixed-243e1791a387)

### Stack

C/C++ · Python · Bash · libFuzzer · AFL++ (CmpLog) · SanitizerCoverage ·
ASan/UBSan/MSan · Linux/systemd/cgroups · CMake/Ninja/Meson ·
AOSP build internals · Git

---

*Open to vulnerability research / product security roles — remote.*
*Available for interviews and podcasts on fuzzing methodology, AOSP attack
surface, and research infrastructure on a budget — reach me via GitHub or
malwaredante@proton.me.*
