# Interview Q&A — Vladimir Garenitsa / MalwareDante

*The public version. Everything below is what I choose to show — the scoring
model, the mutator internals and the parts of the queue I haven't announced
stay where they belong: with me.*

---

## Part I — The person and the pivot

**1. Who are you and what do you do?**

Independent vulnerability research. Media-parsing code — the libraries that
turn untrusted bytes into images, audio and video on every phone in the
world. The work ran privately for a while; in October I published the
platform, the methodology and the findings. What you see in the repo is the
part I've decided is public.

**2. Why go public now?**

The work crossed the line where privacy stopped paying rent. A running
platform, a reproducible upstream report, a methodology that works on
hardware anyone can rent for a few dollars. Publishing buys peer review and
a timestamped record of priority — and it costs me nothing I wasn't already
done holding close. What stays private is the next twelve months of the
queue. That part is worth money, so it stays home.

**3. Why media parsers specifically?**

Exposure math. Old C code, hostile binary formats, reachable from a file a
stranger sends you, shipped at billion-device scale, vendored into forks that
lag upstream by years. Where else would you hunt? The fashionable targets
are crowded precisely because they're fashionable. I prefer surfaces where
the bugs outnumber the hunters.

**4. One person vs Google's OSS-Fuzz — isn't that a losing game?**

Only if you play their game. OSS-Fuzz runs the same harnesses on upstream
code with thousands of cores. I lose that race by definition, so I don't
enter it — I compete on surface selection. Compute is rented; positioning
is designed. *How* I score surfaces — that's the part I'd put behind a paywall
if I were selling, so I'll just say it exists and it works.

**5. What does "going public" change about how you operate?**

Every internal decision now has to survive external scrutiny. The triage
writes an append-only index. The findings table has a status column. Claims
without artifacts don't ship. Going public isn't a PR exercise — it's a
discipline upgrade. And for the record: what's public is a floor, not a
ceiling.

---

## Part II — Methodology

**6. Explain vendor-divergence analysis.**

AOSP doesn't link upstream libraries — it vendors copies under `external/`,
and the copies freeze in time. `external/libexif` is 0.6.21, last upgraded
upstream in June 2015. `external/flac` is 1.4.3 while upstream ships 1.5.0
with real parser-hardening commits. I build the shipped bytes standalone and
fuzz them. A crash there isn't theoretical — it's an n-day on every device
parsing the format. Which other libraries in `external/` have the same
divergence? I've measured more than I've named. That list isn't public.

**7. How do you choose what to fuzz next?**

There's a scoring model. Reachability, coverage thinness, code recency — and
two more factors I'd rather keep to myself, because they're the difference
between my hit rate and the average. The public version: fresh upstream code
wins, encoder paths win, anything OSS-Fuzz can't easily reach wins. The
exact weights are mine.

**8. The "write path" argument — why fuzz encoders?**

Everyone feeds files into decoders; almost nobody fuzzes
decode→re-encode→serialize→reparse loops. Yet box writers, CRC builders and
metadata serializers get maybe a tenth of the coverage decode paths get —
reachable from the same untrusted input. My round-trip harness does the full
loop through x265 and back. Seventy-plus timeouts on mature code tells you
that path was never pushed hard. What it produced beyond timeouts — some of
that is still in the bucket marked "not yet public."

**9. Why run MemorySanitizer when everyone stops at ASan+UBSan?**

MSan catches what nothing else can see — uninitialized memory doesn't crash
under ASan, it silently leaks or branches on garbage. It's expensive: the
whole dependency tree under `-fsanitize=memory` or you drown in false
positives. Two days of build pain buys a bug class almost nobody watches.
There's a second reason I run it, and that one I'm keeping — let's say MSan
data feeds something else in the pipeline and leave it there.

**10. Corpus engineering — what's your approach?**

Conformance suites, regression inputs, a structure-aware mutator, and
frame-splice seeds that force codec realloc paths. The mutator understands
HEIF box structure — which is all I'll say about its internals. How it
decides *what* to splice is the difference between a toy and an instrument,
and that logic is not in the repo.

**11. What does your triage pipeline look like?**

Deterministic. Stack signatures, dedup buckets — 778 artifacts collapsed
into 97 signatures. Timeouts replayed separately; UB classified by
reachability; MSan re-runs where it matters. What gets escalated and what
gets deleted is a judgment call I made explicit in code — the thresholds
are tuned, and the tuning is the craft. The buckets are public; the
thresholds aren't.

**12. How do you avoid the "fuzzing produces noise" problem?**

One rule: no claim without an artifact. Everything in the findings table
reproduces, has a trace and a status. Anything that couldn't reproduce was
deleted, not counted. What I count privately — the gray zone between
"reproduces" and "reportable" — is a larger number than what's in the table,
and I'll leave it at that.

---

## Part III — Engineering depth

**13. Walk me through the platform architecture.**

Four `systemd-run` scopes with hard CPU quotas on two cores — 140/40/20/20.
Master lineage, release lineage, an AFL++ CmpLog instance, the MSan scope.
Daily `git pull → rebuild → relaunch` on a timer. Watchdog restarts,
append-only crash index, per-minute telemetry. The visible part is in the
repo. The scheduling policy — which target gets which quota and *when that
changes* — is the part I've deliberately kept thin in the public tree.

**14. Why systemd scopes and not Kubernetes?**

Two cores. cgroups give quotas, limits, restart, journal — forty lines of
shell. Kubernetes would eat the budget I'm spending on coverage. The boring
choice that maximizes fuzz cycles per dollar is the right choice. If someone
reads the orchestration and thinks "that's it?", good — the point was never
the plumbing, it's what the plumbing feeds.

**15. How did you build AOSP libraries standalone?**

Stub header layer for the Android build tree — ALOG over stderr,
`errorWriteLog` as a no-op, empty media interface headers — plus the real
source lists and cflags extracted from each library's `Android.bp`. The
exact bytes Android ships, under Clang sanitizers, on a VPS. What I've
built beyond flac/exif/sonivox and haven't announced — there are more in
the pipeline. I'll let the next writeup do the talking.

**16. Hardest bug in your own infrastructure?**

A scope-restart race — dying processes still holding the cgroup while the
watchdog spawned duplicates that corrupted the corpus queue. Fixed with a
`wait_scope_dead` primitive: relaunch on cgroup empty, not on process exit.
The public fix is in the repo. What that incident taught me about failure
domains I put into places I haven't shipped yet.

**17. Most embarrassing operational failure?**

`shift:exif-utils.c` in the UBSan suppressions file — the check is called
`shift-base`. Seven hours of restart loop. Now every config change validates
on one binary before it rolls to a scope. I'm not embarrassed by it — I'm
embarrassed it took me a restart loop to learn what any ops manual would
have told me.

**18. How do you know fuzzing is actually progressing?**

8-bit counter coverage, per target, per minute. Around 30k on the primary
heif surfaces. Coverage is the heartbeat — flatline means saturation or a
reachability bug in the harness. There's a second metric I track that I
consider more predictive than coverage, and I'm not disclosing it — partly
because I'm still validating it, partly because it works.

---

## Part IV — Findings

**19. The libde265 bug you reported — walk me through it.**

F-002: SEI `decoded_picture_hash`, `hash_type` byte straight from the
bitstream into an enum — attacker-controlled, reproducible on 1.1.2 and
master. Filed as [strukturag/libde265#546](https://github.com/strukturag/libde265/issues/546)
with PoC, trace, and a fix suggestion. That's the one I've chosen to show.
Whether it's the most interesting thing in my crash index is a question
I'll answer in a later writeup.

**20. 778 artifacts and one report — how is that a success?**

That ratio *is* the triage working. Most artifacts are UB-class findings
below the reporting bar — filing them all would make me a noise generator.
What I'd add: "one report" means one *public* report. The index holds more
than I've disclosed; some entries are waiting on confirmation, some on
timing, and one or two on me deciding what they actually are. The table
shows what's done. It doesn't show what's cooking.

**21. Zero memory-corruption findings so far — does that worry you?**

No — and anyone who's fuzzed mature parsers will tell you why. The decode
paths have been chewed by fleets for years. My bet is structural: divergent
forks, write paths, MSan territory. Saying more about what I *expect* to
find there would be telling you where to look, so I'll just say the
expectation exists and it's based on data I haven't published.

**22. Closest you've come to a real exploitable bug?**

The round-trip timeout bucket — seventy-plus hangs on paths nobody
exercises, some still under classification. "Slow" and "unbounded" are
indistinguishable until replayed. There's one input in that bucket I've
spent more time on than the rest. That's all you're getting today.

---

## Part V — Industry and tradecraft

**23. Your take on Android's external/ hygiene?**

Better than the memes, worse than it should be. Google cherry-picks CVEs —
the hot paths aren't abandoned. But between-CVE hardening never lands:
refactors, parser rewrites, whole bug classes removed upstream that still
exist on devices. A systemic n-day generator nobody's mining because
everyone targets upstream. I've quantified the gap for more libraries than
the three I've named publicly. That analysis will come out when the queue
behind it is done.

**24. Responsible disclosure as an independent — your approach?**

Report early, report clean: PoC, trace, affected versions, proposed fix —
everything a maintainer needs to say "confirmed" in one read. F-002 is the
template. What I haven't decided publicly is my disclosure timeline policy
for the findings still in the bucket — that answer depends on what they
turn out to be, and I'll publish it when it matters.

**25. Solo vuln research in five years — where does it go?**

The commodity tier is dead — fleets own upstream fuzzing. The positioning
tier grows: vendor forks, build paths, sanitizer combinations, embedded and
automotive parsers. The edge is synthesis — enough build-system, sanitizer
and domain knowledge to reach surfaces nobody reached. And there's a third
tier forming that I'd rather demonstrate than describe. Watch the repo.

**26. What would you do with a team and a real budget?**

The playbook generalizes: every vendor fork of a parsing library is a
hunting ground — automotive IVI, embedded SDKs, firmware, Smart-TV codecs.
Differential fuzzing upstream-vs-fork mechanically isolates backport gaps.
There's a version of that idea I've scoped further than I've written down —
it stops being a research program and starts being a product. Details on
request, under NDA preferably.

---

## Part VI — The hire

**27. Why hire you instead of buying a fuzzing service?**

Services fuzz your code on their commodity rig. What I bring is judgment
about where bugs hide — and a platform whose *interesting* parts I've shown
you work, while keeping the sharpest parts private. The repo is the
audition, not the inventory. Anyone who hires me gets the parts I haven't
published — that's rather the point.

**28. What role are you looking for?**

Vulnerability research or product security — real code: parsers, codecs,
embedded stacks, anything that eats untrusted input. Remote preferred. The
job description I want is "find what's exploitable before someone else does,"
and I'd like the compute to go with it — I know what this platform does on
two cores; I'm curious myself what it does on two hundred.

**29. What should a hiring manager verify to trust your claims?**

Everything public — harnesses compile, the deploy tree stands up a node,
`MANIFEST.sha256` verifies, the crash index is append-only, the upstream
issue reproduces. For the parts that aren't public: hire me and they're in
scope. That's not evasion — that's pricing.

**30. What do you want readers to remember?**

That the interesting question in security is never "how much compute do you
have" — it's "what are you looking at that nobody else is." I've shown you
the platform, the method, and one verified finding. What I haven't shown
you is the rest of the index, the rest of the queue, and the parts of the
pipeline I consider mine. A researcher who tells you everything is either
done or bluffing. I'm neither — and this profile is the part I'm comfortable
showing you today.

---

*Vladimir Garenitsa / MalwareDante — independent vulnerability research.
Contact: github.com/malwaredante · malwaredante@proton.me*
