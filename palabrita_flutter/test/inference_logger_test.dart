import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:palabrita_flutter/palabrita_flutter.dart';

void main() {
  late Directory tempDir;
  late File logFile;
  late InferenceLogger logger;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('palabrita_logger_test_');
    logFile = File('${tempDir.path}/test_inference.ndjson');
    logger = InferenceLogger(
      deviceInfo: 'TestDevice Android 14',
      logFile: logFile,
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('logs inference turn correctly to NDJSON', () async {
    await logger.logInference(
      sessionId: 'sess-001',
      turnNumber: 1,
      rawOutput: '```json\n{"hint": "A fruit"}\n```',
      parsedOutput: '{"hint": "A fruit"}',
      parseDecision: ParseDecision.success,
      failureCategory: FailureCategory.none,
      latencyMs: 142,
      gcPauseEstimateUs: 15,
    );

    expect(await logFile.exists(), isTrue);
    final lines = await logFile.readAsLines();
    expect(lines.length, equals(1));

    final json = jsonDecode(lines.first) as Map<String, dynamic>;
    expect(json['session_id'], equals('sess-001'));
    expect(json['turn_number'], equals(1));
    expect(json['raw_output'], equals('```json\n{"hint": "A fruit"}\n```'));
    expect(json['parsed_output'], equals('{"hint": "A fruit"}'));
    expect(json['parse_decision'], equals('success'));
    expect(json['failure_category'], equals('none'));
    expect(json['latency_ms'], equals(142));
    expect(json['gc_pause_estimate_us'], equals(15));
    expect(json['device_info'], equals('TestDevice Android 14'));
    expect(json['timestamp'], isNotEmpty);
  });

  test('tracks session statistics across failures and rotations', () async {
    await logger.logSessionEvent(
      sessionId: 'sess-002',
      turnCount: 0,
      event: SessionEvent.SESSION_START,
      reason: 'initialization',
    );

    var stats = logger.currentSessionStats();
    expect(stats.sessionId, equals('sess-002'));
    expect(stats.turnCount, equals(0));
    expect(stats.failureCount, equals(0));

    // Turn 1: success
    await logger.logInference(
      sessionId: 'sess-002',
      turnNumber: 1,
      rawOutput: '{"hint":"test"}',
      parsedOutput: '{"hint":"test"}',
      parseDecision: ParseDecision.success,
      failureCategory: FailureCategory.none,
      latencyMs: 100,
    );

    // Turn 2: F1 failure
    await logger.logInference(
      sessionId: 'sess-002',
      turnNumber: 2,
      rawOutput: 'No json here',
      parsedOutput: '',
      parseDecision: ParseDecision.failure,
      failureCategory: FailureCategory.F1,
      latencyMs: 200,
    );

    stats = logger.currentSessionStats();
    expect(stats.turnCount, equals(2));
    expect(stats.failureCount, equals(1));

    // Trigger rotation by failure
    await logger.logSessionEvent(
      sessionId: 'sess-002',
      turnCount: 2,
      event: SessionEvent.ROTATION_BY_FAILURE,
      reason: 'F1 format violation detected',
    );

    stats = logger.currentSessionStats();
    expect(stats.lastRotationReason, equals('F1 format violation detected'));
  });

  test('exports NDJSON to CSV correctly', () async {
    await logger.logInference(
      sessionId: 'sess-csv',
      turnNumber: 1,
      rawOutput: 'raw1',
      parsedOutput: 'parsed1',
      parseDecision: ParseDecision.success,
      failureCategory: FailureCategory.none,
      latencyMs: 50,
      gcPauseEstimateUs: 10,
    );

    await logger.logInference(
      sessionId: 'sess-csv',
      turnNumber: 2,
      rawOutput: 'raw2',
      parsedOutput: 'parsed2',
      parseDecision: ParseDecision.fallback,
      failureCategory: FailureCategory.F2,
      latencyMs: 80,
      gcPauseEstimateUs: 20,
    );

    final csvFile = File('${tempDir.path}/test_export.csv');
    final exported = await logger.exportToCSV(targetCsvFile: csvFile);

    expect(await exported.exists(), isTrue);
    final csvLines = await exported.readAsLines();

    // Line 1: Header
    expect(csvLines[0], equals(InferenceLogger.csvHeaders.join(',')));
    // Line 2: Turn 1
    expect(csvLines[1], contains('sess-csv'));
    expect(csvLines[1], contains('raw1'));
    expect(csvLines[1], contains('success'));
    expect(csvLines[1], contains('none'));
    // Line 3: Turn 2
    expect(csvLines[2], contains('sess-csv'));
    expect(csvLines[2], contains('raw2'));
    expect(csvLines[2], contains('fallback'));
    expect(csvLines[2], contains('F2'));
  });

  test('estimateGcPauseUs runs and returns a non-negative duration', () {
    final pauseUs = InferenceLogger.estimateGcPauseUs();
    expect(pauseUs, greaterThanOrEqualTo(0));
  });
}

