import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:palabrita_flutter/palabrita_flutter.dart';

void main() {
  late Directory tempDir;
  late File logFile;
  late InferenceLogger logger;
  late SessionManager sessionManager;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('palabrita_session_test_');
    logFile = File('${tempDir.path}/session_log.ndjson');
    logger = InferenceLogger(
      deviceInfo: 'TestDevice Android 14',
      logFile: logFile,
    );
    sessionManager = SessionManager(
      logger: logger,
      config: const SessionConfig(
        maxTurnsPerSession: 3,
        maxConsecutiveFailures: 2,
      ),
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('SessionManager - Task 2.4 Unit Tests', () {
    test('initializes and starts session, logging SESSION_START', () async {
      final sessId = await sessionManager.startSession(customSessionId: 'sess_100');
      expect(sessId, equals('sess_100'));
      expect(sessionManager.isActive, isTrue);
      expect(sessionManager.currentTurnCount, equals(0));

      final stats = sessionManager.currentSessionStats();
      expect(stats.sessionId, equals('sess_100'));
      expect(stats.turnCount, equals(0));
      expect(stats.failureCount, equals(0));

      final lines = await logFile.readAsLines();
      expect(lines.length, equals(1));
      expect(lines.first, contains('SESSION_START'));
    });

    test('rotates session when turn limit is reached', () async {
      await sessionManager.startSession(customSessionId: 'sess_turns');

      // Turn 1
      var continues = await sessionManager.recordTurn(isSuccess: true);
      expect(continues, isTrue);
      expect(sessionManager.currentTurnCount, equals(1));

      // Turn 2
      continues = await sessionManager.recordTurn(isSuccess: true);
      expect(continues, isTrue);
      expect(sessionManager.currentTurnCount, equals(2));

      // Turn 3: reaches maxTurnsPerSession (3) -> triggers rotation
      continues = await sessionManager.recordTurn(isSuccess: true);
      expect(continues, isFalse); // rotated

      // A new session has begun
      expect(sessionManager.currentSessionId, isNot(equals('sess_turns')));
      expect(sessionManager.currentTurnCount, equals(0));

      final lines = await logFile.readAsLines();
      expect(lines.any((l) => l.contains('ROTATION_BY_TURN_LIMIT')), isTrue);
    });

    test('rotates session when consecutive failures exceed threshold', () async {
      await sessionManager.startSession(customSessionId: 'sess_fails');

      // Failure 1
      var continues = await sessionManager.recordTurn(isSuccess: false, failureReason: 'F1');
      expect(continues, isTrue);
      expect(sessionManager.consecutiveFailures, equals(1));

      // Failure 2: reaches maxConsecutiveFailures (2) -> triggers rotation
      continues = await sessionManager.recordTurn(isSuccess: false, failureReason: 'F1 format violation');
      expect(continues, isFalse); // rotated

      expect(sessionManager.currentSessionId, isNot(equals('sess_fails')));
      final lines = await logFile.readAsLines();
      expect(lines.any((l) => l.contains('ROTATION_BY_FAILURE')), isTrue);
    });

    test('success turn resets consecutive failures count', () async {
      await sessionManager.startSession();

      await sessionManager.recordTurn(isSuccess: false);
      expect(sessionManager.consecutiveFailures, equals(1));

      // Success turn resets consecutive count
      await sessionManager.recordTurn(isSuccess: true);
      expect(sessionManager.consecutiveFailures, equals(0));
    });

    test('endSession logs SESSION_END and sets isActive to false', () async {
      await sessionManager.startSession(customSessionId: 'sess_end');
      await sessionManager.endSession();

      expect(sessionManager.isActive, isFalse);
      final lines = await logFile.readAsLines();
      expect(lines.any((l) => l.contains('SESSION_END')), isTrue);
    });
  });
}

