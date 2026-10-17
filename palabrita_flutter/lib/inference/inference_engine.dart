import 'dart:developer' as developer;
import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';
import 'litert_lm_bindings.dart';

/// Result from an inference execution.
class InferenceResult {
  final String text;
  final int latencyMs;
  final int gcPauseEstimateUs;

  const InferenceResult({
    required this.text,
    required this.latencyMs,
    required this.gcPauseEstimateUs,
  });
}

/// Callback hook fired on single-shot completion.
typedef OnInferenceComplete = void Function(String response, int latencyMs);

/// High-level Dart API over LiteRT-LM FFI bindings.
///
/// Handles initialization, single-shot generation, wall-clock timing,
/// GC pressure probe recording, and safe native resource deallocation.
class InferenceEngine implements ffi.Finalizable {
  final LiteRtLmBindings bindings;
  ffi.Pointer<OpaqueEngine>? _enginePtr;
  bool _isDisposed = false;

  final OnInferenceComplete? onComplete;

  InferenceEngine({
    LiteRtLmBindings? bindings,
    this.onComplete,
  }) : bindings = bindings ?? LiteRtLmBindings.open();

  bool get isReady => _enginePtr != null && !_isDisposed;

  /// Initializes the LiteRT-LM engine with model path and backend.
  /// Backend: 0 = CPU, 1 = GPU.
  Future<void> initialize({
    required String modelPath,
    bool useGpu = false,
  }) async {
    if (_isDisposed) throw StateError('Engine already disposed');

    final pathPtr = modelPath.toNativeUtf8();
    final outEngine = calloc<ffi.Pointer<OpaqueEngine>>();

    try {
      final backend = useGpu ? 1 : 0;
      final status = bindings.engineCreate(pathPtr, backend, outEngine);
      if (status != LiteRtLmStatus.ok) {
        throw LiteRtLmException(status, 'Failed to initialize LiteRT-LM engine (backend: $backend)');
      }
      _enginePtr = outEngine.value;
      if (!bindings.isMock) {
        bindings.engineFinalizer.attach(this, _enginePtr!.cast(), detach: this);
      }
    } finally {
      calloc.free(pathPtr);
      calloc.free(outEngine);
    }
  }

  /// Forces a minor GC pressure hint and measures the synchronous pause in microseconds
  /// using Dart's Timeline API.
  int _probeGcPause() {
    final stopwatch = Stopwatch()..start();
    developer.Timeline.timeSync('InferencePreGCProbe', () {
      // Allocate and release temporary objects to trigger generational GC pressure
      final probe = List<int?>.filled(10000, 0);
      probe[0] = null;
    });
    stopwatch.stop();
    return stopwatch.elapsedMicroseconds;
  }

  /// Executes single-shot inference.
  ///
  /// Records wall-clock latency, runs the pre-inference GC probe,
  /// invokes [onComplete] hook, and safely returns [InferenceResult].
  Future<InferenceResult> generateSingleTurn({
    String? systemPrompt,
    required String userPrompt,
    int topK = 40,
    double topP = 0.95,
    double temperature = 0.8,
  }) async {
    final eng = _enginePtr;
    if (eng == null || _isDisposed) {
      throw StateError('InferenceEngine is not initialized or has been disposed');
    }

    // 1. GC Pressure probe before inference
    final gcPauseUs = _probeGcPause();

    // 2. Wall-clock timing wrapper
    final stopwatch = Stopwatch()..start();

    // Native pointers
    final sysPromptPtr = systemPrompt != null ? systemPrompt.toNativeUtf8() : ffi.nullptr.cast<Utf8>();
    final promptPtr = userPrompt.toNativeUtf8();
    final samplerPtr = calloc<NativeSamplerConfig>();
    samplerPtr.ref.topK = topK;
    samplerPtr.ref.topP = topP;
    samplerPtr.ref.temperature = temperature;

    final outConv = calloc<ffi.Pointer<OpaqueConversation>>();
    final outResponse = calloc<ffi.Pointer<Utf8>>();

    ffi.Pointer<OpaqueConversation>? convPtr;

    try {
      // Create conversation
      final convStatus = bindings.conversationCreate(eng, sysPromptPtr, samplerPtr, outConv);
      if (convStatus != LiteRtLmStatus.ok) {
        throw LiteRtLmException(convStatus, 'Failed to create conversation');
      }
      convPtr = outConv.value;

      // Send single-turn message
      final sendStatus = bindings.sendMessage(convPtr, promptPtr, outResponse);
      if (sendStatus != LiteRtLmStatus.ok) {
        throw LiteRtLmException(sendStatus, 'Inference execution failed');
      }

      final responseText = outResponse.value.toDartString();
      bindings.freeString(outResponse.value);

      stopwatch.stop();
      final latencyMs = stopwatch.elapsedMilliseconds;

      // 3. Callback hook
      onComplete?.call(responseText, latencyMs);

      return InferenceResult(
        text: responseText,
        latencyMs: latencyMs,
        gcPauseEstimateUs: gcPauseUs,
      );
    } finally {
      if (convPtr != null) {
        bindings.conversationDestroy(convPtr);
      }
      if (sysPromptPtr != ffi.nullptr) {
        calloc.free(sysPromptPtr);
      }
      calloc.free(promptPtr);
      calloc.free(samplerPtr);
      calloc.free(outConv);
      calloc.free(outResponse);
    }
  }

  /// Disposes native engine resources.
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    final eng = _enginePtr;
    if (eng != null) {
      bindings.engineFinalizer.detach(this);
      bindings.engineDestroy(eng);
      _enginePtr = null;
    }
  }
}

