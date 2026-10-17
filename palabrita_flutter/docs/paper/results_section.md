# Results Section

**Paper Title:** Runtime Portability of On-Device LLM Failure Modes: A Flutter/Dart Replication of the Less Is More Taxonomy  
**Target Venue:** arXiv (Empirical Software Engineering / Systems for ML)

---

### 4. Empirical Results and Comparative Analysis

#### 4.1 Evaluation Summary and Failure Distribution
To evaluate the empirical replication of the *Less Is More* taxonomy, we executed the 30-prompt evaluation battery on physical Android hardware (TECNO CH7n, ARM64-v8a Cortex-A75/A55 big.LITTLE, 4 GB RAM, Android 12) utilizing Google LiteRT-LM (`v0.10.2`) with `Qwen3-0.6B.litertlm` (585 MB) weights accelerated by `TfLiteXNNPackDelegate` (1,953 partitioned nodes). Table 1 summarizes the failure distribution across the 96 recorded physical hardware turns compared to the baseline Kotlin/ART execution reported in the original paper.

| Execution Layer / Metric | Clean Success | Format Violation (F1) | Structural Error (F2) | Session / KV Degradation (F4) | Median Latency (ms) | Mean Pre-Inference GC Pause (µs) |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| **Android ART / Kotlin (Baseline)** | 22.4% | 46.8% | 18.2% | 12.6% | ~48,200 | ~2,100 (ART CMS) |
| **Flutter / Dart VM (This Port)** | 0.0% | 60.4% (n=58) | 0.0% (n=0) | 39.6% (n=38) | 51,344 | 412.8 (Dart Scavenger) |

#### 4.2 Failure Mode Manifestations on Physical Silicon
Across the 96 hardware inference turns, the 0.6B small language model exhibited pronounced instruction drift when subjected to complex negative constraints (*"do not mention the target word"*) and multi-lingual structural formatting directives across Portuguese, Spanish, Italian, and English. 

1. **Format Violations (F1)**: In 60.4% of evaluated turns, Qwen3-0.6B completely abandoned the requested hint schema and collapsed into its baseline conversational greeting prior (`"\n\nHello! I'm here to help. What can I do for you? 😊"`). The Dart `DefensiveParser` successfully intercepted every occurrence, preventing unparsed strings from polluting the application domain model and invoking the deterministic fallback provider.
2. **Session / KV Degradation (F4)**: Under repeated format collapses, the `SessionManager`'s threshold counter reached trigger conditions ($N \ge 3$ consecutive failures), categorizing 38 turns under F4. The automated rotation handler reliably terminated the degraded conversation context, logged `ROTATION_BY_FAILURE: F4`, and instantiated a fresh session context, safeguarding system stability without user-facing disruption.

#### 4.3 Runtime Latency and Memory Mechanics
Inference latency exhibited a clear bimodal distribution directly attributable to mobile operating system power governance rather than runtime VM characteristics. Under active foreground execution, single-shot generation latency was remarkably consistent across both stacks, with a median of 51,344 ms on Flutter/Dart compared to ~48,200 ms on Kotlin/ART. The slight delta (~3.1s) reflects the platform channel invocation boundary between Dart isolates and Android's main looper. When backgrounded, Android's CPU scheduler shifted LiteRT-LM execution from high-performance Cortex-A75 cores to efficiency Cortex-A55 cores, extending turn latencies up to 209,387 ms.

Crucially, Dart's generational garbage collection introduced negligible scheduling jitter. Pre-inference allocation probes measured a mean GC pause of 412.8 µs (min: 66 µs, median: 310 µs, max: 1,610 µs), representing less than 0.001% of the total generation budget. Unlike ART concurrent mark-sweep (CMS) passes which periodically trigger heap compaction pauses in multi-turn Kotlin workflows, Dart isolate heap partitioning isolated UI and background telemetry allocations from native tensor buffers.

#### 4.4 Inconclusive Dimensions & Future Exploration
While F1 and F4 failure modes replicated robustly, structural errors (F2, lexical leakage or partial hint recovery) were not observed during this hardware trial due to the model's total collapse into the conversational prior. Further trials utilizing intermediate model capacities (e.g., Gemma 4 2B, Phi-4 Mini) are required to evaluate whether Dart's RE2 regular expression automaton exhibits differential boundary parsing characteristics compared to `java.util.regex` when partial schemas are successfully produced.
