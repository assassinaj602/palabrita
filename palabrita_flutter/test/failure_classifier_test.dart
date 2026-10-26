import 'package:flutter_test/flutter_test.dart';
import 'package:palabrita_flutter/palabrita_flutter.dart';

void main() {
  group('FailureClassifier Unit Tests', () {
    final parser = DefensiveParser();

    test('classifies clean hint generation as success (none)', () {
      const raw = 'hints: É um animal | Faz miau | Tem quatro patas';
      final parseResult = parser.parseHints(raw);

      final eval = FailureClassifier.evaluate(
        rawOutput: raw,
        parseResult: parseResult,
        targetWord: 'gato',
      );

      expect(eval.category, equals(FailureCategory.none));
      expect(eval.decision, equals(ParseDecision.success));
    });

    test('classifies target word leakage as F2 (Structural Error)', () {
      const raw = 'hints: É um gato peludo | Faz miau | Tem bigodes';
      final parseResult = parser.parseHints(raw);

      final eval = FailureClassifier.evaluate(
        rawOutput: raw,
        parseResult: parseResult,
        targetWord: 'gato',
      );

      expect(eval.category, equals(FailureCategory.F2));
      expect(eval.decision, equals(ParseDecision.failure));
    });

    test('classifies conversational greeting prior as F1 (Format Violation)', () {
      const raw = "\n\nHello! I'm here to help. What can I do for you? 😊";
      final parseResult = parser.parseHints(raw);

      final eval = FailureClassifier.evaluate(
        rawOutput: raw,
        parseResult: parseResult,
        targetWord: 'livro',
      );

      expect(eval.category, equals(FailureCategory.F1));
      expect(eval.decision, equals(ParseDecision.failure));
    });

    test('classifies infinite token/phrase repetition loops as F3 (Context Degradation)', () {
      const raw = 'clue about word clue about word clue about word clue about word';
      final parseResult = parser.parseHints(raw);

      final eval = FailureClassifier.evaluate(
        rawOutput: raw,
        parseResult: parseResult,
        targetWord: 'livro',
      );

      expect(eval.category, equals(FailureCategory.F3));
      expect(eval.decision, equals(ParseDecision.failure));
    });

    test('classifies multi-turn degradation after consecutive failures as F3', () {
      const raw = 'Some random text without delimiters';
      final parseResult = parser.parseHints(raw);

      final eval = FailureClassifier.evaluate(
        rawOutput: raw,
        parseResult: parseResult,
        targetWord: 'livro',
        consecutiveFailures: 3,
      );

      expect(eval.category, equals(FailureCategory.F3));
      expect(eval.decision, equals(ParseDecision.failure));
    });

    test('classifies malformed delimiters as F2 (Structural Error)', () {
      const raw = 'hints: Clue one | Clue two'; // Only 2 clues instead of 3
      final parseResult = parser.parseHints(raw);

      final eval = FailureClassifier.evaluate(
        rawOutput: raw,
        parseResult: parseResult,
        targetWord: 'livro',
      );

      expect(eval.category, equals(FailureCategory.F2));
      expect(eval.decision, equals(ParseDecision.failure));
    });

    test('isRepetitionLoop correctly flags repetitions and ignores normal text', () {
      expect(FailureClassifier.isRepetitionLoop('abc'), isFalse);
      expect(FailureClassifier.isRepetitionLoop('Hello, this is a normal response with hints.'), isFalse);
      expect(FailureClassifier.isRepetitionLoop('repetitive phrase repetitive phrase repetitive phrase '), isTrue);
    });
  });
}
