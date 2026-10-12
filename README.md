# Continuous Vulnerability Research Platform for Media Parsing Libraries

**Vladimir Garenitsa (Владимир Гареница) — MalwareDante**
Independent vulnerability research · October 2026

A production-grade, fully autonomous fuzzing operation built end-to-end by a
single engineer: 12 instrumented targets, 3 sanitizer classes, 4 orchestrated
compute scopes, daily upstream re-sync — running unattended on commodity
VPS hardware.

**The story behind it:**
[Android's external/ libraries: hunting n-days in code that upstream already
fixed](https://medium.com/@malwaredante/androids-external-libraries-hunting-n-days-in-code-that-upstream-already-fixed-243e1791a387)
(Medium · [Habr RU](https://habr.com/ru/sandbox/308772/))

```
Coverage on instrumented surfaces (8-bit counters, live):
  heif_meta  ████████████████████ 31 351
  heif_decode███████████████████  29 049
  heif_seq   ████████████████     24 543
  sonivox    ████████             1 170   (first hour)
  flac       ██████                 885   (AOSP 1.4.3 — shipped decoder)
```

---

## What this is

Not a script. A **persistent offensive-research platform** with the same
discipline industrial fuzzing teams apply internally:

- **Three build lineages, three sanitizer classes**
  Release · git-master ("bleeding edge", rebuilt daily by `fuzz-refresh.timer`)
  · AOSP vendor forks — each under ASan+UBSan, plus a dedicated
  MemorySanitizer scope hunting use-of-uninitialized-value, the bug class
  invisible to ASan.

- **Autonomous operations**
  systemd-scope quotas (140/40/20/20 %), watchdog restart within ~5 min,
  corpus distillation with atomic swap, signature-dedup triage writing an
  append-only crash index, 1-minute telemetry. The fleet survives SSH drops,
  fuzzer exits and scope failures without human input.

- **Deliberate target selection**
  Surfaces chosen by exposure math, not fashion: sequences/track API (fresh
  upstream code), encoder round-trip (the write path almost nobody fuzzes),
  AV1 decode via dav1d, AOSP forks measured for upstream lag — libexif
  0.6.21 (2015 baseline), flac 1.4.3 vs 1.5.0 security deltas.

## Methodology

**Hunt where code is new or badly integrated.**

1. *Bleeding edge* — master HEAD rebuilt and refuzzed daily; window between
   upstream commit and OSS-Fuzz coverage is where solo research still wins.
2. *Vendor divergence* — fuzz the exact bytes Android ships, not the
   sanitized upstream. Missing backports = pre-mapped attack surface.
3. *Corpus engineering* — HEVC/HEIF conformance suites, upstream regression
   inputs, a structure-aware HEIF box mutator, frame-splice seeds forcing
   codec realloc paths (FLAC `allocate_output_` channel/bps transitions).
4. *Verification culture* — every artifact deduped by stack signature;
   timeouts replayed separately; UB findings triaged by reachability
   (enum-load, null-deref, signed-shift) and MSan-confirmed where relevant.

## Documented findings

| ID | Component | Root cause | Status |
|----|-----------|------------|--------|
| F-001 | libheif `bitstream.cc:115` | memcpy(NULL,0) via `Box_mini→Box_av1C` empty OBU vector | fixed upstream — full pipeline validation |
| F-002 | libde265 `sei.cc:45,70,78` | attacker byte → invalid `hash_type` enum, **unfixed in 1.1.2 and git master** | **reported upstream:** [strukturag/libde265#546](https://github.com/strukturag/libde265/issues/546) |
| — | libexif `exif-utils.c:137` | signed 24-bit shift on tainted byte | suppressed after classification |

**778 deduplicated artifacts · 97 stack signatures · 0 false-positive ASan
events.** The corpus index is append-only and every entry reproduces.

## Engineering inventory

| Layer | Implementation |
|---|---|
| Harnesses (12) | `heif_decode/box/meta/seq/roundtrip`, `libde265`, `flac`, `exif`, `sonivox`, `jpeg`, `png`, `webp` — hand-written, API-accurate |
| Build chains | idempotent phase-marked scripts: `industrial/master/codec/msan/flac/aosp_media` — AOSP libs compiled standalone via Android-header stub layer (`log/log.h`, `cutils`, `MediaPlayerInterface`, `errorWriteLog`) |
| Orchestration | `systemd-run` scopes + quota scheduling, `wait_scope_dead` race-free restarts, watchdog timer, daily `git pull → rebuild → relaunch` |
| Analysis | `triage.sh` (sig extraction + dedup buckets), `metrics.sh`, `hang_triage.sh`, `box_mutator.py`, 5 format dictionaries |
| Seed science | conformance corpora, regression inputs, structure mutators, cross-parameter frame splices |

## Repository

- `TITLE.md` — formal write-up
- `MANIFEST.sha256` — authorship manifest (SHA-256 of all sources)
- `BLOGPOST.md` — the writeup, published on
  [Medium](https://medium.com/@malwaredante/androids-external-libraries-hunting-n-days-in-code-that-upstream-already-fixed-243e1791a387)
  and [Habr](https://habr.com/ru/sandbox/308772/)
- `deploy/` — complete deployment tree; a second node stands up in minutes

---

*© 2026 Vladimir Garenitsa / MalwareDante. All orchestration code, harnesses
and methodology are original work. Third-party libraries belong to their
authors.*
