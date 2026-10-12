# Blog post draft — post on dev.to / Habr / Medium to get indexed fast

## Title
**"Android's `external/` libraries: hunting n-days in code that upstream already fixed"**

*(Alternative: "I built a fuzzing platform on a 2-core VPS. Here's what actually works for solo vuln research")*

## Draft text (v2 — human voice)

> By Vladimir Garenitsa / MalwareDante

I'm not a security researcher by title. This started as a spare-time project on
the cheapest VPS I could find — 2 cores, a few gigs of RAM. I mostly wanted to
know whether one person can still find bugs in code that Google's OSS-Fuzz
cluster has been chewing on for years, 24/7, with thousands of cores.

Short answer: not by competing with it. If you run the same fuzzers on the same
code, you lose by definition. So after the first weeks produced nothing but
timeout noise, I stopped and asked a different question — what does nobody
fuzz at all?

Turns out, quite a lot.

**Vendor forks.** AOSP doesn't link upstream libraries; it ships its own copies
under `external/`, and some of them are ancient. `external/libexif` is 0.6.21,
last upgraded in June 2015. Google cherry-picks the CVE fixes, sure — but
eleven years of general hardening and parser rewrites never made it in.
`external/flac` is 1.4.3 while upstream is at 1.5.0, and the diff between them
includes real security work: overflow checks in residual decoding, metadata
over-read guards. So I fuzz the shipped code, not upstream. If something falls
out of that, it's not a hypothetical bug — it's an n-day on every Android
device that ever parses the format.

**The write path.** Almost every media fuzzer on the planet does the same
thing: feed garbage into a decoder. I spent some effort on the opposite —
decode a HEIF file, re-encode the pixels through x265, serialize the boxes
back out, reparse the result, decode again. That round-trip exercises box
writers, CRC builders, metadata serialization — code that sees a tenth of the
coverage decoders get. On a mature library the write path is usually the least
exercised part of the tree, which is exactly where you want to be.

**MemorySanitizer.** Everyone runs ASan+UBSan because they're easy. MSan is
not easy — you have to rebuild your whole dependency tree under
`-fsanitize=memory`, and half the time it doesn't work until you fix some
unrelated init bug in a dependency. Which is precisely why almost nobody runs
it, and why uninitialized-memory bugs sit there unclaimed. It took me two days
of swearing at build scripts to get an MSan scope running. Worth it.

A few words on the platform itself, since that's honestly the thing I'm
proudest of. It's 12 libFuzzer targets plus an AFL++ CmpLog instance plus the
MSan scope, all packed into `systemd-run` cgroups with CPU quotas so they can
share two cores without starving each other. A systemd timer pulls upstream
master every day, does an incremental rebuild, and relaunches — so commits
that landed in libheif this morning get fuzzed tonight, long before OSS-Fuzz's
schedule touches them. Crash triage is automatic (stack-signature dedup into
an append-only index), telemetry runs every minute, and a watchdog restarts
whatever dies. I check in twice a day over coffee. The fleet runs itself.

Now the part most blog posts would inflate, so I'll just state it plainly.
778 triaged artifacts so far, 97 unique signatures — all of them UB-class
(undefined behavior, invalid enums, bad shifts). Zero memory corruption *yet*.
One real bug reported upstream: **[libde265#546](https://github.com/strukturag/libde265/issues/546)** —
an attacker-controlled byte in an SEI `decoded_picture_hash` message that
loads an invalid enum value, reproducible on release 1.1.2 and current master.
Not a headline, but it's a documented, unfixed issue with a PoC attached, and
it's mine.

I have no idea when the first real crash comes. That's the honest part of
fuzzing nobody puts in writeups — you can do everything right and still wait
weeks. But the setup is built so that when it does come, I'll be the one who
finds it: because I was fuzzing the fork nobody else looks at, on the path
nobody exercises, under the sanitizer nobody bothers to build.

**Source, harnesses and methodology:**
[github.com/malwaredante/fuzzing-infra](https://github.com/malwaredante/fuzzing-infra)

*Vladimir Garenitsa / MalwareDante — independent vulnerability research.*
