# Vladimir Garenitsa
### `MalwareDante` — vulnerability research

Independent. Public since October 2026. Prior history: not for a README.

This page carries what I've decided to release. The rest — the queue, the
scoring model, the undisclosed entries in the index — remains off the record.

**Rule:** no claim without an artifact. Everything stated reproduces.

---

## Operations

```
 fleet        12 libFuzzer harnesses · AFL++ CmpLog · guided MSan scope
 lineages     release · git-master (daily rebuild) · AOSP vendor forks
 sanitizers   ASan+UBSan everywhere · -fsanitize=memory on a full
              instrumented dependency tree
 scheduling   systemd scopes, cgroup CPU quotas 140/40/20/20, two cores
 refresh      timer-driven git pull → incremental build → relaunch
 triage       normalized stack signatures → dedup buckets →
              append-only index · timeouts replayed as a separate class
 telemetry    per-target 8-bit counters, 60s cadence
 uptime       self-healing; survives SSH drops, fuzzer exits, scope death
```

→ **[fuzzing-infra](https://github.com/malwaredante/fuzzing-infra)** —
source, harnesses, methodology.

## Technique

- **AOSP standalone builds** — `external/` forks compiled off-tree via a
  stub layer for the Android build environment (`log/log.h`, `cutils`,
  media interfaces, `errorWriteLog`); source lists and cflags lifted from
  `Android.bp`. The exact bytes devices ship — under sanitizers.
- **Divergence measurement** — shipped-vs-upstream diffs across `external/`:
  libexif pinned at 0.6.21 (2015 baseline), FLAC 1.4.3 vs 1.5.0
  parser-hardening delta. Measured on more libraries than listed here.
- **Write-path fuzzing** — HEIF decode → x265 re-encode → box
  serialization → reparse → decode. The least-exercised machinery in
  mature libraries.
- **Corpus engineering** — conformance vectors, upstream regression
  inputs, a structure-aware HEIF box mutator, frame-splice seeds that
  force `allocate_output_` realloc transitions in the FLAC decoder.
- **Signature-dedup triage** — 778 artifacts → 97 signatures; findings
  classified by reachability and re-confirmed under MSan where it matters.

## Reported upstream

| Where | What | Status |
|---|---|---|
| [strukturag/libde265#546](https://github.com/strukturag/libde265/issues/546) | attacker-controlled invalid enum load, SEI `decoded_picture_hash` | open · live in 1.1.2 & master · PoC attached |

*Public count: one. Index count: higher. Timing is a choice.*

## Writing & interviews

- [Android's `external/` libraries: hunting n-days in code that upstream
  already fixed](https://dev.to/malwaredante/androids-external-libraries-hunting-n-days-in-code-that-upstream-already-fixed-159l) — dev.to ·
  [Medium](https://medium.com/@malwaredante/androids-external-libraries-hunting-n-days-in-code-that-upstream-already-fixed-243e1791a387)
- [Interview Q&A](https://github.com/malwaredante/fuzzing-infra/blob/main/INTERVIEW_QA.md) ·
  [RU](https://github.com/malwaredante/fuzzing-infra/blob/main/INTERVIEW_QA_ru.md)

---

*Vulnerability research / product security — remote.
Serious inquiries get personal answers: malwaredante@proton.me.*
