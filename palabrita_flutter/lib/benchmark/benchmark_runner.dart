import 'dart:convert';
import 'dart:io';

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
  final int f4Count;
  final double meanLatencyMs;
  final double meanGcPauseUs;
  final String csvPath;

  const BenchmarkSummary({
    required this.totalRuns,
    required this.successCount,
    required this.f1Count,
    required this.f2Count,
    required this.f4Count,
    required this.meanLatencyMs,
    required this.meanGcPauseUs,
    required this.csvPath,
  });

  void printSummaryTable() {
    final successRate = totalRuns > 0 ? (successCount / totalRuns * 100).toStringAsFixed(1) : '0.0';
    final f1Rate = totalRuns > 0 ? (f1Count / totalRuns * 100).toStringAsFixed(1) : '0.0';
    final f2Rate = totalRuns > 0 ? (f2Count / totalRuns * 100).toStringAsFixed(1) : '0.0';
    final f4Rate = totalRuns > 0 ? (f4Count / totalRuns * 100).toStringAsFixed(1) : '0.0';

    stdout.writeln('\n===============================================================');
    stdout.writeln('          PALABRITA FLUTTER BENCHMARK SUMMARY RESULTS           ');
    stdout.writeln('===============================================================');
    stdout.writeln(' Total Runs               : $totalRuns');
    stdout.writeln(' Successes                : $successCount ($successRate%)');
    stdout.writeln(' F1 (Format Violations)   : $f1Count ($f1Rate%)');
    stdout.writeln(' F2 (Structural Errors)   : $f2Count ($f2Rate%)');
    stdout.writeln(' F4 (Session Degradation) : $f4Count ($f4Rate%)');
    stdout.writeln(' Mean Latency             : ${meanLatencyMs.toStringAsFixed(2)} ms');
    stdout.writeln(' Mean GC Pause Estimate   : ${meanGcPauseUs.toStringAsFixed(2)} µs');
    stdout.writeln(' Benchmark CSV Export     : $csvPath');
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
        sessionManager = sessionManager ?? SessionManager(logger: logger);

  /// Loads prompts from [promptsPath] (defaults to `assets/test_prompts.json`).
  static Future<List<TestPromptItem>> loadPrompts({String promptsPath = 'assets/test_prompts.json'}) async {
    final file = File(promptsPath);
    if (!await file.exists()) {
      throw FileSystemException('Prompts file not found at $promptsPath');
    }
    final content = await file.readAsString();
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
    int f4Count = 0;
    int totalLatencyMs = 0;
    int totalGcPauseUs = 0;

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
        final gcPauseUs = inferenceResult.gcPauseEstimateUs;

        totalLatencyMs += latencyMs;
        totalGcPauseUs += gcPauseUs;

        // 2. Defensive parsing
        final parseResult = parser.parseHints(rawOutput);

        ParseDecision decision;
        FailureCategory failureCat;
        String parsedString = '';

        if (parseResult is ParseSuccess<List<String>>) {
          final hints = parseResult.data;
          parsedString = hints.join(' | ');

          // Validate target word leakage
          final wordLower = promptItem.word.toLowerCase();
          final leaksWord = hints.any((h) => h.toLowerCase().contains(wordLower));

          if (leaksWord) {
            decision = ParseDecision.failure;
            failureCat = FailureCategory.F2; // Structural failure: leaks target word
            f2Count++;
          } else {
            decision = ParseDecision.success;
            failureCat = FailureCategory.none;
            successCount++;
          }
        } else {
          decision = ParseDecision.failure;

          // Categorize failure according to "Less Is More" taxonomy
          if (sessionManager.consecutiveFailures >= 3 || rawOutput.contains(rawOutput.substring(0, (rawOutput.length / 2).floor()).trim())) {
            failureCat = FailureCategory.F4; // Session / repetition degradation
            f4Count++;
          } else if (rawOutput.contains(':') && rawOutput.contains('|')) {
            failureCat = FailureCategory.F2; // Structural failure
            f2Count++;
          } else {
            failureCat = FailureCategory.F1; // Format violation
            f1Count++;
          }
        }

        // 3. Log to InferenceLogger BEFORE next operation
        await logger.logInference(
          sessionId: sessionManager.currentSessionId,
          turnNumber: turnCounter,
          rawOutput: rawOutput,
          parsedOutput: parsedString,
          parseDecision: decision,
          failureCategory: failureCat,
          latencyMs: latencyMs,
          gcPauseEstimateUs: gcPauseUs,
          metadata: {
            'prompt_id': promptItem.id,
            'word': promptItem.word,
            'language': promptItem.language,
            'run_index': runIdx,
            'prompt_category': promptItem.category,
          },
        );

        // 4. Update session manager turn
        await sessionManager.recordTurn(
          isSuccess: decision == ParseDecision.success,
          failureReason: failureCat != FailureCategory.none ? failureCat.name : null,
        );
      }
    }

    await sessionManager.endSession(reason: 'Benchmark completed');

    // 5. Export to CSV
    final csvFile = await logger.exportToCSV(customCsvPath: outputCsvPath);

    final summary = BenchmarkSummary(
      totalRuns: totalRuns,
      successCount: successCount,
      f1Count: f1Count,
      f2Count: f2Count,
      f4Count: f4Count,
      meanLatencyMs: totalRuns > 0 ? totalLatencyMs / totalRuns : 0.0,
      meanGcPauseUs: totalRuns > 0 ? totalGcPauseUs / totalRuns : 0.0,
      csvPath: csvFile.path,
    );

    summary.printSummaryTable();
    return summary;
  }
}
