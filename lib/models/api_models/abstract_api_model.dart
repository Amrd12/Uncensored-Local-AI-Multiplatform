import '../message_model.dart';

/// Supported remote/local API provider types.
enum ApiProviderType {
  openai,
  lmStudio,
  ollama,
  custom;

  String get displayName {
    switch (this) {
      case ApiProviderType.openai:
        return 'OpenAI';
      case ApiProviderType.lmStudio:
        return 'LM Studio';
      case ApiProviderType.ollama:
        return 'Ollama';
      case ApiProviderType.custom:
        return 'Custom Server';
    }
  }

  String get badgeLabel {
    switch (this) {
      case ApiProviderType.openai:
        return 'OPENAI';
      case ApiProviderType.lmStudio:
        return 'LM STUDIO';
      case ApiProviderType.ollama:
        return 'OLLAMA';
      case ApiProviderType.custom:
        return 'CUSTOM API';
    }
  }

  String get defaultBaseUrl {
    switch (this) {
      case ApiProviderType.openai:
        return 'https://api.openai.com/v1';
      case ApiProviderType.lmStudio:
        return 'http://localhost:1234/v1';
      case ApiProviderType.ollama:
        return 'http://localhost:11434';
      case ApiProviderType.custom:
        return 'http://localhost:8080/v1';
    }
  }

  bool get requiresApiKey => this == ApiProviderType.openai;

  static ApiProviderType fromString(String? value) {
    return ApiProviderType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => ApiProviderType.custom,
    );
  }
}

/// Enum to indicate API connection health status.
enum ConnectionStatus {
  connected,
  connecting,
  disconnecting,
  disconnected,
  error,
}

/// Abstract base class for all remote/server API model providers.
///
/// Behaves identically to a local GGUF model with:
/// - System prompt support (per-chat or global)
/// - Message history (user / assistant / system roles)
/// - Streaming token output & non-streaming completion fallback
/// - Connection validation & model discovery
abstract class AbstractApiModel {
  /// Unique identifier for this saved API model entry.
  final String id;

  /// User-facing display name.
  final String name;

  /// Provider type.
  final ApiProviderType providerType;

  /// Server base URL (e.g. https://api.openai.com/v1 or http://localhost:1234/v1).
  final String baseUrl;

  /// Optional API key / Bearer token.
  final String apiKey;

  /// Model identifier sent to the API server (e.g. gpt-4o-mini, llama-3.2-3b).
  final String modelId;

  /// Default system prompt for this model (overridden by chat/global prompt if set).
  final String systemPrompt;

  /// Default temperature for generation.
  final double defaultTemperature;

  /// Maximum context tokens supported by this provider.
  final int maxContextTokens;

  const AbstractApiModel({
    required this.id,
    required this.name,
    required this.providerType,
    required this.baseUrl,
    this.apiKey = '',
    required this.modelId,
    this.systemPrompt = '',
    this.defaultTemperature = 0.7,
    this.maxContextTokens = 128000,
  });

  /// Provider name (e.g., "OpenAI", "LM Studio", "Ollama").
  String get providerName => providerType.displayName;

  /// Whether the service supports streaming responses.
  bool get isStreamingSupported => true;

  /// Normalized base URL without trailing slashes.
  String get normalizedBaseUrl => baseUrl.trim().replaceAll(RegExp(r'/+$'), '');

  /// Build the target endpoint URL for chat completions.
  String buildConnectionUrl([Map<String, dynamic>? params]);

  /// Fetch available model IDs from the server (if supported).
  Future<List<String>> fetchAvailableModels();

  /// Validate server connectivity and return [ConnectionStatus].
  Future<ConnectionStatus> validateConnection();

  /// Send messages to the API and stream response text chunks.
  Stream<String> sendMessages(
    List<MessageModel> messages, {
    required String systemPrompt,
    double temperature = 0.7,
    bool isStreamingSupported = true,
    Map<String, dynamic>? additionalParams,
  });

  /// Get a single non-streaming completion.
  Future<String> sendCompletion(
    List<MessageModel> messages, {
    required String systemPrompt,
    double temperature = 0.7,
    Map<String, dynamic>? additionalParams,
  });

  /// Abort any active request and close/teardown the connection.
  Future<void> closeConnection();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'providerType': providerType.name,
        'baseUrl': baseUrl,
        'apiKey': apiKey,
        'modelId': modelId,
        'systemPrompt': systemPrompt,
        'defaultTemperature': defaultTemperature,
        'maxContextTokens': maxContextTokens,
      };

  @override
  String toString() => '$providerName: $name ($modelId @ $baseUrl)';
}
