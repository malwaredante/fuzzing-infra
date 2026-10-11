# Industrial-Grade Continuous Fuzzing Infrastructure for Media Parsing Libraries:
## Methodology, Multi-Sanitizer Architecture, and Vendor-Divergence Analysis

**Author:** Владимир Гареница (Vladimir Garenitsa)
**Handle:** MalwareDante
**Date:** October 2026
**Version:** 1.0

---

## Abstract

This work presents the design and operation of an autonomous, self-healing
fuzzing environment deployed on commodity VPS hardware, targeting media
parsing libraries across three distinct code lineages: upstream release,
upstream git-master ("bleeding edge"), and AOSP vendor forks. The system
combines coverage-guided mutation (libFuzzer, AFL++ CmpLog) with three
complementary sanitizer classes — AddressSanitizer, UndefinedBehaviorSanitizer
and MemorySanitizer — under a systemd-scope orchestration layer providing
resource quotas, watchdog-based recovery, daily upstream re-sync, corpus
distillation, and automated crash triage with stack-signature deduplication.

A key methodological contribution is the **vendor-divergence hunting**
strategy: rather than competing with industrial fuzzing clusters on mature
upstream code, the environment targets AOSP `external/` forks that lag
upstream security fixes (libexif: 11 years; flac 1.4.3 vs 1.5.0), plus
weakly-covered integration surfaces (encoder round-trip, sequences API,
codec-backed decode paths via dav1d/x265).

## Contents of this archive

| Category | Files |
|---|---|
| Fuzz targets | `heif_decode/box/meta/seq/roundtrip`, `libde265`, `flac`, `exif`, `sonivox`, `jpeg`, `png`, `webp` |
| Build automation | `setup_fuzz_env.sh`, `industrial_upgrade.sh`, `master_upgrade.sh`, `codec_upgrade.sh`, `msan_upgrade.sh`, `flac_upgrade.sh`, `aosp_media_upgrade.sh` |
| Orchestration | `start_*.sh` (systemd-run scopes), `watchdog.sh`, `git_refresh.sh`, `distill_corpus.sh`, `sync_corpus.sh` |
| Analysis | `triage.sh` (signature dedup), `metrics.sh`, `hang_triage.sh`, `box_mutator.py`, `status.sh`, dicts |

## Findings (as of 2026-10-12)

- **F-001** — libheif `bitstream.cc` memcpy-null UB (fixed upstream; validated pipeline)
- **F-002** — libde265 `sei.cc` attacker-controlled invalid enum load
  (unfixed in release 1.1.2 and git master; valid upstream report)
- 778 triaged artifacts: 97 unique signatures, all UB-class; zero
  memory-corruption findings to date — consistent with the maturity of
  OSS-Fuzz-covered surfaces and motivating the vendor-divergence pivot.

## Author's note

All harnesses, orchestration scripts, the vendor-divergence methodology and
this document are original work by the author, assisted by AI tooling
(Devin/Cognition). Third-party code (libheif, libde265, FLAC, libexif,
sonivox, AFL++) remains property of its respective authors/licenses.

---
**MalwareDante** — 2026
