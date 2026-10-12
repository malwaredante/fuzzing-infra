# Vladimir Garenitsa
### `MalwareDante` · vulnerability research engineer · United States

I build and run offensive-research infrastructure: coverage-guided fuzzing,
sanitizer engineering, and vendor-divergence analysis of the code Android
actually ships.

---

### Running now — an autonomous fuzzing platform built solo, end to end

```
 targets            12 libFuzzer harnesses + AFL++ CmpLog + guided MSan
 sanitizers         ASan · UBSan · MSan — three bug classes in parallel
 operations         4 systemd scopes, CPU quotas, watchdog restarts
 refresh            daily git pull → rebuild → relaunch (bleeding edge)
 coverage           ~30k 8-bit counters on primary heif surfaces
```

→ **[fuzzing-infra](https://github.com/malwaredante/fuzzing-infra)** — full
source, harnesses, methodology, findings log.

### Research focus

- **AOSP vendor divergence** — fuzzing `external/` forks (libexif 0.6.21 →
  2015 baseline, FLAC 1.4.3 vs 1.5.0) where upstream fixes never landed
- **The write path** — decode→re-encode→serialize→reparse round-trips;
  the least-exercised code in mature media libraries
- **MSan hunting** — full dependency trees under `-fsanitize=memory`;
  the bug class most setups can't see
- **Corpus engineering** — conformance suites, structure-aware mutators,
  realloc-forcing seed generation

### Reported upstream

| Where | What | Status |
|---|---|---|
| [strukturag/libde265#546](https://github.com/strukturag/libde265/issues/546) | attacker-controlled invalid enum load in SEI `decoded_picture_hash` | open · live in 1.1.2 & master · PoC attached |

### Writing

- [Android's `external/` libraries: hunting n-days in code that upstream
  already fixed](https://medium.com/@malwaredante/androids-external-libraries-hunting-n-days-in-code-that-upstream-already-fixed-243e1791a387) — Medium
- Same writeup in Russian on [Habr](https://habr.com/ru/sandbox/308772/)
  (in moderation)

### Stack

C/C++ · Python · Bash · libFuzzer · AFL++ (CmpLog) · SanitizerCoverage ·
ASan/UBSan/MSan · Linux/systemd/cgroups · CMake/Ninja/Meson ·
AOSP build internals · Git

---

*Open to vulnerability research / product security roles — remote or US.*
*Every artifact in my repos reproduces; every claim is verifiable.*
