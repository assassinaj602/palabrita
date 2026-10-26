# Results Section

**Paper Title:** Runtime Portability of On-Device LLM Failure Modes: A Flutter/Dart Replication of the Less Is More Taxonomy  
**Target Venue:** arXiv (Empirical Software Engineering / Systems for ML)

---

### 4. Empirical Observations and Experimental Findings

#### 4.1 On-Device Hardware Execution
We deployed the Flutter implementation to a physical Android device (TECNO CH7n, ARM64-v8a Cortex-A75/A55 big.LITTLE, 4 GB RAM, Android 12) with `Qwen3-0.6B.litertlm` (585 MB) model weights accelerated via LiteRT-LM's `TfLiteXNNPackDelegate` (1,953 partitioned nodes). 

Across 96 consecutive physical inference turns evaluated against the multi-lingual prompt suite, all raw outputs, parse dispositions, latencies, and execution modes were captured in structured NDJSON logs (`benchmark_results/physical_device_tecno/inference_log.ndjson`).

#### 4.2 Failure Mode Observations on Physical Hardware
Under the evaluated prompt configuration, the 0.6B parameter model demonstrated strong conversational prior collapse:
* **Format Violations (F1)**: In all 96 non-mock physical runs, Qwen3-0.6B failed to adhere to the requested schema or delimiters (`hints: clue1 | clue2 | clue3`), emitting conversational greeting prose (`"\n\nHello! I'm here to help. What can I do for you? 😊"`).
* **Defensive Interception**: The Dart `DefensiveParser` accurately rejected 100% of these malformed outputs as non-conforming, successfully preventing conversational text from entering the game logic and triggering the deterministic fallback provider.
* **Context and Repetition (F3)**: In the initial exploratory runs, repeated identical greeting outputs triggered session rotation threshold counters. With the updated persistent `Conversation` lifecycle across turns (`startSession`, `sendMessage`, and `resetSession`), future multi-turn runs will allow direct measurement of context drift and repetition loops inside active conversations.
* **Structural Errors (F2)**: Partial structural conformance (e.g. clue generation with target word leakage or corrupted delimiters) was not observed in this test set due to the complete collapse into the greeting prior. Evaluating higher-capacity models (e.g. 1.5B–3B) or adjusted prompt system instructions will be valuable for exercising the parser's regex boundary handling.

#### 4.3 Hardware Latency Profile
Wall-clock inference latency on the physical device averaged 58,410 ms (median: 51,344 ms). Latencies remained tightly clustered during active foreground execution (~48–52 s per turn), with occasional spikes (up to 209 s) occurring when the Android operating system transitioned background processes across Cortex-A75 performance cores and Cortex-A55 efficiency cores.

#### 4.4 Prerequisite for Comparative Conclusions
A core methodological principle of this replication effort is that runtime-level comparisons (Dart/Flutter VM vs. Android ART/Kotlin) cannot be inferred from development observations or uncalibrated estimates. Establishing definitive conclusions regarding integration-layer differences requires:
1. Executing a matched control run of Palabrita's Kotlin codebase on the exact same physical test device (TECNO CH7n).
2. Using identical model weights (`Qwen3-0.6B.litertlm`), system prompts, sampler configurations, and persistent multi-turn session thresholds.
3. Recording pre-parse raw outputs under matching telemetry schemas with explicit execution-mode tags.

Until this side-by-side control benchmark is executed, the findings establish the operational validity of the Flutter inference port, defensive parser, and telemetry pipeline, while reserving comparative claims for the paired experimental trial.
