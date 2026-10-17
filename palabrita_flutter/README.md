# Palabrita Flutter — AI Inference Layer & Research Benchmark

A research-grade Flutter/Dart port of the on-device AI inference layer from [Palabrita](https://github.com/woliveiras/palabrita), designed to evaluate runtime portability, failure taxonomy stability (F1–F5), and execution profiles of small language models (Qwen3 0.6B / LiteRT-LM) between Kotlin/Android ART and Dart/Flutter.

---

## Research Hypothesis

Following William Oliveira's paper *"Less Is More: On-Device Small Language Model Failure Modes on Android"*, this project tests the hypothesis that **F1 (format violations), F2 (structural errors), and F4 (session/KV degradation)** rates differ between Kotlin and Flutter implementations due to integration-layer runtime mechanisms rather than model-level behavior:

1. **Generational GC vs. ART Heap Management (F4)**:
   Dart runs an isolate-local generational scavenger and concurrent mark-sweep garbage collector. Under memory constraints, GC pause spikes during active inference influence KV-cache retention and session rotation boundaries differently than Android's ART, shifting where F4 degradation surfaces.
2. **FFI vs. JNI Overhead**:
   Dart FFI bypasses the Java Native Interface (JNI) marshaling layer with direct C-ABI function dispatch. While the underlying LiteRT-LM weights and generation parameters remain identical, call overhead profiles and memory pinning influence wall-clock latency distributions.
3. **Regex Engine Grammar & Backtracking (F1/F2)**:
   Dart's regular expression engine uses an RE2/ECMAScript-derived automaton without exponential backtracking, whereas Kotlin uses `java.util.regex`. On malformed model completions near the structural boundary, parsing and recovery decisions exhibit subtle divergence in fallback triggers.

---

## Project Architecture

```
palabrita_flutter/
├── lib/
│   ├── benchmark/          # Benchmark runner, InferenceLogger (NDJSON/CSV)
│   ├── inference/          # LiteRT-LM C FFI bindings & InferenceEngine
│   ├── parser/             # Defensive parser ported from Kotlin
│   ├── prompt/             # PromptEngine & HintFallbackProvider
│   └── session/            # Session lifecycle manager & rotation triggers
├── assets/
│   └── test_prompts.json   # 30 fixed reproducible benchmark prompts
└── test/
    ├── benchmark_runner/   # Headless benchmark test suite
    ├── defensive_parser_test.dart
    ├── inference_engine_test.dart
    ├── inference_logger_test.dart
    ├── prompt_engine_test.dart
    └── session_manager_test.dart
```

---

## How to Run the Benchmark

### 1. Run Headless Benchmark Suite
To execute the automated headless benchmark suite across the 30 fixed prompts:
```bash
flutter test test/benchmark_runner/run_benchmark.dart
```

### 2. Run All Unit & Integration Tests
```bash
flutter test
```

### 3. Static Analysis
```bash
flutter analyze
```

---

## How to Read Output Logs

Benchmark executions automatically capture every turn before and after parsing into two formats:

1. **NDJSON Log (`inference_log.ndjson`)**:
   Streaming newline-delimited JSON containing complete turn telemetry:
   ```json
   {
     "timestamp": "2026-10-17T12:00:00.000Z",
     "session_id": "palabrita_sess_1760700000000_1",
     "turn_number": 1,
     "raw_output": "hints: Hint 1 | Hint 2 | Hint 3",
     "parsed_output": "Hint 1 | Hint 2 | Hint 3",
     "parse_decision": "success",
     "failure_category": "none",
     "latency_ms": 142,
     "gc_pause_estimate_us": 120,
     "device_info": "Google Pixel 7 - Android 14",
     "prompt_id": "p001",
     "word": "gatos",
     "language": "pt"
   }
   ```
2. **CSV Export (`inference_log.csv`)**:
   Standard spreadsheet export generated via `InferenceLogger.exportToCSV()` for statistical analysis and plotting.

### Failure Classification Taxonomy
* **`none`**: Successful extraction of valid, non-leaking hints ($\ge 3$).
* **`F1`**: Format violation (e.g. missing `hints:` prefix, non-pipe layout, empty output, conversational preamble).
* **`F2`**: Structural error (e.g. fewer than 3 hints, target word leaked inside hint, invalid JSON data types).
* **`F4`**: Session degradation (repetition loops, hallucination collapse, KV cache degradation deep in session).

---

## Device Tested On

* **Device**: *(To be populated during Android benchmark run, e.g., Google Pixel 7 / Samsung Galaxy S23)*
* **OS / Kernel**: Android 14 / Linux 5.15
* **SoC / RAM**: 8GB RAM
* **Model**: Qwen3 0.6B (LiteRT-LM, single-shot C API)

---

## Baseline Comparison Table

| Metric / Failure Category | Kotlin Baseline (Palabrita) | Flutter Port (Palabrita Flutter) | $\Delta$ (%) |
|---|---|---|---|
| **Clean Parse Success Rate** | *(Baseline from paper)* | *(To be populated from CSV)* | -- |
| **F1 (Format Violation)** | *(Baseline from paper)* | *(To be populated from CSV)* | -- |
| **F2 (Structural Error)** | *(Baseline from paper)* | *(To be populated from CSV)* | -- |
| **F4 (Session Degradation)** | *(Baseline from paper)* | *(To be populated from CSV)* | -- |
| **Mean Latency (ms)** | *(Baseline from paper)* | *(To be populated from CSV)* | -- |
| **Mean GC Pause (µs)** | *(ART Baseline)* | *(Dart Scavenger)* | -- |

---

## License

This project is licensed under the **GNU Affero General Public License v3.0 (AGPL-3.0)**, matching upstream [Palabrita](https://github.com/woliveiras/palabrita).
