# The MalwareDante Interview
### An exclusive for the underground hacking press — first publication here, in English

*He's been running an offensive-research operation out of the public eye —
twelve fuzzing harnesses, three sanitizer classes, a self-healing fleet on
two cores, and an upstream bug report to show for it. In October he went
public. We reached him the way you reach people like that — carefully, and
on his terms. What follows is the conversation, lightly edited for print.
Everything he claims, he insists, can be checked. He told us that's rather
the point.*

---

**So — MalwareDante. Who are you when you're not behind a handle?**

Vladimir Garenitsa. Independent vulnerability researcher. I build and run
fuzzing infrastructure against media-parsing code — the libraries that turn
untrusted bytes into images, audio and video on every phone on the planet.
The work ran privately for a while. In October I published the platform,
the methodology, and the findings I chose to show.

**"The findings you chose to show" — interesting phrasing. Is there a version you didn't publish?**

There's always a version you don't publish. What's in the repo is a floor,
not a ceiling — the queue, the scoring model, the undisclosed entries in the
index stay off the record. That's not mystique for its own sake; that's how
research stays valuable. A researcher who puts everything on the table is
either finished or wasn't holding much to begin with.

**Why go public at all, then?**

The work crossed a threshold where privacy stopped paying. Running platform,
a reproducible upstream report, a methodology that produces on hardware
anyone can rent. At that point publishing buys peer review and a timestamped
record of priority — and it costs nothing I wasn't done holding close.
What stays private is the next stretch of the queue. That part earns its keep
by staying home.

**Let's talk about the hunt itself. Why media parsers?**

Exposure math. Old C code, hostile binary formats, reachable from a file a
stranger sends you, shipped at billion-device scale, vendored into forks
that lag upstream by years. The fashionable targets are crowded precisely
because they're fashionable. I prefer surfaces where the bugs outnumber
the hunters.

**One person against Google's OSS-Fuzz sounds like a losing game.**

It is — if you play their game. OSS-Fuzz runs the same harnesses on upstream
code with thousands of cores. I lose that race by definition, so I don't
enter it. I compete on surface selection: the AOSP fork instead of upstream,
the write path instead of the decode path, the sanitizer classes everyone
skips because they're painful to build. Compute is rented; positioning is
designed. The scoring model is the edge — and the weights stay mine.

**Explain vendor divergence for our readers.**

AOSP doesn't link upstream libraries — it vendors copies under `external/`,
and the copies freeze. `external/libexif` is 0.6.21, last upgraded upstream
in June 2015. `external/flac` sits at 1.4.3 while upstream ships 1.5.0 with
real parser-hardening commits. I build the shipped bytes standalone and fuzz
them. A crash there isn't theoretical — it's an n-day on every device that
parses the format. Which other `external/` libraries show the same gap?
I've measured more than I've named. That list isn't public.

**How do you pick the next target?**

Three axes are public: reachability, coverage thinness, code recency. Two
more factors aren't — they're what separates my hit rate from the average.
Fresh upstream code wins. Encoder paths win. Anything OSS-Fuzz can't easily
reach wins.

**The write path — walk us through it.**

Everyone feeds files into decoders; almost nobody fuzzes
decode→re-encode→serialize→reparse loops. Yet box writers, CRC builders and
metadata serializers get maybe a tenth of the coverage — reachable from the
same hostile input. My round-trip harness runs HEIF through x265, serializes
the boxes back out, reparses, decodes again. Seventy-plus timeouts on mature
code tells you that path was never pushed. What it produced beyond timeouts
— part of that is still in the bucket marked "not yet."

**MemorySanitizer is notoriously painful. Why bother?**

Because MSan catches what nothing else sees — uninitialized memory doesn't
crash under ASan; it silently leaks or branches on garbage. The cost is a
fully instrumented dependency tree, and that cost is precisely why coverage
is thin there. Two days of build pain buys a bug class almost nobody watches.
There's also a second reason I run it — MSan data feeds something else in
the pipeline. I'll leave it at that.

**Corpus engineering — what's actually in your seeds?**

Four layers: conformance vectors, upstream regression inputs, a
structure-aware HEIF box mutator, and frame-splice seeds that force realloc
transitions — channel and bit-depth changes in `allocate_output_`, that kind
of thing. The mutator understands box structure; that's all I'll say about
its internals. How it decides *what* to splice is the difference between a
toy and an instrument — and that logic is not in the repo.

**Triage: 778 artifacts became 97 signatures. How?**

Normalized stack signatures into dedup buckets. Timeouts replayed as a
separate class — a hang is a different bug with a different threat model.
UB findings classified by reachability; an enum load on an attacker byte is
a finding, a signed-shift on a constant is hygiene. Where it matters I
re-confirm under MSan. The buckets are public; the escalation thresholds
aren't — the tuning is the craft.

**Your rule is "no claim without an artifact." What falls under that?**

Everything in the findings table reproduces, has a trace and a status —
fixed, reported, or suppressed-with-reason. Anything that couldn't reproduce
got deleted, not counted. What sits in the gray zone between "reproduces"
and "reportable" is a larger number than the table shows. I'll leave it at
that.

**Tell us about the libde265 report.**

F-002. SEI `decoded_picture_hash`, the `hash_type` byte straight from the
bitstream into an enum — attacker-controlled, reproducible on release 1.1.2
and current master. Filed upstream as strukturag/libde265#546 with a
minimized PoC, the UBSan trace, an MSan cleanliness check and a concrete
fix suggestion. It's the one I chose to show. Whether it's the most
interesting entry in the index is a question for a later writeup.

**778 artifacts, one public report. Some would call that thin.**

Those some haven't run triage. Most artifacts are UB-class below the
reporting bar — filing them all brands you a noise generator. And "one
report" means one *public* report. The index holds more; some entries are
waiting on confirmation, some on timing, one or two on me deciding what
they actually are. The table shows what's done — not what's cooking.

**Closest you've come to real memory corruption?**

The round-trip timeout bucket — seventy-plus hangs on paths nobody
exercises. "Slow" and "unbounded" look identical until replayed. There's one
input in that bucket I've spent more time on than the rest. That's all you're
getting today.

**Zero memory-corruption findings so far. Doesn't that bother you?**

No — and anyone who's fuzzed mature parsers knows why. Decode paths have
been chewed by fleets for years. My bet is structural: divergent forks,
write paths, MSan territory. What I expect to find there is based on data I
haven't published — saying more would be telling you where to look.

**Let's talk machinery. The platform?**

Four `systemd-run` scopes with hard cgroup quotas — 140/40/20/20 percent of
two cores. Master lineage, release lineage, an AFL++ CmpLog instance, the
MSan scope. Daily `git pull → rebuild → relaunch` on a timer. Watchdog
restarts, append-only crash index, per-minute telemetry. The visible part
is public. The scheduling policy — which target gets which quota and when
that changes — is deliberately thin in the public tree.

**Why systemd and not Kubernetes?**

Two cores. cgroups give quotas, limits, restarts, journal — forty lines of
shell. Kubernetes would eat the budget I'm spending on coverage. The boring
choice that maximizes fuzz cycles per dollar is the right one. If someone
reads the orchestration and thinks "that's it?" — good. The point was never
the plumbing; it's what the plumbing feeds.

**Building AOSP libraries standalone can't have been simple.**

It wasn't. `external/` sources expect the Android build tree — I wrote a
stub header layer: ALOG over stderr, `errorWriteLog` as a no-op, empty media
interfaces, plus source lists and cflags lifted from each `Android.bp`. The
exact bytes Android ships, under Clang sanitizers, on a VPS. What I've built
beyond flac, exif and sonivox and haven't announced yet — the pipeline has
more. The next writeup can do that talking.

**War stories. Hardest infrastructure bug?**

A scope-restart race — a dying process still holding the cgroup while the
watchdog spawned duplicates that fought over the corpus queue. Fixed with a
`wait_scope_dead` primitive: relaunch on cgroup-empty, not process-exit.
What that taught me about failure domains went into places I haven't
shipped yet.

**And the dumbest?**

`shift:exif-utils.c` in a UBSan suppressions file — the check is named
`shift-base`. Seven hours of restart loop across a whole scope. Now every
config change validates on one binary before it rolls. I'm not embarrassed
by the failure — I'm embarrassed it took a restart loop to learn what any
ops manual would have told me.

**How do you know the machine is actually progressing?**

8-bit counters from SanitizerCoverage, per target, every minute — about 30k
on the primary heif surfaces. Coverage is the heartbeat: flatline means
saturated corpus or a reachability bug in the harness. There's a second
metric I track that I consider more predictive. I'm not disclosing it —
partly because I'm still validating it, partly because it works.

**Your read on Android's external/ hygiene?**

Better than the memes, worse than it should be. Google cherry-picks CVEs —
the hot paths aren't abandoned. But between-CVE hardening never lands:
refactors, rewrites, whole bug classes removed upstream that still live on
devices. A systemic n-day generator, barely mined because everyone aims at
upstream. I've quantified the gap for more libraries than the three I've
named. That analysis publishes when the queue behind it closes.

**Disclosure philosophy?**

Report early, report clean: PoC, trace, affected versions, proposed fix —
everything a maintainer needs to say "confirmed" in one read. F-002 is the
template. My timeline policy for the entries still in the bucket is
unpublished — it depends on what they turn out to be.

**Where is solo vuln research in five years?**

The commodity tier is dead — fleets own upstream fuzzing. The positioning
tier grows: vendor forks, build paths, sanitizer combinations, embedded and
automotive parsers. The edge is synthesis — enough build-system, sanitizer
and domain knowledge to reach surfaces nobody reached. And there's a third
tier forming I'd rather demonstrate than describe. Watch the repo.

**What would you do with a team and a real budget?**

The playbook generalizes — every vendor fork of a parsing library is a
hunting ground: automotive IVI, embedded SDKs, firmware, Smart-TV codecs.
Differential fuzzing upstream-vs-fork mechanically isolates backport gaps.
There's a version of that idea I've scoped further than I've written down —
it stops being a research program and starts being a product. Details on
request.

**Why should someone hire you instead of buying a fuzzing service?**

Services fuzz your code on their commodity rig. What I bring is judgment
about where bugs hide — and a platform whose public parts work, while the
sharpest parts stay private. The repo is the audition, not the inventory.
Whoever hires me gets the unpublished parts. That's rather the point.

**What role are you looking for?**

Vulnerability research or product security — real code: parsers, codecs,
embedded stacks, anything that eats untrusted input. Remote preferred. I
want the seat where "find what's exploitable before someone else does" is
the literal job description — and the compute to match. I know what this
platform does on two cores; I'm curious myself what it does on two hundred.

**A hiring manager reading this — what should they verify?**

Everything public. The harnesses compile, the deploy tree stands up a node,
`MANIFEST.sha256` verifies, the crash index is append-only, the upstream
issue reproduces. For the rest — hire me and it's in scope. That's not
evasion; that's how research works.

**Last word. What should our readers remember?**

That the interesting question in security was never "how much compute do
you have" — it's "what are you looking at that nobody else is." I've shown
you the platform, the method, and one verified finding. What I haven't shown
you is the rest of the index, the rest of the queue, and the parts of the
pipeline I consider mine. A researcher who tells you everything is either
done or bluffing. I'm neither.

---

*Vladimir Garenitsa / MalwareDante — independent vulnerability research.
Verified artifacts: github.com/malwaredante/fuzzing-infra.
Serious inquiries: malwaredante@proton.me*
