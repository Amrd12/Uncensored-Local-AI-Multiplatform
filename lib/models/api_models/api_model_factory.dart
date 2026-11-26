import 'abstract_api_model.dart';
import 'lm_studio_provider.dart';
import 'ollama_provider.dart';
import 'openai_provider.dart';

/// Factory for creating concrete [AbstractApiModel] instances from configuration.
class ApiModelFactory {
  static AbstractApiModel create({
    required String id,
    required String name,
    required ApiProviderType providerType,
    required String baseUrl,
    String apiKey = '',
    required String modelId,
    String systemPrompt = '',
    double defaultTemperature = 0.7,
    int maxContextTokens = 128000,
  }) {
    final effectiveUrl =
        baseUrl.trim().isEmpty ? providerType.defaultBaseUrl : baseUrl.trim();

    switch (providerType) {
      case ApiProviderType.openai:
        return OpenAiApiModel(
          id: id,
          name: name,
          baseUrl: effectiveUrl,
          apiKey: apiKey,
          modelId: modelId,
          systemPrompt: systemPrompt,
          defaultTemperature: defaultTemperature,
          maxContextTokens: maxContextTokens,
        );
      case ApiProviderType.lmStudio:
        return LmStudioApiModel(
          id: id,
          name: name,
          baseUrl: effectiveUrl,
          apiKey: apiKey,
          modelId: modelId,
          systemPrompt: systemPrompt,
          defaultTemperature: defaultTemperature,
          maxContextTokens: maxContextTokens,
        );
      case ApiProviderType.ollama:
        return OllamaApiModel(
          id: id,
          name: name,
          baseUrl: effectiveUrl,
          apiKey: apiKey,
          modelId: modelId,
          systemPrompt: systemPrompt,
          defaultTemperature: defaultTemperature,
          maxContextTokens: maxContextTokens,
        );
      case ApiProviderType.custom:
        return CustomApiModel(
          id: id,
          name: name,
          baseUrl: effectiveUrl,
          apiKey: apiKey,
          modelId: modelId,
          systemPrompt: systemPrompt,
          defaultTemperature: defaultTemperature,
          maxContextTokens: maxContextTokens,
        );
    }
  }

  static AbstractApiModel fromJson(Map<String, dynamic> json) {
    final providerType =
        ApiProviderType.fromString(json['providerType'] as String?);
    return create(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      providerType: providerType,
      baseUrl: json['baseUrl'] as String? ?? providerType.defaultBaseUrl,
      apiKey: json['apiKey'] as String? ?? '',
      modelId: json['modelId'] as String? ?? '',
      systemPrompt: json['systemPrompt'] as String? ?? '',
      defaultTemperature:
          (json['defaultTemperature'] as num?)?.toDouble() ?? 0.7,
      maxContextTokens:
          (json['maxContextTokens'] as num?)?.toInt() ?? 128000,
    );
  }
}
