import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:palabrita_flutter/palabrita_flutter.dart';

void main() {
  test('Palabrita Headless Benchmark Runner', () async {
    // Determine output directory for benchmark logs
    final tempDir = await Directory.systemTemp.createTemp('palabrita_benchmark_run_');
    final logFile = File('${tempDir.path}/inference_log.ndjson');
    final csvPath = '${tempDir.path}/inference_log.csv';

    final logger = InferenceLogger(
      deviceInfo: 'Benchmark Runner Test Host (${Platform.operatingSystem})',
      logFile: logFile,
    );

    // Initialize inference engine (opens native liblitert_lm.so if available, otherwise mock)
    final bindings = LiteRtLmBindings.open();
    final engine = InferenceEngine(bindings: bindings);

    await engine.initialize(modelPath: '/dummy/path/qwen3_0_6b.bin');

    final runner = BenchmarkRunner(
      inferenceEngine: engine,
      logger: logger,
    );

    // Run benchmark (loads assets/test_prompts.json)
    // Runs 2 passes in test mode for rapid validation, configurable to 5+ for full benchmark
    const promptsFile = 'assets/test_prompts.json';
    final summary = await runner.run(
      promptsPath: promptsFile,
      runsPerPrompt: 2,
      outputCsvPath: csvPath,
    );

    expect(summary.totalRuns, equals(60)); // 30 prompts * 2 runs
    expect(summary.meanLatencyMs, greaterThanOrEqualTo(0));
    expect(summary.meanGcPauseUs, greaterThanOrEqualTo(0));

    // Verify NDJSON log file
    expect(await logFile.exists(), isTrue);
    final ndjsonLines = await logFile.readAsLines();
    // 60 inference turns + session events (SESSION_START, rotations, SESSION_END)
    expect(ndjsonLines.length, greaterThanOrEqualTo(60));

    // Verify CSV export
    final exportedCsv = File(csvPath);
    expect(await exportedCsv.exists(), isTrue);
    final csvLines = await exportedCsv.readAsLines();
    expect(csvLines.first, equals(InferenceLogger.csvHeaders.join(',')));
    expect(csvLines.length, equals(61)); // header + 60 turns

    engine.dispose();
  });
}

