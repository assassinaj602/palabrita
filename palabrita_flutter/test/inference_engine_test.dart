import 'package:flutter_test/flutter_test.dart';
import 'package:palabrita_flutter/palabrita_flutter.dart';

void main() {
  group('InferenceEngine - Task 2.3 Unit Tests', () {
    test('initializes and executes single-shot inference with mock bindings', () async {
      String? callbackResponse;
      int? callbackLatency;

      final engine = InferenceEngine(
        bindings: LiteRtLmBindings.mock(),
        onComplete: (resp, lat) {
          callbackResponse = resp;
          callbackLatency = lat;
        },
      );

      expect(engine.isReady, isFalse);

      await engine.initialize(modelPath: '/dummy/model.bin', useGpu: false);
      expect(engine.isReady, isTrue);

      final result = await engine.generateSingleTurn(
        systemPrompt: 'You are a test assistant',
        userPrompt: 'Generate hints for GATOS',
      );

      expect(result.text, contains('hints:'));
      expect(result.latencyMs, greaterThanOrEqualTo(0));
      expect(result.gcPauseEstimateUs, greaterThanOrEqualTo(0));

      expect(callbackResponse, equals(result.text));
      expect(callbackLatency, equals(result.latencyMs));

      engine.dispose();
      expect(engine.isReady, isFalse);
    });

    test('throws StateError when calling inference before initialization', () async {
      final engine = InferenceEngine(bindings: LiteRtLmBindings.mock());

      expect(
        () => engine.generateSingleTurn(userPrompt: 'test'),
        throwsStateError,
      );
    });

    test('throws StateError when calling initialize or inference after disposal', () async {
      final engine = InferenceEngine(bindings: LiteRtLmBindings.mock());
      await engine.initialize(modelPath: '/dummy/model.bin');
      engine.dispose();

      expect(
        () => engine.initialize(modelPath: '/dummy/model.bin'),
        throwsStateError,
      );

      expect(
        () => engine.generateSingleTurn(userPrompt: 'test'),
        throwsStateError,
      );
    });
  });
}

