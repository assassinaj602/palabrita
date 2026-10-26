import 'package:palabrita_flutter/benchmark/inference_logger.dart';
import 'package:palabrita_flutter/parser/defensive_parser.dart';

/// Unified failure classification logic following the "Less Is More" taxonomy:
/// - F1: Format Violation
/// - F2: Structural Error
/// - F3: Context Quality Degradation (hallucination, repetition loop, multi-turn drift)
/// - F4: Latency Incompatibility
/// - F5: Resource Exhaustion
class FailureClassifier {
  /// Checks if the text exhibits token or phrase repetition loops.
  static bool isRepetitionLoop(String text) {
    final trimmed = text.trim();
    if (trimmed.length < 15) return false;

    // Scan for repeating substrings of length 4 to 40 repeating consecutively >= 3 times
    for (int len = 4; len <= 40 && len * 3 <= trimmed.length; len++) {
      for (int i = 0; i <= trimmed.length - len * 3; i++) {
        final pattern = trimmed.substring(i, i + len);
        if (pattern.trim().isEmpty) continue;
        final repeatPattern = pattern + pattern + pattern;
        if (trimmed.contains(repeatPattern)) {
          return true;
        }
      }
    }
    return false;
  }

  /// Evaluates model output and parsed result, returning the appropriate [FailureCategory] and [ParseDecision].
  static ({FailureCategory category, ParseDecision decision, String parsedText}) evaluate({
    required String rawOutput,
    required ParseResult<List<String>> parseResult,
    required String targetWord,
    int latencyMs = 0,
    int latencyThresholdMs = 30000,
    int consecutiveFailures = 0,
  }) {
    if (parseResult is ParseSuccess<List<String>>) {
      final hints = parseResult.data;
      final parsedString = hints.join(' | ');

      // Check for target word leakage
      final wordLower = targetWord.trim().toLowerCase();
      final leaksWord = wordLower.isNotEmpty &&
          hints.any((h) => h.toLowerCase().contains(wordLower));

      if (leaksWord) {
        return (
          category: FailureCategory.F2,
          decision: ParseDecision.failure,
          parsedText: parsedString,
        );
      }

      if (hints.length < 3) {
        return (
          category: FailureCategory.F2,
          decision: ParseDecision.failure,
          parsedText: parsedString,
        );
      }

      // Check latency budget if specified
      if (latencyThresholdMs > 0 && latencyMs > latencyThresholdMs) {
        return (
          category: FailureCategory.F4,
          decision: ParseDecision.success,
          parsedText: parsedString,
        );
      }

      return (
        category: FailureCategory.none,
        decision: ParseDecision.success,
        parsedText: parsedString,
      );
    }

    // Parse failed: categorize failure mode
    if (isRepetitionLoop(rawOutput)) {
      return (
        category: FailureCategory.F3,
        decision: ParseDecision.failure,
        parsedText: '',
      );
    }

    // If inside a persistent multi-turn session with accumulating context degradation
    if (consecutiveFailures >= 3) {
      return (
        category: FailureCategory.F3,
        decision: ParseDecision.failure,
        parsedText: '',
      );
    }

    // Structural attempt present (contains ':' and '|') but malformed
    if (rawOutput.contains(':') && rawOutput.contains('|')) {
      return (
        category: FailureCategory.F2,
        decision: ParseDecision.failure,
        parsedText: '',
      );
    }

    // Default: format violation (conversational greeting, plain prose, unparseable)
    return (
      category: FailureCategory.F1,
      decision: ParseDecision.failure,
      parsedText: '',
    );
  }
}
