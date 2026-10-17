import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';

/// Status codes returned by LiteRT-LM C API.
abstract class LiteRtLmStatus {
  static const int ok = 0;
  static const int errorInvalidArgument = 1;
  static const int errorOutOfMemory = 2;
  static const int errorModelNotFound = 3;
  static const int errorInferenceFailed = 4;
  static const int errorEngineNotReady = 5;
}

/// Exception thrown when a LiteRT-LM native call fails.
class LiteRtLmException implements Exception {
  final int errorCode;
  final String message;

  const LiteRtLmException(this.errorCode, this.message);

  @override
  String toString() => 'LiteRtLmException($errorCode): $message';
}

// Opaque Native Handles
final class OpaqueEngine extends ffi.Opaque {}
final class OpaqueConversation extends ffi.Opaque {}

// C Struct: Sampler Configuration
final class NativeSamplerConfig extends ffi.Struct {
  @ffi.Int32()
  external int topK;

  @ffi.Float()
  external double topP;

  @ffi.Float()
  external double temperature;
}

// Native Function Typedefs
typedef LiteRtLmEngineCreateNative = ffi.Int32 Function(
  ffi.Pointer<Utf8> modelPath,
  ffi.Int32 backend, // 0 = CPU, 1 = GPU
  ffi.Pointer<ffi.Pointer<OpaqueEngine>> outEngine,
);
typedef LiteRtLmEngineCreateDart = int Function(
  ffi.Pointer<Utf8> modelPath,
  int backend,
  ffi.Pointer<ffi.Pointer<OpaqueEngine>> outEngine,
);

typedef LiteRtLmEngineDestroyNative = ffi.Void Function(ffi.Pointer<OpaqueEngine> engine);
typedef LiteRtLmEngineDestroyDart = void Function(ffi.Pointer<OpaqueEngine> engine);

typedef LiteRtLmConversationCreateNative = ffi.Int32 Function(
  ffi.Pointer<OpaqueEngine> engine,
  ffi.Pointer<Utf8> systemPrompt,
  ffi.Pointer<NativeSamplerConfig> samplerConfig,
  ffi.Pointer<ffi.Pointer<OpaqueConversation>> outConversation,
);
typedef LiteRtLmConversationCreateDart = int Function(
  ffi.Pointer<OpaqueEngine> engine,
  ffi.Pointer<Utf8> systemPrompt,
  ffi.Pointer<NativeSamplerConfig> samplerConfig,
  ffi.Pointer<ffi.Pointer<OpaqueConversation>> outConversation,
);

typedef LiteRtLmConversationDestroyNative = ffi.Void Function(ffi.Pointer<OpaqueConversation> conversation);
typedef LiteRtLmConversationDestroyDart = void Function(ffi.Pointer<OpaqueConversation> conversation);

typedef LiteRtLmSendMessageNative = ffi.Int32 Function(
  ffi.Pointer<OpaqueConversation> conversation,
  ffi.Pointer<Utf8> prompt,
  ffi.Pointer<ffi.Pointer<Utf8>> outResponse,
);
typedef LiteRtLmSendMessageDart = int Function(
  ffi.Pointer<OpaqueConversation> conversation,
  ffi.Pointer<Utf8> prompt,
  ffi.Pointer<ffi.Pointer<Utf8>> outResponse,
);

typedef LiteRtLmFreeStringNative = ffi.Void Function(ffi.Pointer<Utf8> str);
typedef LiteRtLmFreeStringDart = void Function(ffi.Pointer<Utf8> str);

/// Low-level FFI bindings to LiteRT-LM C dynamic library (`liblitert_lm.so`).
class LiteRtLmBindings {
  final ffi.DynamicLibrary? _dylib;

  late final LiteRtLmEngineCreateDart _engineCreate;
  late final LiteRtLmEngineDestroyDart _engineDestroy;
  late final LiteRtLmConversationCreateDart _conversationCreate;
  late final LiteRtLmConversationDestroyDart _conversationDestroy;
  late final LiteRtLmSendMessageDart _sendMessage;
  late final LiteRtLmFreeStringDart _freeString;

  // NativeFinalizers to prevent memory leaks under Dart GC
  late final ffi.NativeFinalizer engineFinalizer;
  late final ffi.NativeFinalizer conversationFinalizer;

  final bool isMock;

  LiteRtLmBindings._({
    this._dylib,
    required this.isMock,
  }) {
    if (!isMock && _dylib != null) {
      _engineCreate = _dylib.lookupFunction<LiteRtLmEngineCreateNative, LiteRtLmEngineCreateDart>('LiteRtLmEngineCreate');
      _engineDestroy = _dylib.lookupFunction<LiteRtLmEngineDestroyNative, LiteRtLmEngineDestroyDart>('LiteRtLmEngineDestroy');
      _conversationCreate = _dylib.lookupFunction<LiteRtLmConversationCreateNative, LiteRtLmConversationCreateDart>('LiteRtLmConversationCreate');
      _conversationDestroy = _dylib.lookupFunction<LiteRtLmConversationDestroyNative, LiteRtLmConversationDestroyDart>('LiteRtLmConversationDestroy');
      _sendMessage = _dylib.lookupFunction<LiteRtLmSendMessageNative, LiteRtLmSendMessageDart>('LiteRtLmConversationSendMessage');
      _freeString = _dylib.lookupFunction<LiteRtLmFreeStringNative, LiteRtLmFreeStringDart>('LiteRtLmFreeString');

      final engineDestroyPtr = _dylib.lookup<ffi.NativeFunction<LiteRtLmEngineDestroyNative>>('LiteRtLmEngineDestroy');
      engineFinalizer = ffi.NativeFinalizer(engineDestroyPtr.cast());

      final convDestroyPtr = _dylib.lookup<ffi.NativeFunction<LiteRtLmConversationDestroyNative>>('LiteRtLmConversationDestroy');
      conversationFinalizer = ffi.NativeFinalizer(convDestroyPtr.cast());
    } else {
      // Mock / fallback finalizers
      engineFinalizer = ffi.NativeFinalizer(ffi.Pointer.fromAddress(0));
      conversationFinalizer = ffi.NativeFinalizer(ffi.Pointer.fromAddress(0));
    }
  }

  /// Opens the native LiteRT-LM library (`liblitert_lm.so`), or falls back to mock if unavailable.
  factory LiteRtLmBindings.open({String libraryPath = 'liblitert_lm.so'}) {
    try {
      final dylib = ffi.DynamicLibrary.open(libraryPath);
      return LiteRtLmBindings._(dylib: dylib, isMock: false);
    } catch (_) {
      // Fallback for non-Android platforms / headless test environments
      return LiteRtLmBindings.mock();
    }
  }

  /// Creates a mock binding instance for testing without native binaries.
  factory LiteRtLmBindings.mock() {
    return LiteRtLmBindings._(isMock: true);
  }

  int engineCreate(
    ffi.Pointer<Utf8> modelPath,
    int backend,
    ffi.Pointer<ffi.Pointer<OpaqueEngine>> outEngine,
  ) {
    if (isMock) {
      outEngine.value = ffi.Pointer.fromAddress(0x12345678);
      return LiteRtLmStatus.ok;
    }
    return _engineCreate(modelPath, backend, outEngine);
  }

  void engineDestroy(ffi.Pointer<OpaqueEngine> engine) {
    if (isMock) return;
    _engineDestroy(engine);
  }

  int conversationCreate(
    ffi.Pointer<OpaqueEngine> engine,
    ffi.Pointer<Utf8> systemPrompt,
    ffi.Pointer<NativeSamplerConfig> samplerConfig,
    ffi.Pointer<ffi.Pointer<OpaqueConversation>> outConversation,
  ) {
    if (isMock) {
      outConversation.value = ffi.Pointer.fromAddress(0x87654321);
      return LiteRtLmStatus.ok;
    }
    return _conversationCreate(engine, systemPrompt, samplerConfig, outConversation);
  }

  void conversationDestroy(ffi.Pointer<OpaqueConversation> conversation) {
    if (isMock) return;
    _conversationDestroy(conversation);
  }

  int sendMessage(
    ffi.Pointer<OpaqueConversation> conversation,
    ffi.Pointer<Utf8> prompt,
    ffi.Pointer<ffi.Pointer<Utf8>> outResponse,
  ) {
    if (isMock) {
      // Return a simulated hints response in mock mode
      final mockStr = 'hints: First mock hint | Second mock hint | Third mock hint'.toNativeUtf8();
      outResponse.value = mockStr;
      return LiteRtLmStatus.ok;
    }
    return _sendMessage(conversation, prompt, outResponse);
  }

  void freeString(ffi.Pointer<Utf8> str) {
    if (isMock) {
      calloc.free(str);
      return;
    }
    _freeString(str);
  }
}

