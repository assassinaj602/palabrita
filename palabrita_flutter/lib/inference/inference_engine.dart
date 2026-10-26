import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart' show MethodChannel, PlatformException;
import 'litert_lm_bindings.dart';

/// Result from an inference execution.
class InferenceResult {
  final String text;
  final int latencyMs;

  const InferenceResult({
    required this.text,
    required this.latencyMs,
  });
}

/// Callback hook fired on single-shot completion.
typedef OnInferenceComplete = void Function(String response, int latencyMs);

/// High-level Dart API over LiteRT-LM inference backends.
///
/// Supports hardware execution via Flutter MethodChannel (`MainActivity.kt` bridge
/// to `com.google.ai.edge.litertlm:litertlm-android`), native C FFI bindings (`liblitert_lm.so`),
/// and deterministic mock bindings for headless CI testing.
class InferenceEngine implements ffi.Finalizable {
  static const MethodChannel _platformChannel =
      MethodChannel('com.palabrita.research/litertlm');
  bool _usePlatformChannel = false;

  final LiteRtLmBindings bindings;
  ffi.Pointer<OpaqueEngine>? _enginePtr;
  bool _isDisposed = false;

  final OnInferenceComplete? onComplete;

  InferenceEngine({
    LiteRtLmBindings? bindings,
    this.onComplete,
  }) : bindings = bindings ?? LiteRtLmBindings.open();

  bool get isReady => (_usePlatformChannel || _enginePtr != null) && !_isDisposed;

  /// Returns the active execution mode: 'hardware' or 'mock'.
  String get executionMode =>
      _usePlatformChannel || !bindings.isMock ? 'hardware' : 'mock';

  /// Initializes the LiteRT-LM engine with model path and backend.
  Future<void> initialize({
    required String modelPath,
    bool useGpu = false,
  }) async {
    if (_isDisposed) throw StateError('Engine already disposed');

    // Attempt platform channel initialization first on Android
    if (bindings.isMock) {
      try {
        final ok = await _platformChannel.invokeMethod<bool>('initialize', {
          'modelPath': modelPath,
          'useGpu': useGpu,
        });
        if (ok == true) {
          _usePlatformChannel = true;
          return;
        }
      } on MissingPluginException {
        // Headless CLI/desktop unit test where no Flutter embedding exists:
        // continue with mock bindings.
      } on PlatformException catch (e) {
        // Hardware platform channel is available but initialization failed:
        // Do NOT silently fall back to mock. Fail explicitly.
        throw LiteRtLmException(
          LiteRtLmStatus.errorInferenceFailed,
          'Hardware engine initialization failed on device: ${e.message} (details: ${e.details})',
        );
      }
    }

    if (_usePlatformChannel) return;

    final pathPtr = modelPath.toNativeUtf8();
    final outEngine = calloc<ffi.Pointer<OpaqueEngine>>();

    try {
      final backend = useGpu ? 1 : 0;
      final status = bindings.engineCreate(pathPtr, backend, outEngine);
      if (status != LiteRtLmStatus.ok) {
        throw LiteRtLmException(
          status,
          'Failed to initialize LiteRT-LM native engine (backend: $backend)',
        );
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

  /// Starts or reconfigures a persistent native conversation session.
  Future<void> startSession({
    String? systemPrompt,
    int topK = 40,
    double topP = 0.95,
    double temperature = 0.8,
  }) async {
    if (_usePlatformChannel) {
      try {
        await _platformChannel.invokeMethod('startSession', {
          if (systemPrompt != null) 'systemPrompt': systemPrompt,
          'topK': topK,
          'topP': topP,
          'temperature': temperature,
        });
      } on PlatformException catch (e) {
        throw LiteRtLmException(
          LiteRtLmStatus.errorInferenceFailed,
          'Failed to start native session: ${e.message}',
        );
      }
    }
  }

  /// Resets the active native conversation session and discards KV-cache context.
  Future<void> resetSession() async {
    if (_usePlatformChannel) {
      try {
        await _platformChannel.invokeMethod('resetSession');
      } catch (_) {}
    }
  }

  /// Executes single-shot inference.
  ///
  /// Records wall-clock latency, invokes [onComplete] hook, and returns [InferenceResult].
  Future<InferenceResult> generateSingleTurn({
    String? systemPrompt,
    required String userPrompt,
    int topK = 40,
    double topP = 0.95,
    double temperature = 0.8,
  }) async {
    if (!isReady) {
      throw StateError('InferenceEngine is not initialized or has been disposed');
    }

    final stopwatch = Stopwatch()..start();

    if (_usePlatformChannel) {
      try {
        final response = await _platformChannel.invokeMethod<String>('sendMessage', {
          if (systemPrompt != null) 'systemPrompt': systemPrompt,
          'userPrompt': userPrompt,
          'topK': topK,
          'topP': topP,
          'temperature': temperature,
        }) ?? '';

        stopwatch.stop();
        final latencyMs = stopwatch.elapsedMilliseconds;
        onComplete?.call(response, latencyMs);

        return InferenceResult(
          text: response,
          latencyMs: latencyMs,
        );
      } on PlatformException catch (e) {
        throw LiteRtLmException(
          LiteRtLmStatus.errorInferenceFailed,
          e.message ?? 'Inference execution failed',
        );
      }
    }

    // Native pointers
    final eng = _enginePtr!;
    final sysPromptPtr = systemPrompt != null
        ? systemPrompt.toNativeUtf8()
        : ffi.nullptr.cast<Utf8>();
    final promptPtr = userPrompt.toNativeUtf8();
    final samplerPtr = calloc<NativeSamplerConfig>();
    samplerPtr.ref.topK = topK;
    samplerPtr.ref.topP = topP;
    samplerPtr.ref.temperature = temperature;

    final outConv = calloc<ffi.Pointer<OpaqueConversation>>();
    final outResponse = calloc<ffi.Pointer<Utf8>>();

    ffi.Pointer<OpaqueConversation>? convPtr;

    try {
      final convStatus =
          bindings.conversationCreate(eng, sysPromptPtr, samplerPtr, outConv);
      if (convStatus != LiteRtLmStatus.ok) {
        throw LiteRtLmException(convStatus, 'Failed to create conversation');
      }
      convPtr = outConv.value;

      final sendStatus = bindings.sendMessage(convPtr, promptPtr, outResponse);
      if (sendStatus != LiteRtLmStatus.ok) {
        throw LiteRtLmException(sendStatus, 'Inference execution failed');
      }

      final responseText = outResponse.value.toDartString();
      bindings.freeString(outResponse.value);

      stopwatch.stop();
      final latencyMs = stopwatch.elapsedMilliseconds;

      onComplete?.call(responseText, latencyMs);

      return InferenceResult(
        text: responseText,
        latencyMs: latencyMs,
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
    if (_usePlatformChannel) {
      _platformChannel.invokeMethod('dispose').catchError((_) => null);
      _usePlatformChannel = false;
    }
    final eng = _enginePtr;
    if (eng != null) {
      if (!bindings.isMock) {
        bindings.engineFinalizer.detach(this);
        bindings.engineDestroy(eng);
      }
      _enginePtr = null;
    }
  }
}
