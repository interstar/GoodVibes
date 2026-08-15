import 'dart:async';

import 'package:xybrid_flutter/xybrid_flutter.dart';

/// Raised when a streaming turn produces no first token within the configured
/// window (most often an unreachable or hung cloud gateway).
class FirstTokenTimeoutException implements Exception {
  final int seconds;
  const FirstTokenTimeoutException(this.seconds);

  @override
  String toString() =>
      'No response from the AI service within $seconds seconds. The cloud '
      'model may be unavailable — try again, or pick an on-device model in '
      'Settings.';
}

/// Wraps Xybrid: initialization, model loading (with cloud-speculative
/// fallback), and streaming multi-turn chat.
class LlmService {
  /// On-device registry model. With an API key set, Xybrid serves from the
  /// cloud while these weights download, then switches to on-device (auto).
  static const String defaultModelId = 'qwen3.5-2b';

  /// Models the picker offers, in order.
  static const List<String> availableModelIds = [
    'qwen3.5-2b',
    'llama-3.2-1b',
    'gemma-3-1b',
    'smollm2-360m',
  ];

  String modelId;

  String? _apiKey;
  Future<void>? _initFuture;
  bool _initialized = false;
  XybridModel? _model;

  LlmService({String? modelId, String? apiKey})
      : modelId = modelId ?? defaultModelId,
        _apiKey = apiKey?.isEmpty ?? true ? null : apiKey;

  bool get isInitialized => _initialized;

  /// Initialize the SDK. The API key is applied via [Xybrid.setApiKey] rather
  /// than `Xybrid.init(apiKey:)`: passing the key to init triggers a telemetry
  /// handshake that can hang on a flaky network, whereas `setApiKey` is a
  /// local call that needs no I/O. Callers that need the SDK just `await`
  /// this (it is idempotent); startup code may fire-and-forget it.
  Future<void> init({String? apiKey}) {
    if (apiKey != null) {
      _apiKey = apiKey.isEmpty ? null : apiKey;
    }
    return _initFuture ??= _initOnce();
  }

  Future<void> _initOnce() async {
    try {
      await Xybrid.init().timeout(const Duration(seconds: 25));
    } catch (_) {
      // Never cache a failed init; a later attempt may succeed.
      _initFuture = null;
      rethrow;
    }
    if (_apiKey != null) {
      Xybrid.setApiKey(_apiKey!);
    }
    _initialized = true;
  }

  /// Switch the active model, discarding any loaded handle so the next turn
  /// loads the new model.
  Future<void> setModelId(String id) async {
    if (id == modelId) return;
    modelId = id;
    _model = null;
  }

  /// Re-apply runtime config (e.g. after the user saves a new API key). If the
  /// SDK isn't initialized yet, the key is applied when it initializes.
  Future<void> applyApiKey(String? apiKey) async {
    final trimmed = apiKey?.trim() ?? '';
    _apiKey = trimmed.isEmpty ? null : trimmed;
    if (_initialized && _apiKey != null) {
      Xybrid.setApiKey(_apiKey!);
    }
  }

  /// Whether a model's weights are already downloaded and extracted.
  static bool isModelCached(String id) => Xybrid.isModelCached(id);

  /// Load the model (downloading weights on first use), optionally streaming
  /// progress events. Without an API key, `fromRegistrySpeculative` behaves
  /// like a plain registry load and blocks until the weights are downloaded.
  Future<XybridModel> ensureModel({void Function(LoadEvent event)? onEvent}) async {
    await init();
    if (_model != null) return _model!;
    final loader = XybridModelLoader.fromRegistrySpeculative(modelId);

    if (onEvent != null && !loader.willSpeculate) {
      await for (final event in loader.loadWithProgress()) {
        onEvent(event);
        if (event is LoadError) {
          throw XybridException('Model load failed: ${event.message}');
        }
        if (event is LoadComplete) break;
      }
    }

    _model = await loader.load();
    return _model!;
  }

  /// Stream a chat turn. The message is pushed into [context]; callers should
  /// push the assistant's reply back into [context] after streaming.
  ///
  /// If [firstTokenTimeout] is set and no token arrives within it, the stream
  /// is aborted and a [FirstTokenTimeoutException] is thrown instead of
  /// hanging forever (e.g. when the cloud gateway is unresponsive).
  Stream<StreamToken> streamChat(
    ConversationContext context,
    String message, {
    CancellationToken? cancellationToken,
    Duration? firstTokenTimeout = const Duration(seconds: 45),
  }) async* {
    final model = await ensureModel();
    context.pushText(message, MessageRole.user);
    var gotFirst = false;
    var timedOut = false;
    Timer? timer;
    if (firstTokenTimeout != null && cancellationToken != null) {
      timer = Timer(firstTokenTimeout, () {
        timedOut = true;
        cancellationToken.cancel();
      });
    }

    try {
      await for (final token in model.runStreamingWithContext(
        XybridEnvelope.text(message),
        context,
        config: const GenerationConfig(maxTokens: 4096, temperature: 0.4),
        cancellationToken: cancellationToken,
      )) {
        if (!gotFirst) {
          gotFirst = true;
          timer?.cancel();
        }
        yield token;
      }
    } finally {
      timer?.cancel();
    }

    if (timedOut) {
      throw FirstTokenTimeoutException(firstTokenTimeout!.inSeconds);
    }
  }
}
