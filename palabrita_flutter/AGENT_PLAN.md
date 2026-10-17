# Palabrita Flutter Port — AI Agent Execution Plan
> Drop this file in your project root. When you open a new AI session, paste this file and say: "Read this plan and start from the current phase."

---

## WHO YOU ARE (Context for the AI)

You are helping Assad, a Flutter/Dart developer and CS undergraduate, build a research-grade Flutter port of the AI inference layer from an open-source Android app called **Palabrita** (github.com/woliveiras/palabrita). The goal is to produce a working Flutter implementation, run benchmarks on Android, and co-author a short arXiv paper with the original developer (William) comparing failure rates across the two stacks.

The research is a follow-up to William's paper "Less Is More" which identified five failure categories (F1–F5) in on-device small language model inference on Android. The hypothesis is that F1, F2, and F4 rates will differ between the Kotlin and Flutter implementations due to integration-layer differences (Dart GC, FFI vs JNI overhead, regex engine differences) rather than model-level behavior.

---

## REPOSITORY TO STUDY

**Main repo:** https://github.com/woliveiras/palabrita

Before writing any code, read and understand these parts of the repo:
1. The AI/inference layer — how LiteRT-LM is called
2. The defensive parser — fence stripping, regex extraction, structural parsing
3. The session lifecycle manager — when and how sessions rotate
4. The prompt engine — hint-only prompt architecture and fallback logic
5. Any existing test or benchmark files

For each file, summarize what it does and what you need to replicate in Dart before writing the port.

---

## CRITICAL PENDING QUESTION

**Wait for Assad to confirm:** William (the repo owner) was asked whether Palabrita uses LiteRT-LM's **streaming API or single-shot generation**. The FFI architecture depends entirely on this answer. Do NOT write the FFI bindings until Assad provides this answer.

---

## PROJECT STRUCTURE TO CREATE

```
palabrita_flutter/
├── lib/
│   ├── inference/          # LiteRT-LM FFI bindings
│   ├── parser/             # Defensive parser (ported from Kotlin)
│   ├── session/            # Session lifecycle manager
│   ├── prompt/             # Prompt engine and fallback logic
│   └── benchmark/          # Benchmark runner and logging
├── test/
│   └── benchmark_runner/   # Headless test suite
├── assets/
│   └── test_prompts.json   # Fixed prompt set for benchmarking
├── pubspec.yaml
└── README.md
```

---

## PHASE 1 — SCAFFOLD

### Task 1.1: Create the Flutter project
```
Create a Flutter project called palabrita_flutter with the folder structure above.
Write the pubspec.yaml with these dependencies:
- ffi: for native bindings
- path_provider: for log file output
- csv: for benchmark export
- collection: utility
Dev dependencies: flutter_test

The project targets Android only for now.
```

### Task 1.2: Create the logging infrastructure FIRST
Before any feature code, build the logger. Every other module will use it.

```
Write a Dart class called InferenceLogger that logs structured events as newline-delimited JSON to a file.

Each log entry must include:
- timestamp (ISO 8601)
- session_id (string)
- turn_number (int)
- raw_output (string) — model output BEFORE parsing
- parsed_output (string) — output AFTER defensive parsing
- parse_decision (enum: success | fallback | failure)
- failure_category (enum: F1 | F2 | F4 | none)
- latency_ms (int)
- gc_pause_estimate_us (int) — use Dart Timeline API to estimate
- device_info (string) — populated once at startup

Save logs to getApplicationDocumentsDirectory()/inference_log.ndjson
Also expose a method exportToCSV() that converts the log to CSV for analysis.
```

---

## PHASE 2 — CORE IMPLEMENTATION

### Task 2.1: Defensive Parser
```
I will paste the Kotlin defensive parser from Palabrita below.
Port it exactly to Dart. Do not change the logic — only translate syntax.

After porting:
1. List every regex pattern used and note if Dart's RE2-based engine handles it differently than java.util.regex
2. Add a comment on any line where behavior might differ
3. Write 10 unit tests covering: clean JSON input, fenced code blocks, malformed JSON, language drift strings, and empty output

[PASTE KOTLIN PARSER CODE HERE BEFORE RUNNING THIS PROMPT]
```

### Task 2.2: Prompt Engine
```
I will paste the Kotlin prompt engine from Palabrita below.
Port it exactly to Dart. Do not change any prompt strings, template structure, or fallback logic — only translate syntax.
Add a method getPromptMetadata() that returns the prompt type used (hint-only vs fallback) for logging.

[PASTE KOTLIN PROMPT ENGINE CODE HERE BEFORE RUNNING THIS PROMPT]
```

### Task 2.3: LiteRT-LM FFI Bindings
```
[FILL IN: streaming OR single-shot — wait for William's answer]

Write Dart FFI bindings for LiteRT-LM's C API using [streaming/single-shot] mode.

Requirements:
- Full binding file using dart:ffi
- NativeFinalizer for all native resources to prevent leaks under Dart GC
- A callback hook that fires on every token (streaming) or on completion (single-shot)
- A timing wrapper that records wall-clock latency per inference call
- A GC pressure probe: before each inference call, force a minor GC hint and record the pause using Dart's Timeline API (dart:developer)
- Structured error handling that maps native error codes to Dart exceptions

The bindings must be in lib/inference/litert_lm_bindings.dart
Also write lib/inference/inference_engine.dart as a clean Dart API over the raw bindings.
```

### Task 2.4: Session Lifecycle Manager
```
I will paste the Kotlin session lifecycle manager from Palabrita below.
Port it exactly to Dart.

Additionally:
- Add a SessionEvent enum: ROTATION_BY_TURN_LIMIT | ROTATION_BY_FAILURE | SESSION_START | SESSION_END
- On every event, call InferenceLogger to record the event with session_id, turn_count, trigger reason, and timestamp
- Expose a currentSessionStats() method that returns turn count, failure count, and last rotation reason

[PASTE KOTLIN SESSION MANAGER CODE HERE BEFORE RUNNING THIS PROMPT]
```

---

## PHASE 3 — BENCHMARK RUNNER

### Task 3.1: Test prompt file
```
Create assets/test_prompts.json with 30 fixed hint-generation prompts.
These should be identical to whatever test prompts Palabrita uses in its own test suite.
If the original test suite is not available, generate 30 prompts that cover:
- Standard vocabulary hint requests (10)
- Edge case short words (5)
- Words with ambiguous language (5)
- Prompts likely to trigger format violations based on the F1/F2 taxonomy (10)

Format: [{"id": "p001", "word": "...", "language": "...", "expected_format": "..."}]
```

### Task 3.2: Benchmark runner
```
Write a headless Flutter benchmark runner in test/benchmark_runner/run_benchmark.dart

It must:
1. Load all prompts from assets/test_prompts.json
2. For each prompt, run inference N times (default N=5, configurable)
3. After each inference:
   - Record raw output to InferenceLogger BEFORE passing to parser
   - Pass output to DefensiveParser
   - Record parsed output and parse decision
   - Classify failure category: F1 (format violation), F2 (structural error), F4 (session/KV degradation), none
   - Record latency and GC estimate
4. After all prompts, call exportToCSV() and print the output file path
5. Print a summary table to console: total runs, F1 count, F2 count, F4 count, mean latency

Must be runnable with: flutter test test/benchmark_runner/run_benchmark.dart
```

---

## PHASE 4 — PR AND PAPER

### Task 4.1: README
```
Write a README.md for the palabrita_flutter repository.

Sections:
- What this is (one paragraph)
- Research hypothesis (the three mechanisms: GC, FFI/JNI, regex engine)
- How to run the benchmark
- How to read the output logs
- Device tested on (Assad will fill in)
- Baseline comparison table (Assad will fill in after running benchmarks)
- License
```

### Task 4.2: PR Description (after first benchmark run)
```
Write a GitHub PR description to submit to github.com/woliveiras/palabrita

Context: This is a research PR adding a Flutter/Dart port of Palabrita's AI inference layer to test whether F1, F2, and F4 failure categories from the "Less Is More" paper hold on a different runtime stack.

Include:
- What was ported (parser, prompt engine, session manager, FFI bindings)
- The research hypothesis
- A results table comparing F1/F2/F4 rates between Kotlin baseline and Flutter implementation
- Inference engine and model config used (Qwen3 0.6B, LiteRT-LM)
- Test device specs (Assad will fill in)
- Open questions for William

[Assad will paste benchmark CSV results here before running this prompt]
```

### Task 4.3: Paper — Methods Section
```
Write the methods section for a short arXiv paper titled:
"Runtime Portability of On-Device LLM Failure Modes: A Flutter/Dart Replication of the Less Is More Taxonomy"

This is a follow-up to: [paste abstract of "Less Is More" paper]

Methods section must cover:
1. Implementation approach — what was ported and how
2. Inference engine and model configuration (Qwen3 0.6B, LiteRT-LM, [streaming/single-shot])
3. Test device specifications
4. Test suite design (N prompts × N runs, fixed inputs)
5. Logging methodology (pre/post parse raw output capture)
6. How we distinguish integration-layer effects from model-level behavior
7. Failure category classification criteria (F1, F2, F4 definitions)

Write in academic style, past tense, ~600 words.
```

### Task 4.4: Paper — Results Section
```
Write the results section for the same paper.

Here is the benchmark CSV output:
[PASTE CSV HERE]

Here is the Kotlin baseline data from the original paper:
[PASTE BASELINE NUMBERS HERE]

The results section must:
- Present F1, F2, F4 rates for both implementations in a table
- Present mean latency comparison
- Note statistically interesting differences
- Propose explanations tied to GC behavior, FFI overhead, or regex engine differences
- Note what is inconclusive and needs more data

Write in academic style, ~500 words.
```

---

## PHASE 5 — GITHUB REPLIES

Whenever William replies on the GitHub issue or PR, paste his comment below and use this prompt:

```
Context: Assad is collaborating with William (woliveiras), the author of the open-source Android app Palabrita and the "Less Is More" paper on on-device LLM failure modes. They are building a Flutter port together as a research collaboration toward a co-authored arXiv paper.

Here is the full conversation so far:
[PASTE FULL GITHUB THREAD]

William just said:
[PASTE WILLIAM'S LATEST COMMENT]

Write a reply from Assad. Requirements:
- Technical and direct, no fluff
- Address every point William raised
- Sound like a developer who knows what they're doing
- If he asks a technical question, answer it specifically
- If he raises a concern, acknowledge it and address it
- End with one forward-moving question or statement
- Max 200 words, conversational not formal
```

---

## CURRENT STATUS

- [x] GitHub issue opened (#3)
- [x] William responded — interested, asked about streaming vs single-shot
- [x] Assad replied with refined hypothesis
- [x] Verified Palabrita uses single-shot generation (doGenerate via sendMessage)
- [x] Phase 1 completed (Scaffold & InferenceLogger)
- [x] Phase 2 completed (Defensive Parser, Prompt Engine, LiteRT-LM FFI Bindings, Session Lifecycle Manager)
- [ ] Phase 3 not started
- [ ] Benchmark not run
- [ ] PR not opened
- [ ] Paper not drafted

---

## NOTES FOR AI AGENT

- Never change prompt content when porting — only translate syntax
- Always write raw output to log BEFORE parsing
- Every module must use InferenceLogger
- The benchmark must be reproducible — fixed prompts, fixed N, fixed model config
- When in doubt, match the Kotlin behavior exactly and document the difference
- Assad will provide all Kotlin source files — wait for them before writing ports
- Assad runs everything on a physical Android device — no emulator results
