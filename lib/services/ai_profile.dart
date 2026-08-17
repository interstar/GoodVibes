/// Provider families supported by Good Vibes AI profiles.
enum AiProviderType { xybrid, openAiCompatible }

String _providerToJson(AiProviderType provider) {
  return switch (provider) {
    AiProviderType.xybrid => 'xybrid',
    AiProviderType.openAiCompatible => 'openAiCompatible',
  };
}

AiProviderType _providerFromJson(Object? value) {
  return switch (value) {
    'openAiCompatible' => AiProviderType.openAiCompatible,
    _ => AiProviderType.xybrid,
  };
}

/// A user-selectable AI configuration. UI and app code should reason in terms
/// of this profile, not provider-specific SDK classes.
class AiProfile {
  static const Object _unset = Object();
  final String id;
  final String name;
  final AiProviderType provider;
  final String model;
  final String? apiKey;
  final String? baseUrl;
  final double temperature;
  final int maxTokens;

  const AiProfile({
    required this.id,
    required this.name,
    required this.provider,
    required this.model,
    this.apiKey,
    this.baseUrl,
    this.temperature = 0.4,
    this.maxTokens = 4096,
  });

  factory AiProfile.xybrid({required String model, String? apiKey}) {
    return AiProfile(
      id: 'xybrid',
      name: 'Xybrid',
      provider: AiProviderType.xybrid,
      model: model,
      apiKey: apiKey,
    );
  }

  factory AiProfile.openAiCompatible({
    required String id,
    required String name,
    required String baseUrl,
    required String model,
    String? apiKey,
    double temperature = 0.4,
    int maxTokens = 4096,
  }) {
    return AiProfile(
      id: id,
      name: name,
      provider: AiProviderType.openAiCompatible,
      baseUrl: baseUrl,
      model: model,
      apiKey: apiKey,
      temperature: temperature,
      maxTokens: maxTokens,
    );
  }

  AiProfile copyWith({
    String? id,
    String? name,
    AiProviderType? provider,
    String? model,
    Object? apiKey = _unset,
    Object? baseUrl = _unset,
    double? temperature,
    int? maxTokens,
  }) {
    return AiProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      provider: provider ?? this.provider,
      model: model ?? this.model,
      apiKey: identical(apiKey, _unset) ? this.apiKey : apiKey as String?,
      baseUrl: identical(baseUrl, _unset) ? this.baseUrl : baseUrl as String?,
      temperature: temperature ?? this.temperature,
      maxTokens: maxTokens ?? this.maxTokens,
    );
  }

  Map<String, dynamic> toMetadataJson() => {
    'id': id,
    'name': name,
    'provider': _providerToJson(provider),
    'model': model,
    if (baseUrl != null) 'baseUrl': baseUrl,
    'temperature': temperature,
    'maxTokens': maxTokens,
  };

  factory AiProfile.fromMetadataJson(
    Map<String, dynamic> json, {
    String? apiKey,
  }) {
    return AiProfile(
      id: json['id'] as String? ?? 'xybrid',
      name: json['name'] as String? ?? 'Xybrid',
      provider: _providerFromJson(json['provider']),
      model: json['model'] as String? ?? 'qwen3.5-2b',
      baseUrl: json['baseUrl'] as String?,
      apiKey: apiKey,
      temperature: (json['temperature'] as num?)?.toDouble() ?? 0.4,
      maxTokens: (json['maxTokens'] as num?)?.toInt() ?? 4096,
    );
  }
}

class AiMessage {
  final String role;
  final String content;

  const AiMessage({required this.role, required this.content});

  const AiMessage.system(String content)
    : this(role: 'system', content: content);
  const AiMessage.user(String content) : this(role: 'user', content: content);
  const AiMessage.assistant(String content)
    : this(role: 'assistant', content: content);
}

/// Provider-neutral chat state.
class AiConversation {
  final List<AiMessage> _messages = [];

  bool get hasSystem => _messages.any((m) => m.role == 'system');
  List<AiMessage> get messages => List.unmodifiable(_messages);

  void setSystem(String content) {
    final index = _messages.indexWhere((m) => m.role == 'system');
    final message = AiMessage.system(content);
    if (index == -1) {
      _messages.insert(0, message);
    } else {
      _messages[index] = message;
    }
  }

  void pushUser(String content) => _messages.add(AiMessage.user(content));
  void pushAssistant(String content) =>
      _messages.add(AiMessage.assistant(content));
}

class AiCancellationToken {
  final List<void Function()> _callbacks = [];
  bool _isCancelled = false;

  bool get isCancelled => _isCancelled;

  void cancel() {
    if (_isCancelled) return;
    _isCancelled = true;
    for (final callback in List<void Function()>.from(_callbacks)) {
      callback();
    }
  }

  void onCancel(void Function() callback) {
    if (_isCancelled) {
      callback();
    } else {
      _callbacks.add(callback);
    }
  }
}

class AiLoadStatus {
  final String message;
  final int? percentage;
  final bool isError;

  const AiLoadStatus(this.message, {this.percentage, this.isError = false});
}

class AiStreamChunk {
  final String text;
  final String? errorMessage;

  const AiStreamChunk.text(this.text) : errorMessage = null;
  const AiStreamChunk.error(this.errorMessage) : text = '';

  bool get isError => errorMessage != null;
}
