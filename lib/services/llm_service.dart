import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:xybrid_flutter/xybrid_flutter.dart' as xybrid;

import 'ai_profile.dart';

/// Raised when a streaming turn produces no first token within the configured
/// window (most often an unreachable or hung cloud gateway).
class FirstTokenTimeoutException implements Exception {
  final int seconds;
  const FirstTokenTimeoutException(this.seconds);

  @override
  String toString() =>
      'No response from the AI service within $seconds seconds. The cloud '
      'model may be unavailable - try again, or pick an on-device model in '
      'Settings.';
}

/// Provider-neutral AI service. The rest of the app talks in terms of
/// [AiProfile], [AiConversation], and [AiStreamChunk]; provider SDK details
/// stay inside this adapter.
class LlmService {
  /// On-device registry model. With an API key set, Xybrid serves from the
  /// cloud while these weights download, then switches to on-device (auto).
  static const String defaultModelId = 'qwen3.5-2b';

  /// Xybrid models the picker offers, in order.
  static const List<String> availableModelIds = [
    'qwen3.5-2b',
    'llama-3.2-1b',
    'gemma-3-1b',
    'smollm2-360m',
  ];

  AiProfile activeProfile;

  Future<void>? _xybridInitFuture;
  bool _xybridInitialized = false;
  xybrid.XybridModel? _xybridModel;

  LlmService({String? modelId, String? apiKey, AiProfile? profile})
    : activeProfile =
          profile ??
          AiProfile.xybrid(
            model: modelId ?? defaultModelId,
            apiKey: apiKey?.isEmpty ?? true ? null : apiKey,
          );

  bool get isInitialized {
    return switch (activeProfile.provider) {
      AiProviderType.xybrid => _xybridInitialized,
      AiProviderType.openAiCompatible => true,
    };
  }

  String get modelId => activeProfile.model;

  /// Initialize the active provider. For Xybrid, the API key is applied via
  /// `setApiKey` rather than `init(apiKey:)`: passing the key to init triggers
  /// a telemetry handshake that can hang on a flaky network.
  Future<void> init({String? apiKey}) {
    if (apiKey != null) {
      activeProfile = activeProfile.copyWith(
        apiKey: apiKey.isEmpty ? null : apiKey,
      );
    }
    return switch (activeProfile.provider) {
      AiProviderType.xybrid => _initXybridOnce(),
      AiProviderType.openAiCompatible => Future<void>.value(),
    };
  }

  Future<void> _initXybridOnce() {
    return _xybridInitFuture ??= _doInitXybrid();
  }

  Future<void> _doInitXybrid() async {
    try {
      await xybrid.Xybrid.init().timeout(const Duration(seconds: 25));
    } catch (_) {
      // Never cache a failed init; a later attempt may succeed.
      _xybridInitFuture = null;
      rethrow;
    }
    final apiKey = activeProfile.apiKey;
    if (apiKey != null && apiKey.isNotEmpty) {
      xybrid.Xybrid.setApiKey(apiKey);
    }
    _xybridInitialized = true;
  }

  /// Switch the whole active profile. Provider-specific handles are reset when
  /// the provider/model changes.
  Future<void> setActiveProfile(AiProfile profile) async {
    final old = activeProfile;
    activeProfile = profile;
    if (old.provider != profile.provider || old.model != profile.model) {
      _xybridModel = null;
    }
  }

  /// Switch the active Xybrid model, discarding any loaded handle so the next
  /// turn loads the new model.
  Future<void> setModelId(String id) async {
    if (id == activeProfile.model) return;
    activeProfile = activeProfile.copyWith(model: id);
    _xybridModel = null;
  }

  /// Re-apply runtime config (e.g. after the user saves a new API key). If the
  /// SDK isn't initialized yet, the key is applied when it initializes.
  Future<void> applyApiKey(String? apiKey) async {
    final trimmed = apiKey?.trim() ?? '';
    activeProfile = activeProfile.copyWith(
      apiKey: trimmed.isEmpty ? null : trimmed,
    );
    if (activeProfile.provider == AiProviderType.xybrid &&
        _xybridInitialized &&
        trimmed.isNotEmpty) {
      xybrid.Xybrid.setApiKey(trimmed);
    }
  }

  /// Whether a Xybrid model's weights are already downloaded and extracted.
  ///
  /// This is best-effort because Xybrid's cache check touches the Rust bridge
  /// and can throw before provider initialization has completed. UI code should
  /// never crash while rendering a cache badge.
  static bool isModelCached(String id) {
    try {
      return xybrid.Xybrid.isModelCached(id);
    } catch (_) {
      return false;
    }
  }

  /// Prepare the active AI profile for use. Xybrid may download/load local
  /// weights here; OpenAI-compatible profiles will use this hook later for
  /// validation or warm-up.
  Future<void> ensureReady({
    void Function(AiLoadStatus status)? onStatus,
  }) async {
    return switch (activeProfile.provider) {
      AiProviderType.xybrid => _ensureXybridReady(onStatus: onStatus),
      AiProviderType.openAiCompatible => Future<void>.value(),
    };
  }

  Future<void> _ensureXybridReady({
    void Function(AiLoadStatus status)? onStatus,
  }) async {
    await init();
    if (_xybridModel != null) return;
    final loader = xybrid.XybridModelLoader.fromRegistrySpeculative(
      activeProfile.model,
    );

    if (onStatus != null && !loader.willSpeculate) {
      await for (final event in loader.loadWithProgress()) {
        if (event is xybrid.LoadProgress) {
          onStatus(
            AiLoadStatus('Downloading model...', percentage: event.percentage),
          );
        } else if (event is xybrid.LoadError) {
          onStatus(AiLoadStatus(event.message, isError: true));
          throw xybrid.XybridException('Model load failed: ${event.message}');
        }
        if (event is xybrid.LoadComplete) break;
      }
    }

    _xybridModel = await loader.load();
  }

  /// Stream a chat turn through the active profile.
  ///
  /// If [firstTokenTimeout] is set and no token arrives within it, the stream
  /// is aborted and a [FirstTokenTimeoutException] is thrown instead of
  /// hanging forever.
  Stream<AiStreamChunk> streamChat(
    AiConversation conversation,
    String message, {
    AiCancellationToken? cancellationToken,
    Duration? firstTokenTimeout = const Duration(seconds: 45),
  }) async* {
    switch (activeProfile.provider) {
      case AiProviderType.xybrid:
        yield* _streamXybridChat(
          conversation,
          message,
          cancellationToken: cancellationToken,
          firstTokenTimeout: firstTokenTimeout,
        );
      case AiProviderType.openAiCompatible:
        yield* _streamOpenAiCompatibleChat(
          conversation,
          message,
          cancellationToken: cancellationToken,
          firstTokenTimeout: firstTokenTimeout,
        );
    }
  }

  Stream<AiStreamChunk> _streamOpenAiCompatibleChat(
    AiConversation conversation,
    String message, {
    AiCancellationToken? cancellationToken,
    Duration? firstTokenTimeout = const Duration(seconds: 45),
  }) async* {
    final profile = activeProfile;
    final baseUrl = profile.baseUrl?.trim() ?? '';
    final apiKey = profile.apiKey?.trim() ?? '';
    if (baseUrl.isEmpty) {
      throw StateError('The AI profile is missing an endpoint URL.');
    }
    if (apiKey.isEmpty) {
      throw StateError('The AI profile is missing an API key.');
    }

    final client = HttpClient();
    cancellationToken?.onCancel(() => client.close(force: true));
    final uri = _chatCompletionsUri(baseUrl);
    final request = await client.postUrl(uri);
    request.headers.contentType = ContentType.json;
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
    request.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');

    final messages = [
      for (final m in conversation.messages)
        {'role': m.role, 'content': m.content},
      {'role': 'user', 'content': message},
    ];
    conversation.pushUser(message);

    request.write(
      jsonEncode({
        'model': profile.model,
        'messages': messages,
        'stream': true,
        'temperature': profile.temperature,
        'max_tokens': profile.maxTokens,
      }),
    );

    var gotFirst = false;
    var timedOut = false;
    Timer? timer;
    if (firstTokenTimeout != null) {
      timer = Timer(firstTokenTimeout, () {
        timedOut = true;
        client.close(force: true);
      });
    }

    try {
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final body = await utf8.decoder.bind(response).join();
        throw HttpException(
          'AI request failed (${response.statusCode}): $body',
          uri: uri,
        );
      }

      var pending = '';
      await for (final chunk in utf8.decoder.bind(response)) {
        pending += chunk;
        while (true) {
          final newline = pending.indexOf('\n');
          if (newline == -1) break;
          final line = pending.substring(0, newline).trimRight();
          pending = pending.substring(newline + 1);
          if (!line.startsWith('data:')) continue;
          final data = line.substring(5).trim();
          if (data.isEmpty) continue;
          if (data == '[DONE]') return;
          final text = _contentFromOpenAiChunk(data);
          if (text == null || text.isEmpty) continue;
          if (!gotFirst) {
            gotFirst = true;
            timer?.cancel();
          }
          yield AiStreamChunk.text(text);
        }
      }
    } finally {
      timer?.cancel();
      client.close(force: true);
    }

    if (timedOut) {
      throw FirstTokenTimeoutException(firstTokenTimeout!.inSeconds);
    }
  }

  static Uri _chatCompletionsUri(String baseUrl) {
    final trimmed = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.parse(trimmed);
    if (uri.path.endsWith('/chat/completions')) return uri;
    return Uri.parse('$trimmed/chat/completions');
  }

  static String? _contentFromOpenAiChunk(String data) {
    final decoded = jsonDecode(data);
    if (decoded is! Map) return null;
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) return null;
    final first = choices.first;
    if (first is! Map) return null;
    final delta = first['delta'];
    if (delta is Map && delta['content'] != null) {
      return delta['content'].toString();
    }
    final message = first['message'];
    if (message is Map && message['content'] != null) {
      return message['content'].toString();
    }
    if (first['text'] != null) return first['text'].toString();
    return null;
  }

  Stream<AiStreamChunk> _streamXybridChat(
    AiConversation conversation,
    String message, {
    AiCancellationToken? cancellationToken,
    Duration? firstTokenTimeout = const Duration(seconds: 45),
  }) async* {
    await ensureReady();
    final model = _xybridModel!;
    final xybridContext = _toXybridContext(conversation);
    conversation.pushUser(message);
    xybridContext.pushText(message, xybrid.MessageRole.user);

    final xybridCancel = xybrid.CancellationToken();
    cancellationToken?.onCancel(xybridCancel.cancel);

    var gotFirst = false;
    var timedOut = false;
    Timer? timer;
    if (firstTokenTimeout != null) {
      timer = Timer(firstTokenTimeout, () {
        timedOut = true;
        xybridCancel.cancel();
      });
    }

    try {
      await for (final token in model.runStreamingWithContext(
        xybrid.XybridEnvelope.text(message),
        xybridContext,
        config: xybrid.GenerationConfig(
          maxTokens: activeProfile.maxTokens,
          temperature: activeProfile.temperature,
        ),
        cancellationToken: xybridCancel,
      )) {
        if (!gotFirst) {
          gotFirst = true;
          timer?.cancel();
        }
        if (token.isError) {
          yield AiStreamChunk.error(token.errorMessage ?? 'unknown error');
        } else {
          yield AiStreamChunk.text(token.token);
        }
      }
    } finally {
      timer?.cancel();
    }

    if (timedOut) {
      throw FirstTokenTimeoutException(firstTokenTimeout!.inSeconds);
    }
  }

  xybrid.ConversationContext _toXybridContext(AiConversation conversation) {
    final context = xybrid.ConversationContext();
    for (final message in conversation.messages) {
      switch (message.role) {
        case 'system':
          if (!context.hasSystem) {
            context.setSystem(message.content);
          }
          break;
        case 'assistant':
          context.pushText(message.content, xybrid.MessageRole.assistant);
          break;
        case 'user':
          context.pushText(message.content, xybrid.MessageRole.user);
          break;
      }
    }
    return context;
  }
}
