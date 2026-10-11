# Industrial Fuzzing Infrastructure for Media Parsing Libraries

**Author & Lead Researcher:** Владимир Гареница (Vladimir Garenitsa) — **MalwareDante**
*Security researcher / vulnerability research engineer*
**October 2026 · v1.0**

> Independent vulnerability research: design, deployment and operation of an
> autonomous continuous-fuzzing platform covering three code lineages and
> three sanitizer classes on minimal hardware.

---

## About the author

Vulnerability research engineer focused on memory-corruption bug hunting in
media parsers and codec stacks. Practical areas:

- **Coverage-guided fuzzing**: libFuzzer, AFL++ (CmpLog/redqueen), custom
  mutators and structure-aware seed generation
- **Sanitizer engineering**: ASan / UBSan / MSan builds across full dependency
  trees, suppression tuning, UMR (use-of-uninitialized) analysis
- **Differential / vendor-divergence analysis**: upstream↔AOSP audit for
  n-day gaps; targeted harness development against shipped vendor code
- **Infrastructure**: systemd-scope orchestration, CPU-quota scheduling,
  watchdog self-healing, corpus distillation, automated crash triage with
  stack-signature deduplication

This repository is the complete artifact of that work — every harness,
build script and orchestration unit here was written from scratch for a
live, continuously-running campaign.

## Architecture (operational, running)

```
┌──────────────────────── VPS fleet ────────────────────────┐
│ fuzz-master  140% CPU │ 6 targets @ upstream git HEAD     │
│                       │ decode·box·meta·seq·roundtrip·de265│
│ fuzz-heif     40% CPU │ release set + AOSP forks          │
│                       │ heif×2·de265·flac·exif·sonivox    │
│ fuzz-afl      20% CPU │ AFL++ CmpLog, dictionary-driven   │
│ fuzz-msan     20% CPU │ guided MemorySanitizer (UMR hunt) │
│ fuzz-refresh.timer    │ daily git pull → incremental build│
│ fuzz-watchdog.timer   │ scope health → auto-restart       │
└────────────────────────────────────────────────────────────┘
```

- **11+ fuzz targets** across libheif (incl. sequences & encoder round-trip
  via x265), libde265, AOSP libFLAC 1.4.3, AOSP libexif 0.6.21, sonivox,
  jpeg/png/webp
- **Corpus engineering**: HEVC + HEIF conformance suites, upstream
  regression inputs, HEIF box-structure mutator (1500 variants), frame-splice
  seeds for codec realloc paths, daily `-merge=1` distillation
- **Triage pipeline**: live crash indexing (`crashes.tsv`), signature-based
  dedup buckets, per-target telemetry (`metrics.log`, 1-min resolution)

## Research methodology: hunt where the code is new

1. **Bleeding edge** — master-branch builds re-synced daily; fresh commits
   are fuzzed within hours of landing, before upstream CI/OSS-Fuzz coverage.
2. **Vendor divergence** — AOSP `external/` forks audited against upstream
   for missing security fixes: libexif 0.6.21 (2015 baseline + selective
   CVE backports), flac 1.4.3 vs 1.5.0 (residual-overflow & metadata
   bounds checks absent). Fuzzing runs on the *exact shipped code*.
3. **Weakly-covered surfaces** — encoder round-trip (write path),
   sequences/track API, AV1 decode (dav1d), MSan-only bug class
   (uninitialized reads) invisible to ASan/UBSan.

## Findings & honest assessment

| ID | Component | Class | Status |
|----|-----------|-------|--------|
| F-001 | libheif `bitstream.cc` memcpy-null | UB | fixed upstream — validated pipeline end-to-end |
| F-002 | libde265 `sei.cc` invalid enum load (attacker-controlled) | UB, **unfixed** in 1.1.2 & master | reproducible PoC, upstream-report ready |
| — | libexif `exif-utils.c` signed shift | benign UB | suppressed, documented |

**778 triaged artifacts · 97 unique signatures · all UB-class ·
zero memory-corruption to date.**

No RCE claims are made here on purpose: every artifact in this repo is
reproducible and the crash index is append-only. In vulnerability
research, an honest zero beats an invented hundred — the infrastructure,
the methodology and the verifiable artifacts are the deliverable.

## Repository map

| Path | Content |
|---|---|
| `TITLE.md` | Full scientific-style write-up (methodology, findings) |
| `MANIFEST.sha256` | Authorship manifest — SHA-256 of every file |
| `deploy/*_harness.*` | 12 fuzz-target harnesses (heif/de265/flac/exif/sonivox/jpeg/png/webp) |
| `deploy/*_upgrade.sh` | Idempotent build chains: ASan+UBSan, MSan, dav1d/x265 codecs, AOSP libs with Android-header stubs |
| `deploy/start_*.sh` | systemd-scope launchers with quota + safe-restart logic |
| `deploy/triage.sh`, `metrics.sh`, `watchdog.sh` | Autonomous ops: dedup, telemetry, self-healing |
| `deploy/git_refresh.sh` | Daily upstream re-sync loop |
| `deploy/box_mutator.py`, `deploy/dicts/` | Structure-aware mutator + 5 format dictionaries |

---

*(c) Vladimir Garenitsa / **MalwareDante**, 2026 — original work.
Third-party libraries remain property of their respective authors.*
