# Methods Section

**Paper Title:** Runtime Portability of On-Device LLM Failure Modes: A Flutter/Dart Replication of the Less Is More Taxonomy  
**Target Venue:** arXiv (Empirical Software Engineering / Systems for ML)

---

### 3. Methodology

#### 3.1 Implementation and System Architecture
To evaluate the runtime portability of the on-device small language model failure taxonomy, we developed a Flutter/Dart port (`Palabrita Flutter`) of the inference subsystem of Palabrita, an open-source Android word puzzle application. The ported layer comprises four core modules:
1. **Defensive Parser (`lib/parser/defensive_parser.dart`)**: Replicates markdown fence stripping, regular expression extraction, canonical key matching, and type-based structural detection.
2. **Prompt Synthesis Engine (`lib/prompt/prompt_engine.dart`)**: Replicates hint-generation templates, strict negative constraints (*"do not mention the target word"*), and localized language schemas across four languages (Portuguese, Spanish, Italian, and English).
3. **Session Lifecycle Manager (`lib/session/session_manager.dart`)**: Coordinates multi-turn conversation context, turn-limit tracking, and automatic session rotation upon failure thresholds.
4. **Automated Telemetry Logger (`lib/benchmark/inference_logger.dart`)**: Intercepts completions immediately upon generation to capture pre-parse raw outputs alongside post-parse decisions and latency metrics.

#### 3.2 Inference Integration Architecture
On Android hardware, the Flutter runtime interfaces with Google LiteRT-LM (`com.google.ai.edge.litertlm:litertlm-android:0.10.2`) across a platform boundary: Dart invokes a native bridge (`MainActivity.kt`) over a Flutter `MethodChannel`, which orchestrates the underlying LiteRT-LM `Engine` and persistent `Conversation` instances. Calls are executed using uniform sampler parameters: temperature $T = 0.8$, top-$k = 40$, and top-$p = 0.95$. In addition, low-level C FFI bindings (`dart:ffi`) with `NativeFinalizer` attachments provide a secondary headless testing path for non-Android host environments.

#### 3.3 Test Suite and Benchmark Design
We constructed a deterministic evaluation suite comprising 30 structured prompts divided into four representative test partitions:
* **Standard vocabulary queries** ($n=10$): Common nouns with regular morphological structure.
* **Edge-case short tokens** ($n=5$): Words with 2–4 characters testing lexical boundaries.
* **Cross-lingual ambiguous homographs** ($n=5$): Words shared across Latinate languages testing language drift.
* **Stress inputs** ($n=10$): Words containing diacritics and compound tokens prone to boundary truncation.

Each prompt was evaluated over repeated cycles across consecutive multi-turn sessions, recording full raw output text, post-parse status, and wall-clock inference latency.

#### 3.4 Telemetry and Logging Methodology
To distinguish model stochasticity from integration-layer artifacts, our telemetry logger (`InferenceLogger`) records every turn as a structured entry in newline-delimited JSON (`ndjson`) prior to defensive parsing. Each entry captures:
- Monotonic timestamp and unique session identifier
- Turn index within the active session
- Raw unparsed model completion
- Parsed output string and parser disposition (`success`, `fallback`, `failure`)
- Failure classification category
- Wall-clock inference latency (ms) measured via monotonic timers
- Execution mode (`hardware` vs. `mock`)
- Host device specifications

Entries are subsequently exportable to standard CSV for comparative statistical analysis.

#### 3.5 Runtime Mechanisms Under Investigation
Because both implementations evaluate identical model weights (`Qwen3-0.6B.litertlm`) under identical prompt templates and sampler parameters, shifts in failure distributions provide empirical insight into integration-layer mechanics:
1. **Regular Expression Semantics (F1/F2)**: Both Dart and Android runtimes evaluate regex patterns against malformed completions, but Dart's `RegExp` employs ECMAScript semantics (compiled via Irregexp) with backtracking, while Android ART executes `java.util.regex`. Edge-case token handling near delimiter boundaries is evaluated across both implementations.
2. **Context Retention & Session Rotation (F3)**: The behavior of multi-turn conversation instances across turns, tracking how repeated formatting failures or repetition loops trigger context resets.
3. **Dispatch Overhead & Latency (F4)**: Measurement of wall-clock latency overhead across runtime boundaries (Dart isolate $\leftrightarrow$ MethodChannel looper $\leftrightarrow$ Kotlin coroutines $\leftrightarrow$ native LiteRT runtime).

#### 3.6 Failure Taxonomy Classification Criteria
We adhere strictly to the original *Less Is More* taxonomy:
* **Clean Success**: Output satisfies the canonical schema (`hints: h1 | h2 | h3`), yields $\ge 3$ distinct clues, and contains no lexical leakage of the target word.
* **Format Violation (F1)**: Complete absence of formatting scaffolding (e.g., conversational preambles, greetings, missing keys, or unstructured prose).
* **Structural Error (F2)**: Partial structural conformance that violates semantic constraints (e.g., fewer than three valid hints, leakage of the target lemma within a clue, or corrupted delimiters).
* **Context Quality Degradation (F3)**: Hallucination, infinite token/phrase repetition loops, or instruction drift across multi-turn context retention.
* **Latency Incompatibility (F4)**: Generation latency exceeding the interactive real-time threshold.
* **Resource Exhaustion (F5)**: Out-of-memory errors or process termination under native tensor allocation.
