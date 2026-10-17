import 'package:flutter_test/flutter_test.dart';
import 'package:palabrita_flutter/palabrita_flutter.dart';

void main() {
  late DefensiveParser parser;

  setUp(() {
    parser = DefensiveParser();
  });

  group('DefensiveParser - Task 2.1 Unit Tests', () {
    // 1. Clean JSON input
    test('1. parses clean valid JSON input', () {
      const raw = '{"word":"gatos","hints":["Dica 1","Dica 2","Dica 3"]}';
      final result = parser.parsePuzzle(raw);

      expect(result, isA<ParseSuccess<PuzzleResponse>>());
      final puzzle = (result as ParseSuccess<PuzzleResponse>).data;
      expect(puzzle.word, equals('gatos'));
      expect(puzzle.hints.length, equals(3));
      expect(puzzle.hints[0], equals('Dica 1'));
    });

    // 2. Fenced code blocks
    test('2. strips fenced code blocks with ```json and backticks', () {
      const raw = '''
```json
{"word":"campo","hints":["É aberto","Tem grama","Zona rural"]}
```
''';
      final result = parser.parsePuzzle(raw);

      expect(result, isA<ParseSuccess<PuzzleResponse>>());
      final puzzle = (result as ParseSuccess<PuzzleResponse>).data;
      expect(puzzle.word, equals('campo'));
      expect(puzzle.hints.length, equals(3));
    });

    // 3. Malformed JSON returns ParseError
    test('3. handles malformed JSON gracefully and returns ParseError', () {
      const raw = '{"word":"gatos","hints":';
      final result = parser.parsePuzzle(raw);

      expect(result, isA<ParseError<PuzzleResponse>>());
      final error = result as ParseError<PuzzleResponse>;
      expect(error.rawResponse, equals(raw));
    });

    // 4. Surrounding noisy prose text
    test('4. extracts JSON from surrounding noisy prose text', () {
      const raw = '''
Here is the word for the game:
{"word":"gatos","hints":["A","B","C"]}
I hope this helps!
''';
      final result = parser.parsePuzzle(raw);

      expect(result, isA<ParseSuccess<PuzzleResponse>>());
      final puzzle = (result as ParseSuccess<PuzzleResponse>).data;
      expect(puzzle.word, equals('gatos'));
      expect(puzzle.hints, equals(['A', 'B', 'C']));
    });

    // 5. Language drift strings (Spanish / Portuguese / English keys)
    test('5. parses hints with localized language keys (dicas, pistas, hints)', () {
      // Portuguese key 'dicas'
      final pt = parser.parseHints('dicas: Uma dica vaga | Uma dica média | Uma dica específica');
      expect(pt, isA<ParseSuccess<List<String>>>());
      expect((pt as ParseSuccess<List<String>>).data.length, equals(3));

      // Spanish key 'pistas'
      final es = parser.parseHints('pistas: Pista vaga | Pista media | Pista específica');
      expect(es, isA<ParseSuccess<List<String>>>());
      expect((es as ParseSuccess<List<String>>).data.length, equals(3));

      // English key 'hints'
      final en = parser.parseHints('hints: Hint 1 | Hint 2 | Hint 3');
      expect(en, isA<ParseSuccess<List<String>>>());
      expect((en as ParseSuccess<List<String>>).data.length, equals(3));
    });

    // 6. Empty and whitespace output
    test('6. returns ParseError on empty or whitespace output', () {
      final puzzleEmpty = parser.parsePuzzle('');
      expect(puzzleEmpty, isA<ParseError<PuzzleResponse>>());

      final puzzleWhitespace = parser.parsePuzzle('   \n  \t  ');
      expect(puzzleWhitespace, isA<ParseError<PuzzleResponse>>());

      final hintsEmpty = parser.parseHints('');
      expect(hintsEmpty, isA<ParseError<List<String>>>());
    });

    // 7. Structural detection fallback when JSON keys differ
    test('7. structural parsing succeeds when model drifts from canonical key names', () {
      // Non-canonical key names "target" and "clues"
      const raw = '{"target":"planta","clues":["Verde","Precisa de água","Cresce no solo"]}';
      final result = parser.parsePuzzle(raw);

      expect(result, isA<ParseSuccess<PuzzleResponse>>());
      final puzzle = (result as ParseSuccess<PuzzleResponse>).data;
      expect(puzzle.word, equals('planta'));
      expect(puzzle.hints.length, equals(3));
    });

    // 8. Mojibake recovery / replacement character stripping
    test('8. recovers from mojibake replacement characters', () {
      const replacementChar = '\uFFFD';
      const raw = '{"word":"a${replacementChar}o","hints":["Dica 1","Dica 2","Dica 3"]}';
      final result = parser.parsePuzzle(raw);

      expect(result, isA<ParseSuccess<PuzzleResponse>>());
      final puzzle = (result as ParseSuccess<PuzzleResponse>).data;
      expect(puzzle.word, equals('ao'));
    });

    // 9. Too few hints (< 3) rejected
    test('9. rejects response when fewer than minimum 3 hints are provided', () {
      const rawHints = 'hints: Only one hint | Second hint';
      final hintsResult = parser.parseHints(rawHints);
      expect(hintsResult, isA<ParseError<List<String>>>());

      const rawPuzzle = '{"word":"carro"}';
      final puzzleResult = parser.parsePuzzle(rawPuzzle);
      expect(puzzleResult, isA<ParseError<PuzzleResponse>>());
    });

    // 10. Pretty-printed multi-line JSON
    test('10. parses pretty-printed multi-line JSON correctly', () {
      const raw = '''
      {
        "word": "campo",
        "hints": [
          "É aberto",
          "Tem grama",
          "Zona rural"
        ]
      }
      ''';
      final result = parser.parsePuzzle(raw);

      expect(result, isA<ParseSuccess<PuzzleResponse>>());
      final puzzle = (result as ParseSuccess<PuzzleResponse>).data;
      expect(puzzle.word, equals('campo'));
      expect(puzzle.hints.length, equals(3));
    });
  });
}
