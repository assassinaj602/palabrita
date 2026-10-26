import 'package:palabrita_flutter/benchmark/inference_logger.dart';

/// Configuration for session lifecycle management.
class SessionConfig {
  final int maxTurnsPerSession;
  final int maxConsecutiveFailures;

  const SessionConfig({
    this.maxTurnsPerSession = 10,
    this.maxConsecutiveFailures = 5,
  });
}

/// Manages the LLM inference session lifecycle, turn tracking, KV-cache
/// rotation triggers, and failure degradation handling.
class SessionManager {
  final InferenceLogger logger;
  final SessionConfig config;
  final Future<void> Function()? onSessionReset;

  String _currentSessionId = '';
  int _turnCount = 0;
  int _consecutiveFailures = 0;
  int _totalFailures = 0;
  bool _isActive = false;
  String? _lastRotationReason;
  int _sessionSequence = 0;

  SessionManager({
    required this.logger,
    this.config = const SessionConfig(),
    this.onSessionReset,
  });

  String get currentSessionId => _currentSessionId;
  int get currentTurnCount => _turnCount;
  int get consecutiveFailures => _consecutiveFailures;
  bool get isActive => _isActive;
  String? get lastRotationReason => _lastRotationReason;

  /// Starts a new inference session.
  Future<String> startSession({
    String? customSessionId,
    String reason = 'Session initialized',
  }) async {
    if (_isActive) {
      await endSession(reason: 'Rotating into new session');
    }

    _sessionSequence++;
    _currentSessionId = customSessionId ??
        'palabrita_sess_${DateTime.now().millisecondsSinceEpoch}_$_sessionSequence';
    _turnCount = 0;
    _consecutiveFailures = 0;
    _totalFailures = 0;
    _isActive = true;
    _lastRotationReason = null;

    await onSessionReset?.call();

    await logger.logSessionEvent(
      sessionId: _currentSessionId,
      turnCount: _turnCount,
      event: SessionEvent.SESSION_START,
      reason: reason,
    );

    return _currentSessionId;
  }

  /// Records the result of an inference turn.
  /// Automatically checks if rotation is needed due to turn limits or failure thresholds.
  Future<bool> recordTurn({
    required bool isSuccess,
    String? failureReason,
  }) async {
    if (!_isActive) {
      await startSession();
    }

    _turnCount++;

    if (isSuccess) {
      _consecutiveFailures = 0;
    } else {
      _consecutiveFailures++;
      _totalFailures++;
    }

    // Check if session reached turn limit
    if (_turnCount >= config.maxTurnsPerSession) {
      await rotateSession(
        event: SessionEvent.ROTATION_BY_TURN_LIMIT,
        reason: 'Session reached turn limit of ${config.maxTurnsPerSession}',
      );
      return false; // rotated
    }

    // Check if session reached consecutive failure threshold (F3 / context degradation)
    if (_consecutiveFailures >= config.maxConsecutiveFailures) {
      await rotateSession(
        event: SessionEvent.ROTATION_BY_FAILURE,
        reason: failureReason ??
            'Exceeded max consecutive failures (${config.maxConsecutiveFailures}): F3 context degradation',
      );
      return false; // rotated
    }

    return true; // current session continues
  }

  /// Manually or automatically rotates the session.
  Future<String> rotateSession({
    required SessionEvent event,
    required String reason,
  }) async {
    _lastRotationReason = reason;

    await logger.logSessionEvent(
      sessionId: _currentSessionId,
      turnCount: _turnCount,
      event: event,
      reason: reason,
    );

    await endSession(reason: reason, skipEventLog: true);
    return startSession(reason: 'Rotated: $reason');
  }

  /// Ends the current active session.
  Future<void> endSession({
    String reason = 'Session ended',
    bool skipEventLog = false,
  }) async {
    if (!_isActive) return;

    await onSessionReset?.call();

    if (!skipEventLog) {
      await logger.logSessionEvent(
        sessionId: _currentSessionId,
        turnCount: _turnCount,
        event: SessionEvent.SESSION_END,
        reason: reason,
      );
    }

    _isActive = false;
  }

  /// Returns stats for the active or most recent session.
  SessionStats currentSessionStats() {
    return SessionStats(
      sessionId: _currentSessionId,
      turnCount: _turnCount,
      failureCount: _totalFailures,
      lastRotationReason: _lastRotationReason,
    );
  }
}
