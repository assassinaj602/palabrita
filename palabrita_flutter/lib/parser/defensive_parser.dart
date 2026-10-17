import 'dart:convert';

/// Puzzle response containing the target word and associated hints.
class PuzzleResponse {
  final String word;
  final List<String> hints;

  const PuzzleResponse({
    required this.word,
    required this.hints,
  });

  Map<String, dynamic> toJson() => {
        'word': word,
        'hints': hints,
      };

  factory PuzzleResponse.fromJson(Map<String, dynamic> json) {
    final rawWord = json['word'] as String? ?? '';
    final rawHints = json['hints'];
    final hintsList = <String>[];
    if (rawHints is List) {
      for (final item in rawHints) {
        if (item != null) hintsList.add(item.toString());
      }
    }
    return PuzzleResponse(word: rawWord, hints: hintsList);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PuzzleResponse &&
          runtimeType == other.runtimeType &&
          word == other.word &&
          _listEquals(hints, other.hints);

  @override
  int get hashCode => word.hashCode ^ Object.hashAll(hints);

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Result of parsing an LLM response.
sealed class ParseResult<T> {
  const ParseResult();
}

class ParseSuccess<T> extends ParseResult<T> {
  final T data;
  const ParseSuccess(this.data);
}

class ParseError<T> extends ParseResult<T> {
  final String reason;
  final String rawResponse;
  const ParseError(this.reason, this.rawResponse);
}

/// Interface for defensive LLM response parsing.
abstract interface class LlmResponseParser {
  ParseResult<PuzzleResponse> parsePuzzle(String rawResponse);
  ParseResult<List<String>> parseHints(String rawResponse);
}

/// Port of Palabrita's Kotlin `LlmResponseParserImpl`.
///
/// Handles fence stripping, regex extraction, canonical decoding, and
/// structural fallback parsing.
class DefensiveParser implements LlmResponseParser {
  static const int minHints = 3;

  /// Regex matching JSON object with at most one level of nested braces:
  /// `\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\}`
  /// Note: Both Java's regex and Dart's RegExp handle this non-recursive pattern similarly.
  static final RegExp _jsonObjectRegex =
      RegExp(r'\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\}');

  /// Regex matching markdown code fences:
  /// ````\w*\s*\n?([\s\S]*?)\n?\s*````
  /// Note: Dart's RE2/ECMAScript RegExp matches `[\s\S]*?` lazily across newlines
  /// identical to Java's pattern.
  static final RegExp _codeFenceRegex =
      RegExp(r'```\w*\s*\n?([\s\S]*?)\n?\s*```');

  static const Set<String> _hintsKeys = {
    'hints',
    'dicas',
    'pistas',
    'clues',
    'indices',
    'consejos',
  };

  @override
  ParseResult<PuzzleResponse> parsePuzzle(String rawResponse) {
    if (rawResponse.trim().isEmpty) {
      return ParseError('empty response', rawResponse);
    }

    final sanitized = _sanitizeUtf8(rawResponse);
    final cleaned = _stripCodeFences(sanitized);

    // Attempt 1: direct decode with canonical keys
    final direct = _tryDecode(cleaned);
    if (direct != null) {
      return ParseSuccess(direct);
    }

    // Attempt 2: extract JSON block via regex, then try canonical keys
    final match = _jsonObjectRegex.firstMatch(cleaned);
    final extracted = match?.group(0);
    if (extracted != null) {
      final fromExtracted = _tryDecode(extracted);
      if (fromExtracted != null) {
        return ParseSuccess(fromExtracted);
      }
    }

    // Attempt 3: structural detection — identify fields by value type, not key name
    final jsonText = extracted ?? cleaned;
    final structural = _tryStructuralParse(jsonText);
    if (structural != null) {
      return ParseSuccess(structural);
    }

    return ParseError('could not parse JSON from response', rawResponse);
  }

  @override
  ParseResult<List<String>> parseHints(String rawResponse) {
    if (rawResponse.trim().isEmpty) {
      return ParseError('empty response', rawResponse);
    }

    final sanitized = _sanitizeUtf8(rawResponse);
    final cleaned = _stripCodeFences(sanitized);

    // Look for a line starting with a hints-like key followed by colon
    final lines = const LineSplitter().convert(cleaned);
    for (final line in lines) {
      final trimmed = line.trim();
      final colonIndex = trimmed.indexOf(':');
      if (colonIndex < 0) continue;

      final key = trimmed.substring(0, colonIndex).trim().toLowerCase();
      if (_hintsKeys.contains(key)) {
        final value = trimmed.substring(colonIndex + 1).trim();
        final hints = value
            .split('|')
            .map((h) => h.trim())
            .where((h) => h.isNotEmpty)
            .toList();
        if (hints.length >= minHints) {
          return ParseSuccess(hints);
        }
      }
    }

    return ParseError('could not parse hints from response', rawResponse);
  }

  String _stripCodeFences(String text) {
    final match = _codeFenceRegex.firstMatch(text);
    if (match == null) return text;
    final content = match.group(1);
    return content != null ? content.trim() : text;
  }

  String _sanitizeUtf8(String text) {
    // Replicates Kotlin's String(bytes, Charsets.UTF_8).replace("\uFFFD", "")
    final encoded = utf8.encode(text);
    return utf8.decode(encoded, allowMalformed: true).replaceAll('\uFFFD', '');
  }

  PuzzleResponse? _tryDecode(String text) {
    try {
      final decoded = jsonDecode(text.trim());
      if (decoded is! Map<String, dynamic>) return null;

      final word = decoded['word'] as String? ?? '';
      final hintsRaw = decoded['hints'];
      if (word.trim().isEmpty || hintsRaw is! List) return null;

      final hints = hintsRaw.map((e) => e?.toString() ?? '').toList();
      if (hints.isEmpty) return null;

      return PuzzleResponse(word: word, hints: hints);
    } catch (_) {
      return null;
    }
  }

  PuzzleResponse? _tryStructuralParse(String text) {
    try {
      final decoded = jsonDecode(text.trim());
      if (decoded is! Map<String, dynamic>) return null;

      String? word;
      List<String>? hints;

      for (final entry in decoded.entries) {
        final value = entry.value;
        if (value is List) {
          hints ??= value
              .where((e) => e != null)
              .map((e) => e.toString())
              .toList();
        } else if (value is String) {
          final strVal = value;
          // Structural rule: length in 2..8 and doesn't contain spaces
          if (word == null && strVal.length >= 2 && strVal.length <= 8 && !strVal.contains(' ')) {
            word = strVal;
          }
        }
      }

      if (word != null && hints != null && hints.length >= minHints) {
        return PuzzleResponse(word: word, hints: hints);
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}

