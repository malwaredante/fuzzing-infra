# Interview Q&A — Vladimir Garenitsa / MalwareDante

*Prepared talking points for podcasts, written interviews and recruiter deep-dives.
Every claim below maps to a verifiable artifact in
[github.com/malwaredante/fuzzing-infra](https://github.com/malwaredante/fuzzing-infra).*

---

## Part I — The person and the pivot

**1. Who are you and what do you do?**

I'm an independent vulnerability research engineer. I build and operate
fuzzing infrastructure aimed at media-parsing code — the libraries that turn
untrusted bytes into images, audio and video on every phone in the world.
Until recently all of it ran privately; this October I went public with the
platform, the methodology and the findings.

**2. Why go public now?**

Because the work crossed the threshold where silence stopped making sense.
I have a running platform, a reproducible upstream report, and a methodology
that produces results on hardware anyone can rent for a few dollars. At that
point publishing costs nothing and buys everything — peer review, citations,
collaboration offers, and a public record of priority. Timestamped commits and
a signed manifest beat private notes.

**3. Why media parsers specifically?**

Attack-surface math. A media decoder is the ideal target class: it parses
complex binary formats, runs at scale on every device, ships inside
messaging apps where files arrive from strangers, and — critically — the
code is old, in C, and full of manual memory management. Media libraries are
where n-days live longest because vendors ship forks that lag upstream by
years. I'm not chasing fashionable targets; I'm hunting where the exposure
multiplier is highest.

**4. One person vs Google's OSS-Fuzz — isn't that a losing game?**

It's a losing game only if you play their game. OSS-Fuzz runs the same
harnesses on upstream code with thousands of cores. I can't win on compute,
so I don't compete on compute — I compete on surface selection. I fuzz the
AOSP fork instead of upstream, the encoder write-path instead of the decode
path, and I run sanitizer classes most setups skip because they're annoying
to build. Different territory, different bugs. Compute is rented; positioning
is designed.

**5. What does "going out of the shadows" mean for you operationally?**

It means every internal decision now survives external scrutiny. My triage
writes an append-only index because private me could tolerate a sloppy
crash folder — public me can't. My findings table has a status column because
claims without statuses are marketing. Going public isn't a PR exercise; it's
a discipline upgrade.

---

## Part II — Methodology

**6. Explain vendor-divergence analysis in one paragraph.**

AOSP doesn't link upstream libraries — it vendors copies under `external/`
and those copies freeze in time. `external/libexif` is version 0.6.21, last
touched upstream in June 2015. `external/flac` is 1.4.3 while upstream shipped
1.5.0 with real parser-hardening commits. So I take the exact bytes Android
ships, build them standalone, and fuzz them. A crash there isn't a theoretical
bug — it's an n-day on every device that parses the format. The gap between
"fixed upstream" and "shipped on a billion devices" is my hunting ground.

**7. How do you choose what to fuzz next?**

Exposure math, not fashion. I score surfaces on three axes: reachability
(does an untrusted file reach this code automatically?), coverage thinness
(does OSS-Fuzz exercise it?), and recency (how fresh is the code?). Fresh
upstream code wins because the window between commit and coverage is where
solo research still beats fleets. Sequences/track APIs and encoder paths
score high on all three.

**8. The "write path" argument — why does fuzzing encoders matter?**

Everyone feeds files into decoders; almost nobody fuzzes
decode→re-encode→serialize→reparse loops. But box writers, CRC builders and
metadata serializers are code that gets maybe a tenth of the coverage decode
paths get — and it's reachable from the same untrusted input. My
`heif_roundtrip` harness does the full loop: decode a HEIF, re-encode pixels
through x265, write boxes, reparse, decode again. Seventy-plus timeouts on
mature code tells you that path has never been pushed hard before.

**9. Why run MemorySanitizer when everyone else stops at ASan+UBSan?**

Because the bugs MSan catches are invisible to everything else — use of
uninitialized memory doesn't crash under ASan, it just quietly leaks or
branches on garbage. MSan is expensive: you must rebuild the entire
dependency tree under `-fsanitize=memory` or you get floods of false
positives from uninstrumented libraries. That cost is exactly why coverage
is thin there. Two days of build-script pain buys you a bug class almost
nobody is looking at. Cheap alpha.

**10. How do you handle corpus engineering?**

Four sources, layered: upstream conformance suites (HEVC and HEIF test
vectors — real structure, real reach), regression inputs from upstream test
suites (inputs that historically broke the parser), a structure-aware HEIF
box mutator that understands box boundaries instead of byte-flipping blindly,
and frame-splice seeds that force codec realloc paths — channel-count and
bit-depth transitions in FLAC's `allocate_output_`, that kind of thing. A
corpus isn't a pile of files; it's a directed probe set.

**11. What does your triage pipeline look like?**

Deterministic and boring, deliberately. Every artifact gets a stack signature
— top frames normalized — and drops into a dedup bucket. 778 artifacts
collapsed into 97 signatures. Timeouts get replayed separately from crashes
because a hang is a different bug class with a different threat model. UB
findings get classified by reachability: an enum load on an
attacker-controlled byte is a finding; a signed-shift on a constant is
hygiene. Where it matters I re-run under MSan to confirm or kill.

**12. How do you avoid the "fuzzing produces noise" problem?**

Verification culture. My rule is: no claim without an artifact. Every entry
in my findings table reproduces, has a minimized input or a named seed, a
sanitizer trace, and a status — fixed, reported, or suppressed-with-reason.
When I say "zero false-positive ASan events," that's not modesty, it's a
process guarantee: anything that couldn't reproduce got deleted, not counted.

---

## Part III — Engineering depth

**13. Walk me through the platform architecture.**

Four `systemd-run` scopes with hard CPU quotas — 140%, 40%, 20%, 20% of a
2-core box — so fuzzers share hardware without starving each other. Each
scope runs a target set: master-lineage targets, release-lineage, an AFL++
CmpLog instance, and the MSan scope. A systemd timer does daily
`git pull → incremental rebuild → relaunch` against upstream masters. A
watchdog restarts dead scopes within minutes. Triage, telemetry and the
crash index run as services. I check in twice a day; the fleet runs itself.

**14. Why systemd scopes instead of containers or Kubernetes?**

Honest answer: it's a 2-core VPS. cgroups via `systemd-run` give me CPU
quotas, memory limits, auto-restart and journal integration with zero
orchestration overhead and maybe forty lines of shell. Kubernetes on two
cores would consume the budget I'm trying to spend on coverage. The right
engineering choice is the boring one that maximizes fuzz cycles per dollar.

**15. How did you make AOSP libraries build standalone?**

That was the fiddly part. `external/` sources expect the Android build tree:
they include `log/log.h`, `cutils/*`, media interfaces that don't exist on a
plain Linux box. I wrote a stub header layer — ALOG macros over stderr,
`android_errorWriteLog` as a no-op, an empty `MediaPlayerInterface.h` — and
extracted each library's real source list and cflags from its `Android.bp`,
including parser-defining flags like `_IMELODY_PARSER` for sonivox. The
result: the *exact* code Android ships, compiled with Clang sanitizers,
fuzzable on a VPS in minutes.

**16. What's the hardest bug you've had in the infrastructure itself?**

A scope-restart race. A fuzzer would die, the watchdog would respawn it, but
the dying process hadn't fully released the scope — so you'd get duplicate
instances fighting over the corpus directory and corrupting the queue. The
fix was a `wait_scope_dead` primitive: don't relaunch on process exit, wait
on cgroup empty. Classic distributed-systems lesson applied to a 2-core box:
exit is an event, not a state.

**17. And the most embarrassing operational failure?**

An invalid UBSan suppression. I wrote `shift:exif-utils.c` in the suppressions
file — the check is actually named `shift-base`. Every binary in that scope
died at startup, the watchdog faithfully restarted them, and the scope burned
seven hours in a restart loop. Now every suppression and config change gets
validated against one binary before it touches a scope. Test the change, then
roll the fleet.

**18. How do you measure that fuzzing is actually progressing?**

8-bit counter coverage from SanitizerCoverage, per target, logged every
minute. On the primary heif surfaces I'm holding roughly 30k counters.
Coverage isn't the goal — it's the heartbeat monitor: if a target's coverage
flatlines for a day, either the corpus is saturated or the harness has a
reachability bug. Both are worth investigating. Growth curves are how you
know the machine is alive.

---

## Part IV — Findings

**19. Tell me about the libde265 bug you reported.**

F-002: in SEI message `decoded_picture_hash`, the `hash_type` byte is
read straight from the bitstream and loaded as an enum — values outside
{0,1,2} are UB, and an attacker controls that byte completely. It reproduces
on release 1.1.2 and on current master. I filed
[strukturag/libde265#546](https://github.com/strukturag/libde265/issues/546)
with a minimized PoC, the UBSan trace, an MSan cleanliness check, and a
concrete fix suggestion — validate or clamp at the parse site. Small bug,
clean report, real attack surface.

**20. 778 artifacts and only one report — how is that a success story?**

Because that ratio is what triage is *for*. Of 778 artifacts, 97 unique
signatures, and the overwhelming majority are UB-class findings that don't
meet the bar for upstream noise. Reporting all of them would burn maintainer
goodwill and brand me as a noise generator. The discipline is knowing the
difference between "the sanitizer fired" and "a human should spend time on
this." One well-documented report is worth fifty sloppy ones.

**21. Zero memory-corruption findings — does that worry you?**

Not yet, and here's the honest reasoning. The mature decoder paths have been
fuzzed by OSS-Fuzz for years — expecting to find heap overflows there in
week one would be magical thinking. My bet is structural: divergent forks,
write paths, and MSan territory haven't been mined at all. Fuzzing is a
marathon where infrastructure quality decides who finds the bug, not luck.
I'm on the track; the platform keeps running while I sleep.

**22. What's the closest you've come to a real exploitable bug?**

The heif round-trip timeouts. Seventy-plus hangs on encode→serialize→reparse
is interesting precisely because it's under-characterized — some are probably
just quadratic box writers on adversarial input, but until each is replayed
and classified, "slow" and "unbounded" are indistinguishable. That bucket is
where I expect either a DoS-class finding or a performance bug upstream will
actually care about.

---

## Part V — Industry and tradecraft

**23. What's your opinion on the state of Android's external/ hygiene?**

It's better than the memes say and worse than it should be. Google does
cherry-pick CVE fixes — the hot paths aren't abandoned. But version-level
divergence means everything *between* CVEs never lands: hardening commits,
refactors that remove bug classes wholesale, parser rewrites. The result is a
gray zone where code is technically patched yet structurally ancient. That's
a systemic n-day generator, and it's barely fuzzed because everyone targets
upstream.

**24. How do you think about responsible disclosure as an independent?**

Report early, report clean, include everything a maintainer needs to say
"yes, confirmed" in one read: PoC, sanitizer trace, affected versions, a
proposed fix. My F-002 report did that. I'm not interested in the
name-and-shame game — I'm interested in the track record. A chain of
accepted, well-written upstream reports is worth more than any headline.

**25. Where do you see solo vulnerability research in five years?**

Splitting in two directions. The commodity tier — running OSS-Fuzz's own
harnesses on upstream — is dead for individuals; fleets own it. The
positioning tier is alive and growing: vendor forks, build-system fuzzing,
write paths, sanitizer combinations, embedded and automotive parsers. The
edge for a solo researcher is synthesis — knowing enough about build
systems, sanitizers and the target domain to reach surfaces nobody else
bothered to reach. Compute is a commodity; insight isn't.

**26. What would you do with a team and a real budget?**

Scale the playbook horizontally. The divergence analysis generalizes:
every vendor fork of a parsing library is a hunting ground — automotive
IVI stacks, embedded SDKs, printer firmware, Smart-TV codecs. With compute
I'd run differential fuzzing upstream-vs-fork automatically: crash a fork on
input X, verify the same input is clean upstream, and you've mechanically
isolated a backport gap. That's a product, not a project.

---

## Part VI — The hire

**27. Why should a company hire you instead of buying a fuzzing service?**

Because services fuzz *your* code with *their* commodity rig. What I bring
is judgment about where bugs hide — which code, which build variant, which
sanitizer, which seed strategy. Infrastructure is the easy part; I've shown I
can build it on two cores. The hard part, the part that takes years to learn,
is surface selection and triage discipline. That's what transfers to any
codebase a company throws at me.

**28. What kind of role are you looking for?**

Vulnerability research or product security — ideally somewhere with real
code: parsers, codecs, embedded stacks, anything that parses untrusted input.
Remote preferred. I want the seat where "find what's exploitable before
someone else does" is the literal job description.

**29. What should a hiring manager verify to trust your claims?**

Everything — that's the point. Pull the repo: the harnesses compile, the
deployment tree stands up a second node, `MANIFEST.sha256` verifies every
file, the crash index is append-only, and my upstream issue is public with a
reproducer attached. I don't want to be believed; I want to be checked.
Candidates who survive verification are the ones worth hiring.

**30. Last question — what's the one thing you want readers to remember?**

That the interesting question in security was never "how much compute do you
have" — it's "what are you looking at that nobody else is." I built a
platform that runs itself, on hardware that costs less than a restaurant
dinner, and it produces verifiable findings against code that runs on a
billion devices. The barrier to serious vuln research was never money. It's
discipline. That's what I'm offering: the discipline, proven in public.

---

*Vladimir Garenitsa / MalwareDante — independent vulnerability research.
Contact: github.com/malwaredante · malwaredante@proton.me*
