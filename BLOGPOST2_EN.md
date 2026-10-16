# The Illusion of Progress: how a typo in my custom mutator sent my fuzzer into the wrong parser

**A question up front — I'll answer it at the end: when did you last verify that your fuzzer is executing the code you actually intended? Not "executing code at all" — everyone's coverage grows. I mean *that* code. If you can't answer instantly, keep reading. Every indicator on my side was green too.**

A postmortem of an incident in my own fuzzing infrastructure. Not a "how we found 100 CVEs" story — a story about three weeks spent fuzzing the wrong parser on a dying VPS while every health metric glowed green.

## TL;DR

My harness selected the transport parser via `data[0] % 6`. My custom mutator wrote `0xFF` into `data[0]` — the first byte of a sync header.

Do the math: `255 % 6 = 3`. Index `3` is a completely different transport container.

The entire structure-aware stream of the campaign went into a parser I never intended to test. The target parser — the one with the hottest memory-write surface in the whole decoder — sat idle for three weeks. Meanwhile coverage grew, the corpus swelled, crashes rained down.

Nothing looked broken. And that's the scariest part.

## 1. The lab: fuzzing on a shoestring

**Target:** an old media decoder in C++. A format parser for binary streams with manual memory management and fixed-point arithmetic. The kind of deeply buried component that silently dissects everything arriving from the outside world.

I picked it using the standard methodology:

- rich vulnerability history;
- low patch activity;
- verifiable coverage.

**Infrastructure:** deliberately modest. One cheap VPS, a couple of cores, `libFuzzer` + sanitizers, and a custom `LLVMFuzzerCustomMutator`.

No exotics. The whole point of the experiment was to prove that methodology has to work even on hardware you'd be embarrassed to list on a resume.

**One detail that matters:** the harness supports several container formats. Which parser dissects a given input is decided by the first byte of that input. Remember this.

## 2. Act one: the validation wall

Any complex binary format opens with a rigid structure: syncword, length fields, checksums (CRC).

Blind mutation breaks any of these elements on approach. Result — the parser bails at the first `if`.

At the start I got the classic picture:

- **Throughput:** single digits of effective executions per second (`exec/s`).
- **Coverage graph:** flat as a table.
- **Outcome:** validation eats 99% of mutations, and behind it lives a huge body of code the fuzzer simply never reaches.

The standard fix is a structure-aware approach.

I wrote a custom mutator. After every change it obediently recomputed length fields and CRC. On top, a wrapper packaged the mutational chaos inside a structurally valid frame. Outside — a canonical container; inside — hell and brimstone for the parser.

The effect was instant. Penetration jumped an order of magnitude. The decoder core lit up in coverage within the first hour.

In a typical article this is where you'd get a fat period and a triumphant conclusion: "Custom mutators solve everything, subscribe to my channel."

That's where my nightmare began instead.

## 3. Act two: the `255 % 6` detective story

Three weeks into continuous fuzzing I decided to run a routine audit. Not of the target — of my own mutator. The motive was mundane: crashes were pouring in but all of one class, and I wanted to know where the compute was actually going.

I asked the input generator the fundamental security question:

> For every byte you produce — which code interprets it first?

I started tracing the wrapper logic. It built the header from the start of the buffer. To make the parser accept the file as "its own," the first byte (`data[0]`) was hard-overwritten with `0xFF` (syncword).

Then the arithmetic of my own harness contract kicked in:

```cpp
data[0] = 0xFF;  // that's 255 in decimal
255 % 6 = 3;     // select parser by remainder
kTTs[3] = ...;   // oops. that's a different transport format
```

Index `3` invoked a different container format with a completely different parsing automaton.

Every wrapped input — thousands of files, the backbone of the three-week campaign — was being decoded by a parser I never planned to touch.

Meanwhile the target parser — the prime memory-corruption candidate in the whole project, where block lengths and distribution indices come straight from the stream — received exactly zero directed pressure the entire time.

The most instructive part is the list of things that looked perfectly normal.

**The four horsemen of false calm:**

1. **Inputs weren't rejected.** The wrong parser happily accepted them and dove deep into its state machine. Work was humming along. Just not mine.
2. **Coverage grew.** Of course it did: the fuzzer was discovering and executing real, previously uncovered code — of a sibling parser.
3. **The corpus swelled.** Coverage-guidance faithfully kept every unique input that unlocked new features (in the wrong code).
4. **Crashes rained down.** The specific UB anomalies in fixed-point math don't care which container the payload arrived in. They'll be everywhere.

All four health indicators glowed green. The fuzzer didn't hang, didn't crash. It just silently worked for a neighbor.

This is the fuzzing equivalent of a typo in an SQL query that's syntactically valid and returns meaningful rows. The worst kind of bug that exists: it has no external symptoms.

## 4. Act three: the generator is your reachability ceiling

I fixed the bug: byte zero is now assigned explicitly from a distribution across all available transports, the body mutates starting from the second byte, and every transport got its own isolated wrapper.

After the fix I decided to thoroughly inventory my generator's entire emission space. And immediately hit a second blind spot.

One of the decoder's configuration fields worked like this: values up to 31 encode in five bits; anything higher uses a special escape sequence.

My generator knew nothing about escape sequences. It simply couldn't produce them.

**Consequence:** an entire family of decoder configuration profiles was being cut off at the door. The code behind them was unreachable *by construction* — because of a single unset bit in the mutator's code.

That's the second half of the lesson, and it's universal:

> In structure-aware fuzzing, the engine doesn't determine code reachability. Your generator does.

A million iterations won't cover code the generator physically cannot emit. Theoretically that's obvious. Practically — almost nobody inventories their mutator's emission space. If your project does, I genuinely want to hear about it in the comments.

## 5. How I rebuilt the process: six new rules

The root cause wasn't arithmetic or a dumb typo. It was process: I audit the target to a strict standard of evidence — but the pipeline feeding it, I didn't.

This is what changed in how I run fuzzing campaigns:

1. **End-to-end input tracing.** Every new mutator or wrapper passes a manual test. I take one generated input and walk it by hand to the parser. Which path actually executes — that's a fact, not an assumption.
2. **Selector contract.** Every place where the harness interprets input bytes for branching logic is now written down explicitly. The mutator is required to know about each such byte.
3. **Emission inventory.** A matrix gets built: the range of values the mutator can emit versus the range the parser accepts. Every blind spot gets closed with code.
4. **PC-table as the single source of truth.** Corpus replay with a coverage dump gives a concrete list of functions that are reachable but not yet covered. That's a map for preparing the next seeds — not a vague feeling of "yeah, we're fuzzing."
5. **Crash classification — replay only.** Sorting and deduplicating bugs by signature without clean artifact reproduction is forbidden. Otherwise a real memory-corruption finding drowns in the noise of identical fixed-point anomalies.
6. **Automated watchdog.** Logs are scanned continuously by a script. If the fuzzer finds something interesting at 3 AM — the alert fires at 3:05, not as a morning surprise over coffee.

## Scoreboard: the bottom line

- **Logs:** thousands of crash artifacts. I replayed everything that fit inside the triage window.
- **Result:** hundreds of unique confirmed anomaly locations. One class — `runtime error` in fixed-point arithmetic. Formally UB; practically, standard lifestyle for legacy C++ code.
- **Confirmed memory corruption:** 0.
- **Dynamics:** after the mutator rewrite, the coverage graphs finally broke through the ceiling. New transports and a raw-config path opened up a body of code that had been invisible to the campaign for weeks.

Zero memory bugs is just data as of this second. "We haven't found one yet" and "there is none" are fundamentally different claims. The argument between them is settled by CPU-hours. And my humble VPS keeps clocking them.

## In lieu of a conclusion

The main weak point of coverage-guided fuzzing isn't the engine (libFuzzer is beautiful), isn't the sanitizers, and certainly isn't hardware.

It's your pipeline — the thing that turns an engineer's intent into bytes at the program's input. A mutator is a parser in reverse. A harness is a compiler for your design. And they deserve exactly the same rigorous audit as the target itself.

Because between "the fuzzer executes code" and "the fuzzer executes the code I meant" there's easily room for one extra parser, three weeks of wasted time, and a very convincing — but entirely false — illusion of progress.

## Now, about your fuzzer

Back to the question from the first paragraph. If you've read this far — here are three checks for one evening, cheaper than three lost weeks:

1. **Which byte decides where your input goes?** Find every place the harness reads data for branching. Does your mutator know about all of them?
2. **What can your generator emit?** Write out the emission range for every field and compare it against the parser's acceptance range. Escape sequences, reserved values, boundaries.
3. **Which code executes first?** Walk one input from generation to parser — by hand, once.

If you find your own `255 % 6` — tell me in the comments; I'm genuinely curious how widespread this is. If you don't — tell me how you checked: I still don't know a way to spot this earlier than three weeks in.

Because I'm fairly sure: everyone who's written their own input pipeline has a line like this somewhere. The only difference is who already found theirs — and who's still fuzzing a neighboring parser, admiring green graphs.

---

*Target, infrastructure, and prioritization deliberately offstage — the techniques transfer, the details don't. If anything worth confirming shows up — through responsible disclosure.*


---

## Publications

- **DEV.to (EN):** https://dev.to/malwaredante/the-illusion-of-progress-how-a-typo-in-my-custom-mutator-sent-my-fuzzer-into-the-wrong-parser-435j
- **Medium (EN):** https://medium.com/@malwaredante/the-illusion-of-progress-how-a-typo-in-my-custom-mutator-sent-my-fuzzer-into-the-wrong-parser-222c16b1cbc7
- **Habr (RU):** https://habr.com/ru/sandbox/309628/
