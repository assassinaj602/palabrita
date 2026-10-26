# Palabrita Flutter — AI Inference Layer & Research Benchmark

A research-grade Flutter/Dart port of the on-device AI inference layer from [Palabrita](https://github.com/woliveiras/palabrita), designed to evaluate runtime portability, failure taxonomy stability (F1–F5), and execution profiles of small language models (Qwen3 0.6B / LiteRT-LM) between Kotlin/Android ART and Dart/Flutter.

---

## Research Scope & Taxonomy Alignment

Following William Oliveira's paper *"Less Is More: On-Device Small Language Model Failure Modes on Android"*, this project replicates the defensive parsing, session management, and inference telemetry pipeline to evaluate failure modes across runtimes under identical model weights and prompt inputs.

### Failure Classification Taxonomy
* **`none`**: Clean success — output satisfies the canonical schema (`hints: h1 | h2 | h3`), yields $\ge 3$ distinct hints, and contains no lexical leakage of the target word.
* **`F1`**: Format violation (e.g., missing delimiter prefix, unparseable conversational greeting, unstructured prose).
* **`F2`**: Structural error (e.g., fewer than 3 hints, target word leaked inside a hint, invalid schema keys).
* **`F3`**: Context quality degradation (e.g., token/phrase repetition loops, multi-turn instruction drift, context degradation).
* **`F4`**: Latency incompatibility (inference latency exceeding the interactive real-time budget).
* **`F5`**: Resource exhaustion (out-of-memory or process termination).

---

## Architecture & Integration

* **Android Device Execution**: Flutter invokes a native Android bridge (`MainActivity.kt`) over `MethodChannel`, coordinating Google LiteRT-LM (`com.google.ai.edge.litertlm:litertlm-android:0.10.2`) with persistent native `Conversation` lifecycles across turns.
* **Headless Host Execution**: Low-level C FFI bindings (`dart:ffi`) to `liblitert_lm.so` with `NativeFinalizer` attachments and deterministic mock implementations support headless unit and integration testing.
* **Regex Engine**: Dart's `RegExp` implementation compiles via Irregexp using ECMAScript regular expression semantics with backtracking.

```
palabrita_flutter/
├── lib/
│   ├── benchmark/          # Benchmark runner, failure classifier, InferenceLogger (NDJSON/CSV)
│   ├── inference/          # LiteRT-LM bindings & InferenceEngine
│   ├── parser/             # Defensive parser ported from Kotlin
│   ├── prompt/             # PromptEngine & HintFallbackProvider
│   └── session/            # Session lifecycle manager & rotation triggers
├── assets/
│   └── test_prompts.json   # 30 fixed reproducible benchmark prompts
└── test/
    ├── benchmark_runner/   # Headless benchmark test suite
    ├── defensive_parser_test.dart
    ├── failure_classifier_test.dart
    ├── inference_engine_test.dart
    ├── inference_logger_test.dart
    ├── prompt_engine_test.dart
    ├── session_manager_test.dart
    └── widget_test.dart
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

## Telemetry & Logging

Benchmark executions record every turn before and after parsing into structured formats:

1. **NDJSON Log (`inference_log.ndjson`)**:
   Streaming newline-delimited JSON containing complete turn telemetry:
   ```json
   {
     "timestamp": "2026-10-18T12:00:00.000Z",
     "session_id": "palabrita_sess_1760700000000_1",
     "turn_number": 1,
     "raw_output": "hints: Hint 1 | Hint 2 | Hint 3",
     "parsed_output": "Hint 1 | Hint 2 | Hint 3",
     "parse_decision": "success",
     "failure_category": "none",
     "latency_ms": 142,
     "execution_mode": "hardware",
     "device_info": "TECNO CH7n - Android 12",
     "prompt_id": "p001",
     "word": "gatos",
     "language": "pt"
   }
   ```
2. **CSV Export (`inference_log.csv`)**:
   Exported via `InferenceLogger.exportToCSV()` for statistical aggregation.

---

## Experimental Protocol for Replication

To ensure scientific validity when comparing Dart/Flutter with Kotlin/Android:
1. Run both implementations on the **exact same physical Android device**.
2. Deploy identical model weights (`Qwen3-0.6B.litertlm`) and identical sampler parameters ($T=0.8, \text{top-}k=40, \text{top-}p=0.95$).
3. Use matched prompt sets, identical persistent conversation lifecycles, and identical evaluation criteria.

---

## License

This project is licensed under the **GNU Affero General Public License v3.0 (AGPL-3.0)**, matching upstream [Palabrita](https://github.com/woliveiras/palabrita).
