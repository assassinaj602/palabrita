import 'package:flutter_test/flutter_test.dart';
import 'package:palabrita_flutter/palabrita_flutter.dart';

void main() {
  late PromptEngine engine;

  setUp(() {
    engine = PromptEngine();
  });

  group('PromptEngine - Task 2.2 Unit Tests', () {
    test('resolves language display names correctly', () {
      expect(engine.languageDisplayName('pt'), equals('Brazilian Portuguese'));
      expect(engine.languageDisplayName('en'), equals('English'));
      expect(engine.languageDisplayName('es'), equals('Spanish'));
      expect(engine.languageDisplayName('it'), equals('Italian'));
      expect(engine.languageDisplayName('fr'), equals('fr')); // fallback to code
    });

    test('generates system prompt with resolved language name and exact format', () {
      final prompt = engine.hintSystemPrompt('pt');
      expect(prompt, contains('You write short, clear word-game hints in Brazilian Portuguese.'));
      expect(prompt, contains('hints: hint 1 | hint 2 | hint 3'));
      expect(prompt, contains('ALL hints MUST be written in Brazilian Portuguese.'));
    });

    test('generates user prompt with uppercase target word and instructions', () {
      final prompt = engine.hintUserPrompt('gatos', 'es');
      expect(prompt, contains('Language: Spanish'));
      expect(prompt, contains('Target word: "GATOS"'));
      expect(prompt, contains('Write 3 hints for this word IN Spanish.'));
      expect(prompt, contains('Começa com G'));
      expect(prompt, contains('Tem 5 letras'));
    });

    test('provides prompt metadata for logging', () {
      final hintMeta = engine.getPromptMetadata(
        PromptType.hintOnly,
        'pt',
        targetWord: 'campo',
      );
      expect(hintMeta.promptType, equals(PromptType.hintOnly));
      expect(hintMeta.language, equals('pt'));
      expect(hintMeta.targetWord, equals('campo'));
      expect(hintMeta.toJson()['prompt_type'], equals('hint-only'));

      final fallbackMeta = engine.getPromptMetadata(
        PromptType.fallback,
        'en',
        targetWord: 'house',
      );
      expect(fallbackMeta.promptType, equals(PromptType.fallback));
      expect(fallbackMeta.toJson()['prompt_type'], equals('fallback'));
    });

    test('produces valid 3-hint fallback lists across supported languages', () {
      // Portuguese fallback
      final ptFallback = engine.getFallbackHints('carro', 'pt');
      expect(ptFallback.length, equals(3));
      expect(ptFallback[0], equals('É algo que as pessoas conhecem'));
      expect(ptFallback[2], equals('Tem 5 letras'));

      // Spanish fallback
      final esFallback = engine.getFallbackHints('perro', 'es');
      expect(esFallback.length, equals(3));
      expect(esFallback[0], equals('Es algo que la gente conoce'));
      expect(esFallback[2], equals('Tiene 5 letras'));

      // English / default fallback
      final enFallback = engine.getFallbackHints('table', 'en');
      expect(enFallback.length, equals(3));
      expect(enFallback[0], equals('It is something people know'));
      expect(enFallback[2], equals('It has 5 letters'));
    });
  });
}

