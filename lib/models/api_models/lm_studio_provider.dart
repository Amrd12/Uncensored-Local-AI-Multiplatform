import 'abstract_api_model.dart';
import 'openai_provider.dart';

/// LM Studio API provider.
///
/// Connects to a local or LAN LM Studio server (default `http://localhost:1234/v1`)
/// using its OpenAI-compatible `/v1/chat/completions` and `/v1/models` endpoints.
class LmStudioApiModel extends OpenAiApiModel {
  LmStudioApiModel({
    required super.id,
    required super.name,
    super.baseUrl = 'http://localhost:1234/v1',
    super.apiKey = '',
    required super.modelId,
    super.systemPrompt = '',
    super.defaultTemperature = 0.7,
    super.maxContextTokens = 128000,
  }) : super(providerType: ApiProviderType.lmStudio);
}
