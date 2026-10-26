import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:palabrita_flutter/benchmark/failure_classifier.dart';
import 'package:palabrita_flutter/benchmark/inference_logger.dart';
import 'package:palabrita_flutter/inference/inference_engine.dart';
import 'package:palabrita_flutter/parser/defensive_parser.dart';
import 'package:palabrita_flutter/prompt/prompt_engine.dart';
import 'package:palabrita_flutter/session/session_manager.dart';

/// Representation of a benchmark test prompt item.
class TestPromptItem {
  final String id;
  final String word;
  final String language;
  final String expectedFormat;
  final String category;

  const TestPromptItem({
    required this.id,
    required this.word,
    required this.language,
    required this.expectedFormat,
    this.category = 'standard',
  });

  factory TestPromptItem.fromJson(Map<String, dynamic> json) {
    return TestPromptItem(
      id: json['id'] as String? ?? '',
      word: json['word'] as String? ?? '',
      language: json['language'] as String? ?? 'pt',
      expectedFormat: json['expected_format'] as String? ?? 'hints: hint 1 | hint 2 | hint 3',
      category: json['category'] as String? ?? 'standard',
    );
  }
}

/// Aggregated summary of a benchmark execution.
class BenchmarkSummary {
  final int totalRuns;
  final int successCount;
  final int f1Count;
  final int f2Count;
  final int f3Count;
  final int f4Count;
  final double meanLatencyMs;
  final String csvPath;

  const BenchmarkSummary({
    required this.totalRuns,
    required this.successCount,
    required this.f1Count,
    required this.f2Count,
    required this.f3Count,
    required this.f4Count,
    required this.meanLatencyMs,
    required this.csvPath,
  });

  void printSummaryTable() {
    final successRate = totalRuns > 0 ? (successCount / totalRuns * 100).toStringAsFixed(1) : '0.0';
    final f1Rate = totalRuns > 0 ? (f1Count / totalRuns * 100).toStringAsFixed(1) : '0.0';
    final f2Rate = totalRuns > 0 ? (f2Count / totalRuns * 100).toStringAsFixed(1) : '0.0';
    final f3Rate = totalRuns > 0 ? (f3Count / totalRuns * 100).toStringAsFixed(1) : '0.0';
    final f4Rate = totalRuns > 0 ? (f4Count / totalRuns * 100).toStringAsFixed(1) : '0.0';

    stdout.writeln('\n===============================================================');
    stdout.writeln('          PALABRITA FLUTTER BENCHMARK SUMMARY RESULTS           ');
    stdout.writeln('===============================================================');
    stdout.writeln(' Total Runs                        : $totalRuns');
    stdout.writeln(' Successes                         : $successCount ($successRate%)');
    stdout.writeln(' F1 (Format Violations)            : $f1Count ($f1Rate%)');
    stdout.writeln(' F2 (Structural Errors)            : $f2Count ($f2Rate%)');
    stdout.writeln(' F3 (Context Quality Degradation)  : $f3Count ($f3Rate%)');
    stdout.writeln(' F4 (Latency Incompatibility)      : $f4Count ($f4Rate%)');
    stdout.writeln(' Mean Latency                      : ${meanLatencyMs.toStringAsFixed(2)} ms');
    stdout.writeln(' Benchmark CSV Export              : $csvPath');
    stdout.writeln('===============================================================\n');
  }
}

/// Headless runner executing benchmark prompts against InferenceEngine and DefensiveParser.
class BenchmarkRunner {
  final InferenceEngine inferenceEngine;
  final DefensiveParser parser;
  final PromptEngine promptEngine;
  final InferenceLogger logger;
  final SessionManager sessionManager;

  BenchmarkRunner({
    required this.inferenceEngine,
    DefensiveParser? parser,
    PromptEngine? promptEngine,
    required this.logger,
    SessionManager? sessionManager,
  })  : parser = parser ?? DefensiveParser(),
        promptEngine = promptEngine ?? PromptEngine(),
        sessionManager = sessionManager ??
            SessionManager(
              logger: logger,
              onSessionReset: inferenceEngine.resetSession,
            );

  /// Loads prompts from [promptsPath] (defaults to `assets/test_prompts.json`).
  static Future<List<TestPromptItem>> loadPrompts({String promptsPath = 'assets/test_prompts.json'}) async {
    String content;
    final file = File(promptsPath);
    if (await file.exists()) {
      content = await file.readAsString();
    } else {
      content = await rootBundle.loadString(promptsPath);
    }
    final list = jsonDecode(content) as List<dynamic>;
    return list.map((e) => TestPromptItem.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Runs the full benchmark: executes all [prompts] for [runsPerPrompt] cycles.
  Future<BenchmarkSummary> run({
    List<TestPromptItem>? prompts,
    String promptsPath = 'assets/test_prompts.json',
    int runsPerPrompt = 5,
    String? outputCsvPath,
  }) async {
    final promptList = prompts ?? await loadPrompts(promptsPath: promptsPath);

    int totalRuns = 0;
    int successCount = 0;
    int f1Count = 0;
    int f2Count = 0;
    int f3Count = 0;
    int f4Count = 0;
    int totalLatencyMs = 0;

    await sessionManager.startSession(reason: 'Benchmark session started');

    int turnCounter = 0;

    for (final promptItem in promptList) {
      final sysPrompt = promptEngine.hintSystemPrompt(promptItem.language);
      final userPrompt = promptEngine.hintUserPrompt(promptItem.word, promptItem.language);

      for (var runIdx = 1; runIdx <= runsPerPrompt; runIdx++) {
        turnCounter++;
        totalRuns++;

        // 1. Run inference
        final inferenceResult = await inferenceEngine.generateSingleTurn(
          systemPrompt: sysPrompt,
          userPrompt: userPrompt,
        );

        final rawOutput = inferenceResult.text;
        final latencyMs = inferenceResult.latencyMs;
        totalLatencyMs += latencyMs;

        // 2. Defensive parsing
        final parseResult = parser.parseHints(rawOutput);

        // 3. Unified evaluation according to "Less Is More" taxonomy
        final eval = FailureClassifier.evaluate(
          rawOutput: rawOutput,
          parseResult: parseResult,
          targetWord: promptItem.word,
          latencyMs: latencyMs,
          consecutiveFailures: sessionManager.consecutiveFailures,
        );

        switch (eval.category) {
          case FailureCategory.none:
            successCount++;
            break;
          case FailureCategory.F1:
            f1Count++;
            break;
          case FailureCategory.F2:
            f2Count++;
            break;
          case FailureCategory.F3:
            f3Count++;
            break;
          case FailureCategory.F4:
            f4Count++;
            break;
          case FailureCategory.F5:
            break;
        }

        // 4. Log to InferenceLogger BEFORE next operation
        await logger.logInference(
          sessionId: sessionManager.currentSessionId,
          turnNumber: turnCounter,
          rawOutput: rawOutput,
          parsedOutput: eval.parsedText,
          parseDecision: eval.decision,
          failureCategory: eval.category,
          latencyMs: latencyMs,
          executionMode: inferenceEngine.executionMode,
          metadata: {
            'prompt_id': promptItem.id,
            'word': promptItem.word,
            'language': promptItem.language,
            'run_index': runIdx,
            'prompt_category': promptItem.category,
          },
        );

        // 5. Update session manager turn
        await sessionManager.recordTurn(
          isSuccess: eval.decision == ParseDecision.success,
          failureReason: eval.category != FailureCategory.none ? eval.category.name : null,
        );
      }
    }

    await sessionManager.endSession(reason: 'Benchmark completed');

    // 6. Export to CSV
    final csvFile = await logger.exportToCSV(customCsvPath: outputCsvPath);

    final summary = BenchmarkSummary(
      totalRuns: totalRuns,
      successCount: successCount,
      f1Count: f1Count,
      f2Count: f2Count,
      f3Count: f3Count,
      f4Count: f4Count,
      meanLatencyMs: totalRuns > 0 ? totalLatencyMs / totalRuns : 0.0,
      csvPath: csvFile.path,
    );

    summary.printSummaryTable();
    return summary;
  }
}
