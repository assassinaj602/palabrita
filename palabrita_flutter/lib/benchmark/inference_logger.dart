// ignore_for_file: constant_identifier_names

import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';

/// Parse decision made by the defensive parser.
enum ParseDecision {
  success,
  fallback,
  failure;

  String toJson() => name;

  static ParseDecision fromJson(String value) {
    return ParseDecision.values.firstWhere(
      (e) => e.name.toLowerCase() == value.toLowerCase(),
      orElse: () => ParseDecision.failure,
    );
  }
}

/// Failure category taxonomy from the "Less Is More" paper.
enum FailureCategory {
  F1, // Format violation
  F2, // Structural error
  F4, // Session / KV cache degradation
  none;

  String toJson() => name;

  static FailureCategory fromJson(String value) {
    return FailureCategory.values.firstWhere(
      (e) => e.name.toUpperCase() == value.toUpperCase(),
      orElse: () => FailureCategory.none,
    );
  }
}

/// Session lifecycle events for tracking session rotation and triggers.
enum SessionEvent {
  SESSION_START,
  SESSION_END,
  ROTATION_BY_TURN_LIMIT,
  ROTATION_BY_FAILURE;

  String toJson() => name;

  static SessionEvent fromJson(String value) {
    return SessionEvent.values.firstWhere(
      (e) => e.name.toUpperCase() == value.toUpperCase(),
      orElse: () => SessionEvent.SESSION_START,
    );
  }
}

/// Structured log entry for an individual inference turn.
class InferenceLogEntry {
  final DateTime timestamp;
  final String sessionId;
  final int turnNumber;
  final String rawOutput;
  final String parsedOutput;
  final ParseDecision parseDecision;
  final FailureCategory failureCategory;
  final int latencyMs;
  final int gcPauseEstimateUs;
  final String deviceInfo;
  final Map<String, dynamic>? metadata;

  InferenceLogEntry({
    DateTime? timestamp,
    required this.sessionId,
    required this.turnNumber,
    required this.rawOutput,
    required this.parsedOutput,
    required this.parseDecision,
    required this.failureCategory,
    required this.latencyMs,
    required this.gcPauseEstimateUs,
    required this.deviceInfo,
    this.metadata,
  }) : timestamp = timestamp ?? DateTime.now().toUtc();

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'session_id': sessionId,
        'turn_number': turnNumber,
        'raw_output': rawOutput,
        'parsed_output': parsedOutput,
        'parse_decision': parseDecision.toJson(),
        'failure_category': failureCategory.toJson(),
        'latency_ms': latencyMs,
        'gc_pause_estimate_us': gcPauseEstimateUs,
        'device_info': deviceInfo,
        ...?metadata,
      };

  factory InferenceLogEntry.fromJson(Map<String, dynamic> json) {
    return InferenceLogEntry(
      timestamp: DateTime.parse(json['timestamp'] as String),
      sessionId: json['session_id'] as String,
      turnNumber: json['turn_number'] as int,
      rawOutput: json['raw_output'] as String? ?? '',
      parsedOutput: json['parsed_output'] as String? ?? '',
      parseDecision: ParseDecision.fromJson(json['parse_decision'] as String),
      failureCategory:
          FailureCategory.fromJson(json['failure_category'] as String),
      latencyMs: json['latency_ms'] as int? ?? 0,
      gcPauseEstimateUs: json['gc_pause_estimate_us'] as int? ?? 0,
      deviceInfo: json['device_info'] as String? ?? '',
    );
  }
}

/// Structured log entry for session lifecycle events.
class SessionLogEntry {
  final DateTime timestamp;
  final String sessionId;
  final int turnCount;
  final SessionEvent event;
  final String reason;
  final String deviceInfo;

  SessionLogEntry({
    DateTime? timestamp,
    required this.sessionId,
    required this.turnCount,
    required this.event,
    required this.reason,
    required this.deviceInfo,
  }) : timestamp = timestamp ?? DateTime.now().toUtc();

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'event_type': 'session_event',
        'session_id': sessionId,
        'turn_count': turnCount,
        'event': event.toJson(),
        'reason': reason,
        'device_info': deviceInfo,
      };

  factory SessionLogEntry.fromJson(Map<String, dynamic> json) {
    return SessionLogEntry(
      timestamp: DateTime.parse(json['timestamp'] as String),
      sessionId: json['session_id'] as String,
      turnCount: json['turn_count'] as int? ?? 0,
      event: SessionEvent.fromJson(json['event'] as String),
      reason: json['reason'] as String? ?? '',
      deviceInfo: json['device_info'] as String? ?? '',
    );
  }
}

/// Statistics for the active session.
class SessionStats {
  final String sessionId;
  final int turnCount;
  final int failureCount;
  final String? lastRotationReason;

  const SessionStats({
    required this.sessionId,
    required this.turnCount,
    required this.failureCount,
    this.lastRotationReason,
  });

  Map<String, dynamic> toJson() => {
        'session_id': sessionId,
        'turn_count': turnCount,
        'failure_count': failureCount,
        'last_rotation_reason': lastRotationReason,
      };

  @override
  String toString() =>
      'SessionStats(sessionId: $sessionId, turnCount: $turnCount, failureCount: $failureCount, lastRotationReason: $lastRotationReason)';
}

/// Structured logger that records inference turns and session events to NDJSON,
/// and exports them to CSV for failure rate analysis.
class InferenceLogger {
  static const List<String> csvHeaders = [
    'timestamp',
    'session_id',
    'turn_number',
    'raw_output',
    'parsed_output',
    'parse_decision',
    'failure_category',
    'latency_ms',
    'gc_pause_estimate_us',
    'device_info',
  ];

  final String deviceInfo;
  final File? _customLogFile;
  File? _resolvedLogFile;

  String _currentSessionId = '';
  int _currentSessionTurnCount = 0;
  int _currentSessionFailureCount = 0;
  String? _lastRotationReason;

  InferenceLogger({
    String? deviceInfo,
    File? logFile,
    String? customLogPath,
  })  : deviceInfo = deviceInfo ?? _defaultDeviceInfo(),
        _customLogFile = customLogPath != null ? File(customLogPath) : logFile;

  static String _defaultDeviceInfo() {
    return '${Platform.operatingSystem} ${Platform.operatingSystemVersion} (Dart ${Platform.version.split(' ').first})';
  }

  /// Estimates GC pause in microseconds using Dart's Timeline API and a quick allocation probe.
  static int estimateGcPauseUs() {
    final stopwatch = Stopwatch()..start();
    developer.Timeline.timeSync('InferenceGCProbe', () {
      final probe = List<int?>.filled(10000, 0);
      probe[0] = null;
    });
    stopwatch.stop();
    return stopwatch.elapsedMicroseconds;
  }

  /// Resolves the NDJSON log file. Defaults to `getApplicationDocumentsDirectory()/inference_log.ndjson`.
  Future<File> getLogFile() async {
    final custom = _customLogFile;
    if (custom != null) return custom;
    final resolved = _resolvedLogFile;
    if (resolved != null) return resolved;
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/inference_log.ndjson');
    _resolvedLogFile = file;
    return file;
  }

  /// Logs a raw [InferenceLogEntry] to the NDJSON file.
  Future<void> logEntry(InferenceLogEntry entry) async {
    _currentSessionId = entry.sessionId;
    _currentSessionTurnCount = entry.turnNumber;
    if (entry.parseDecision == ParseDecision.failure ||
        entry.failureCategory != FailureCategory.none) {
      _currentSessionFailureCount++;
    }

    final file = await getLogFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(
      '${jsonEncode(entry.toJson())}\n',
      mode: FileMode.append,
      flush: true,
    );
  }

  /// Convenience method to log an inference turn.
  Future<void> logInference({
    required String sessionId,
    required int turnNumber,
    required String rawOutput,
    required String parsedOutput,
    required ParseDecision parseDecision,
    required FailureCategory failureCategory,
    required int latencyMs,
    int? gcPauseEstimateUs,
    Map<String, dynamic>? metadata,
  }) async {
    final gcEstimate = gcPauseEstimateUs ?? estimateGcPauseUs();
    final entry = InferenceLogEntry(
      sessionId: sessionId,
      turnNumber: turnNumber,
      rawOutput: rawOutput,
      parsedOutput: parsedOutput,
      parseDecision: parseDecision,
      failureCategory: failureCategory,
      latencyMs: latencyMs,
      gcPauseEstimateUs: gcEstimate,
      deviceInfo: deviceInfo,
      metadata: metadata,
    );
    await logEntry(entry);
  }

  /// Logs a session lifecycle event (start, end, or rotation trigger).
  Future<void> logSessionEvent({
    required String sessionId,
    required int turnCount,
    required SessionEvent event,
    required String reason,
  }) async {
    _currentSessionId = sessionId;
    _currentSessionTurnCount = turnCount;

    if (event == SessionEvent.SESSION_START) {
      _currentSessionFailureCount = 0;
      _lastRotationReason = null;
    } else if (event == SessionEvent.ROTATION_BY_TURN_LIMIT ||
        event == SessionEvent.ROTATION_BY_FAILURE) {
      _lastRotationReason = reason;
    }

    final entry = SessionLogEntry(
      sessionId: sessionId,
      turnCount: turnCount,
      event: event,
      reason: reason,
      deviceInfo: deviceInfo,
    );

    final file = await getLogFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(
      '${jsonEncode(entry.toJson())}\n',
      mode: FileMode.append,
      flush: true,
    );
  }

  /// Returns stats for the current session.
  SessionStats currentSessionStats() {
    return SessionStats(
      sessionId: _currentSessionId,
      turnCount: _currentSessionTurnCount,
      failureCount: _currentSessionFailureCount,
      lastRotationReason: _lastRotationReason,
    );
  }

  /// Exports all inference turns from the NDJSON log to CSV for analysis.
  /// If [customCsvPath] or [targetCsvFile] is provided, writes to that path;
  /// otherwise saves as `inference_log.csv` in the same directory as the NDJSON file.
  Future<File> exportToCSV({
    File? targetCsvFile,
    String? customCsvPath,
  }) async {
    final logFile = await getLogFile();
    File csvFile;
    if (customCsvPath != null) {
      csvFile = File(customCsvPath);
    } else if (targetCsvFile != null) {
      csvFile = targetCsvFile;
    } else {
      final parent = logFile.parent;
      csvFile = File('${parent.path}/inference_log.csv');
    }

    await csvFile.parent.create(recursive: true);

    if (!await logFile.exists()) {
      final emptyCsv = const CsvEncoder(lineDelimiter: '\n').convert([csvHeaders]);
      await csvFile.writeAsString('$emptyCsv\n');
      return csvFile;
    }

    final lines = await logFile.readAsLines();
    final rows = <List<dynamic>>[csvHeaders];

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      try {
        final json = jsonDecode(trimmed) as Map<String, dynamic>;
        // Include entries that represent inference turns
        if (json.containsKey('session_id') && json.containsKey('raw_output')) {
          rows.add([
            json['timestamp'] ?? '',
            json['session_id'] ?? '',
            json['turn_number'] ?? '',
            json['raw_output'] ?? '',
            json['parsed_output'] ?? '',
            json['parse_decision'] ?? '',
            json['failure_category'] ?? '',
            json['latency_ms'] ?? '',
            json['gc_pause_estimate_us'] ?? '',
            json['device_info'] ?? '',
          ]);
        }
      } catch (_) {
        // Skip malformed entries
      }
    }

    final csvData = const CsvEncoder(lineDelimiter: '\n').convert(rows);
    await csvFile.writeAsString('$csvData\n');
    return csvFile;
  }
}

