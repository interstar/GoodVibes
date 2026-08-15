import 'package:xybrid_flutter/xybrid_flutter.dart';

/// Wraps Xybrid: initialization, model loading (with cloud-speculative
/// fallback), and streaming multi-turn chat.
class LlmService {
  /// On-device registry model. With an API key set, Xybrid serves from the
  /// cloud while these weights download, then switches to on-device (auto).
  static const String defaultModelId = 'qwen3.5-2b';

  final String modelId;

  XybridModel? _model;
  bool _initialized = false;

  LlmService({this.modelId = defaultModelId});

  bool get isInitialized => _initialized;

  Future<void> init({String? apiKey}) async {
    await Xybrid.init(apiKey: apiKey);
    _initialized = true;
  }

  /// Re-apply runtime config (e.g. after the user saves a new API key).
  Future<void> applyApiKey(String? apiKey) async {
    if (apiKey != null && apiKey.isNotEmpty) {
      Xybrid.setApiKey(apiKey);
    }
  }

  /// Load the model (downloading weights on first use), optionally streaming
  /// progress events. Without an API key, `fromRegistrySpeculative` behaves
  /// like a plain registry load and blocks until the weights are downloaded.
  Future<XybridModel> ensureModel({void Function(LoadEvent event)? onEvent}) async {
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
  Stream<StreamToken> streamChat(
    ConversationContext context,
    String message, {
    CancellationToken? cancellationToken,
  }) async* {
    final model = await ensureModel();
    context.pushText(message, MessageRole.user);
    yield* model.runStreamingWithContext(
      XybridEnvelope.text(message),
      context,
      config: const GenerationConfig(maxTokens: 4096, temperature: 0.4),
      cancellationToken: cancellationToken,
    );
  }
}
