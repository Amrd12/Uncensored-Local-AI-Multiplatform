import 'api_models/abstract_api_model.dart';
import 'api_models/api_model_factory.dart';

/// Represents a downloadable/loadable AI model from the catalog.
class AiModelInfo {
  final String id;
  final String name;
  final String filename;
  final String url;
  final double sizeGb;
  final int minRamGb;
  final String label;        // UNCENSORED / STANDARD / CUSTOM / API
  final String badge;        // RECOMMENDED, HERETIC, OPENAI, LM STUDIO, etc.
  final String systemPrompt;
  final bool recommended;
  final Map<String, dynamic>? apiConfig;

  const AiModelInfo({
    required this.id,
    required this.name,
    required this.filename,
    required this.url,
    required this.sizeGb,
    required this.minRamGb,
    required this.label,
    required this.badge,
    required this.systemPrompt,
    this.recommended = false,
    this.apiConfig,
  });

  factory AiModelInfo.fromJson(Map<String, dynamic> json) {
    final rawApi = json['apiConfig'];
    return AiModelInfo(
      id: json['id'] as String,
      name: json['name'] as String,
      filename: json['filename'] as String,
      url: json['url'] as String,
      sizeGb: (json['sizeGb'] as num).toDouble(),
      minRamGb: (json['minRamGb'] as num).toInt(),
      label: json['label'] as String? ?? 'STANDARD',
      badge: json['badge'] as String? ?? '',
      systemPrompt: json['systemPrompt'] as String? ?? '',
      recommended: json['recommended'] as bool? ?? false,
      apiConfig: rawApi is Map ? Map<String, dynamic>.from(rawApi) : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'filename': filename,
        'url': url,
        'sizeGb': sizeGb,
        'minRamGb': minRamGb,
        'label': label,
        'badge': badge,
        'systemPrompt': systemPrompt,
        'recommended': recommended,
        if (apiConfig != null) 'apiConfig': apiConfig,
      };

  bool get isUncensored => label == 'UNCENSORED';
  bool get isStandard => label == 'STANDARD';
  bool get isCustom => label == 'CUSTOM';
  bool get isApiModel => label == 'API' || apiConfig != null;

  AbstractApiModel? toApiModel() {
    if (apiConfig == null) return null;
    return ApiModelFactory.fromJson(apiConfig!);
  }
}
