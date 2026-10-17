/// Prompt type categorization for inference tracking and logging.
enum PromptType {
  hintOnly,
  fallback;

  String toJson() => switch (this) {
        PromptType.hintOnly => 'hint-only',
        PromptType.fallback => 'fallback',
      };
}

/// Metadata describing prompt configuration for an inference run.
class PromptMetadata {
  final PromptType promptType;
  final String language;
  final String? targetWord;

  const PromptMetadata({
    required this.promptType,
    required this.language,
    this.targetWord,
  });

  Map<String, dynamic> toJson() => {
        'prompt_type': promptType.toJson(),
        'language': language,
        if (targetWord != null) 'target_word': targetWord,
      };
}

/// Abstract contract for prompt template providers.
abstract interface class PromptProvider {
  String hintSystemPrompt(String language);
  String hintUserPrompt(String word, String language);
  String languageDisplayName(String code);
  PromptMetadata getPromptMetadata(PromptType type, String language, {String? targetWord});
}

/// Provider for template-based fallback hints when LLM generation fails.
abstract interface class HintFallbackProvider {
  List<String> fallbackHints(String word, String language);
}

/// Implementation of Palabrita's fallback hints.
///
/// Produces deterministic, safe, 3-hint lists that never reveal the target word.
class HintFallbackProviderImpl implements HintFallbackProvider {
  const HintFallbackProviderImpl();

  @override
  List<String> fallbackHints(String word, String language) => switch (language) {
        'pt' => [
            'É algo que as pessoas conhecem',
            'Pode ser encontrado no dia a dia',
            'Tem ${word.length} letras',
          ],
        'es' => [
            'Es algo que la gente conoce',
            'Se puede encontrar en el día a día',
            'Tiene ${word.length} letras',
          ],
        _ => [
            'It is something people know',
            'It can be found in everyday life',
            'It has ${word.length} letters',
          ],
      };
}

/// Port of Palabrita's Kotlin `PromptTemplates`.
///
/// Contains exact prompt strings, rules, and fallback mappings.
class PromptEngine implements PromptProvider {
  static const Map<String, String> defaultLanguageNames = {
    'pt': 'Brazilian Portuguese',
    'en': 'English',
    'es': 'Spanish',
    'it': 'Italian',
  };

  final Map<String, String> _customLanguageMap;
  final HintFallbackProvider fallbackProvider;

  PromptEngine({
    Map<String, String>? customLanguageMap,
    this.fallbackProvider = const HintFallbackProviderImpl(),
  }) : _customLanguageMap = customLanguageMap ?? defaultLanguageNames;

  @override
  String languageDisplayName(String code) {
    return _customLanguageMap[code] ?? code;
  }

  @override
  String hintSystemPrompt(String language) {
    final lang = languageDisplayName(language);
    return '''
You write short, clear word-game hints in $lang.

Rules:
- The target word is already chosen by the app.
- Do not change the target word.
- Write exactly 3 hints.
- ALL hints MUST be written in $lang. Never write hints in English or any other language.
- Each hint must describe the meaning or common use of the target word.
- Do not include the target word in any hint.
- Do not include spelling, letter count, rhymes, or the first letter.
- Use simple language for casual mobile players.
- Return only this format:

hints: hint 1 | hint 2 | hint 3''';
  }

  @override
  String hintUserPrompt(String word, String language) {
    final lang = languageDisplayName(language);
    final upper = word.toUpperCase();
    final firstChar = upper.isNotEmpty ? upper[0] : '';
    return '''
Language: $lang
Target word: "$upper"

Write 3 hints for this word IN $lang.
Do NOT write hints in English unless the language is English.

Bad hints:
- "A palavra é $upper"
- "Começa com $firstChar"
- "Tem ${word.length} letras"

Good style:
hints: <vague hint in $lang> | <medium hint in $lang> | <specific hint in $lang>''';
  }

  @override
  PromptMetadata getPromptMetadata(
    PromptType type,
    String language, {
    String? targetWord,
  }) {
    return PromptMetadata(
      promptType: type,
      language: language,
      targetWord: targetWord,
    );
  }

  /// Convenience method to generate fallback hints.
  List<String> getFallbackHints(String word, String language) {
    return fallbackProvider.fallbackHints(word, language);
  }
}

