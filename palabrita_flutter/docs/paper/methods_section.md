# Methods Section

**Paper Title:** Runtime Portability of On-Device LLM Failure Modes: A Flutter/Dart Replication of the Less Is More Taxonomy  
**Target Venue:** arXiv (Empirical Software Engineering / Systems for ML)

---

### 3. Methodology

#### 3.1 Implementation and System Architecture
To evaluate the runtime portability of the on-device small language model failure taxonomy, we developed a Flutter/Dart port (`Palabrita Flutter`) of the inference subsystem of Palabrita, an open-source Android word puzzle application. The ported layer comprised four core components: (1) a defensive parser replicating fence stripping, regular-expression extraction, and type-based structural detection; (2) a prompt synthesis engine enforcing strict negative constraints, canonical formatting, and language localization across four languages (Portuguese, Spanish, Italian, and English); (3) a session lifecycle manager controlling multi-turn context retention, turn-limit rotations, and failure threshold resets; and (4) an automated telemetry logger capturing execution metrics.

#### 3.2 Inference Engine and Model Configuration
Both the baseline Kotlin implementation and our Flutter port targeted the same underlying model and inference engine: Qwen3 0.6B running atop Google LiteRT-LM (formerly MediaPipe LLM Inference Engine). Inference was configured in single-shot generation mode using LiteRT-LM’s C API via Dart foreign function interface (`dart:ffi`) bindings. Calls were configured with uniform sampler parameters: temperature $T = 0.8$, top-$k = 40$, and top-$p = 0.95$. Memory safety across the unmanaged C boundary was guaranteed using Dart’s `NativeFinalizer` to ensure that native conversation handles and engine allocations were released deterministically without leaking under asynchronous Dart isolate garbage collection.

#### 3.3 Test Suite and Benchmark Design
We constructed a fixed, deterministic evaluation suite consisting of 30 structured prompts divided into four representative test partitions: (a) standard vocabulary queries ($n=10$), (b) edge-case short tokens with 2–4 characters ($n=5$), (c) cross-lingual ambiguous homographs across Latinate languages ($n=5$), and (d) stress inputs prone to structural failure near token boundaries, including diacritics and compound tokens ($n=10$). Each prompt was evaluated over $N = 5$ independent inference cycles across consecutive multi-turn sessions, yielding 150 total generation events per evaluation run.

#### 3.4 Telemetry and Logging Methodology
A critical methodological requirement was isolating integration-layer effects from pure model stochasticity. To prevent defensive post-processing from masking raw runtime variations, our telemetry logger (`InferenceLogger`) intercepted and persisted the raw string output to newline-delimited JSON (`ndjson`) immediately upon receiving completion from the native C API, prior to executing parsing logic. Each entry logged an ISO 8601 timestamp, session identifier, turn index, raw completion, parsed completion, parser disposition, classified failure mode, wall-clock latency (recorded with millisecond precision via high-resolution monotonic clocks), and garbage collection pause estimates sampled using the Dart `developer.Timeline` API. Logs were subsequently exported to comma-separated values for statistical aggregation.

#### 3.5 Disentangling Runtime Effects from Model Behavior
Because both stacks executed identical model weights and temperature parameters, systematic shifts in error distributions were isolated to three runtime mechanisms:
1. **Automaton Differences (F1/F2)**: Discrepancies in regex engine implementations (Dart’s RE2-derived engine vs. Kotlin’s `java.util.regex` backtracking engine) on malformed completions near structural boundaries.
2. **Heap Management and Allocation Pauses (F4)**: Differences between Dart’s isolate-generational scavenging and Android ART concurrent mark-sweep compaction under memory pressure during multi-turn retention.
3. **Dispatch Overhead**: Comparative latency profiling between direct C FFI invocation and Java Native Interface (JNI) marshaling.

#### 3.6 Failure Taxonomy Classification Criteria
Model completions were classified into four mutually exclusive outcomes according to the *Less Is More* taxonomy:
* **Clean Success**: The response satisfied the canonical schema (`hints: h1 | h2 | h3`), yielded $\ge 3$ distinct hints, and contained no lexical leakage of the target word.
* **Format Violation (F1)**: Complete absence of formatting scaffolding (e.g., conversational preambles, missing keys, or unstructured prose).
* **Structural Error (F2)**: Partial structural conformance that violated semantic constraints (e.g., fewer than three valid hints, leakage of the target lemma within a clue, or corrupted delimiters).
* **Session Degradation (F4)**: Multi-turn degradation characterized by consecutive parsing failures, repetitive loop collapse, or context degeneration deep within a session.
