import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../message_model.dart';
import 'abstract_api_model.dart';

/// OpenAI and OpenAI-compatible API provider.
///
/// Works with OpenAI, OpenRouter, Groq, Together, vLLM, llama.cpp server,
/// LocalAI, KoboldCpp, and any server exposing `/v1/chat/completions` and `/v1/models`.
class OpenAiApiModel extends AbstractApiModel {
  http.Client? _activeClient;

  OpenAiApiModel({
    required super.id,
    required super.name,
    super.providerType = ApiProviderType.openai,
    super.baseUrl = 'https://api.openai.com/v1',
    super.apiKey = '',
    required super.modelId,
    super.systemPrompt = '',
    super.defaultTemperature = 0.7,
    super.maxContextTokens = 128000,
  });

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (apiKey.trim().isNotEmpty) 'Authorization': 'Bearer ${apiKey.trim()}',
      };

  @override
  String buildConnectionUrl([Map<String, dynamic>? params]) {
    final overrideBase = (params?['baseUrl'] as String?)?.trim();
    final base = (overrideBase != null && overrideBase.isNotEmpty)
        ? overrideBase.replaceAll(RegExp(r'/+$'), '')
        : normalizedBaseUrl;
    if (base.endsWith('/chat/completions')) return base;
    return '$base/chat/completions';
  }

  String _modelsUrl() {
    final base = normalizedBaseUrl;
    if (base.endsWith('/models')) return base;
    if (base.endsWith('/chat/completions')) {
      return '${base.substring(0, base.length - '/chat/completions'.length)}/models';
    }
    return '$base/models';
  }

  List<Map<String, dynamic>> _buildFormattedMessages(
    List<MessageModel> messages,
    String effectiveSystemPrompt,
  ) {
    final formatted = <Map<String, dynamic>>[];

    final promptToUse = effectiveSystemPrompt.trim().isNotEmpty
        ? effectiveSystemPrompt.trim()
        : systemPrompt.trim();

    if (promptToUse.isNotEmpty) {
      formatted.add({'role': 'system', 'content': promptToUse});
    }

    for (final msg in messages) {
      if (msg.isUser) {
        formatted.add({'role': 'user', 'content': msg.content});
      } else if (msg.isAssistant && msg.content.isNotEmpty) {
        formatted.add({'role': 'assistant', 'content': msg.content});
      } else if (msg.isSystem && promptToUse.isEmpty && msg.content.isNotEmpty) {
        formatted.add({'role': 'system', 'content': msg.content});
      }
    }

    return formatted;
  }

  @override
  Future<List<String>> fetchAvailableModels() async {
    final client = http.Client();
    try {
      final response = await client
          .get(Uri.parse(_modelsUrl()), headers: _headers)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic> && decoded['data'] is List) {
          final models = <String>[];
          for (final item in decoded['data'] as List) {
            if (item is Map && item['id'] != null) {
              models.add(item['id'].toString());
            }
          }
          return models;
        }
      }
      return [];
    } finally {
      client.close();
    }
  }

  @override
  Future<ConnectionStatus> validateConnection() async {
    final client = http.Client();
    try {
      final response = await client
          .get(Uri.parse(_modelsUrl()), headers: _headers)
          .timeout(const Duration(seconds: 8));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return ConnectionStatus.connected;
      }
      if (response.statusCode == 401 || response.statusCode == 403) {
        return ConnectionStatus.error;
      }
      return ConnectionStatus.disconnected;
    } catch (_) {
      return ConnectionStatus.error;
    } finally {
      client.close();
    }
  }

  @override
  Stream<String> sendMessages(
    List<MessageModel> messages, {
    required String systemPrompt,
    double temperature = 0.7,
    bool isStreamingSupported = true,
    Map<String, dynamic>? additionalParams,
  }) async* {
    if (!isStreamingSupported) {
      final full = await sendCompletion(
        messages,
        systemPrompt: systemPrompt,
        temperature: temperature,
        additionalParams: additionalParams,
      );
      if (full.isNotEmpty) yield full;
      return;
    }

    await closeConnection();
    final client = http.Client();
    _activeClient = client;

    try {
      final payload = <String, dynamic>{
        'model': modelId,
        'messages': _buildFormattedMessages(messages, systemPrompt),
        'temperature': temperature,
        'stream': true,
        if (additionalParams != null) ...additionalParams,
      };

      final request = http.Request(
        'POST',
        Uri.parse(buildConnectionUrl(additionalParams)),
      );
      request.headers.addAll(_headers);
      request.body = jsonEncode(payload);

      final response =
          await client.send(request).timeout(const Duration(seconds: 60));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final errorBody = await response.stream.bytesToString();
        throw Exception(
          'API error (${response.statusCode}): ${_extractErrorMessage(errorBody)}',
        );
      }

      final contentType = response.headers['content-type'] ?? '';
      if (contentType.contains('application/json')) {
        // Server returned non-streaming JSON despite stream: true
        final body = await response.stream.bytesToString();
        final decoded = jsonDecode(body) as Map<String, dynamic>;
        final content = _extractCompletionContent(decoded);
        if (content.isNotEmpty) yield content;
        return;
      }

      // Parse SSE stream line by line
      final lineStream = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      await for (final line in lineStream) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || trimmed.startsWith(':')) continue;
        if (!trimmed.startsWith('data:')) continue;

        final dataStr = trimmed.substring(5).trim();
        if (dataStr == '[DONE]') break;

        try {
          final jsonMap = jsonDecode(dataStr) as Map<String, dynamic>;
          final choices = jsonMap['choices'] as List?;
          if (choices == null || choices.isEmpty) continue;

          final first = choices.first as Map<String, dynamic>;
          final delta = first['delta'] as Map<String, dynamic>?;
          final content = delta?['content'] as String?;
          if (content != null && content.isNotEmpty) {
            yield content;
          }
        } catch (_) {
          // Ignore malformed keep-alive or partial SSE lines
        }
      }
    } finally {
      if (_activeClient == client) {
        _activeClient = null;
      }
      client.close();
    }
  }

  @override
  Future<String> sendCompletion(
    List<MessageModel> messages, {
    required String systemPrompt,
    double temperature = 0.7,
    Map<String, dynamic>? additionalParams,
  }) async {
    await closeConnection();
    final client = http.Client();
    _activeClient = client;

    try {
      final payload = <String, dynamic>{
        'model': modelId,
        'messages': _buildFormattedMessages(messages, systemPrompt),
        'temperature': temperature,
        'stream': false,
        if (additionalParams != null) ...additionalParams,
      };

      final response = await client
          .post(
            Uri.parse(buildConnectionUrl(additionalParams)),
            headers: _headers,
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 120));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          'API error (${response.statusCode}): ${_extractErrorMessage(response.body)}',
        );
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      return _extractCompletionContent(decoded);
    } finally {
      if (_activeClient == client) {
        _activeClient = null;
      }
      client.close();
    }
  }

  @override
  Future<void> closeConnection() async {
    _activeClient?.close();
    _activeClient = null;
  }

  String _extractCompletionContent(Map<String, dynamic> decoded) {
    final choices = decoded['choices'] as List?;
    if (choices == null || choices.isEmpty) return '';
    final first = choices.first as Map<String, dynamic>;
    final message = first['message'] as Map<String, dynamic>?;
    if (message != null && message['content'] != null) {
      return message['content'].toString();
    }
    if (first['text'] != null) {
      return first['text'].toString();
    }
    return '';
  }

  String _extractErrorMessage(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['error'] is Map) {
        final msg = decoded['error']['message'];
        if (msg != null) return msg.toString();
      }
      if (decoded is Map && decoded['message'] != null) {
        return decoded['message'].toString();
      }
    } catch (_) {}
    return body.length > 200 ? '${body.substring(0, 200)}...' : body;
  }
}

/// Generic OpenAI-compatible server provider (vLLM, OpenRouter, Groq, llama.cpp, etc.).
class CustomApiModel extends OpenAiApiModel {
  CustomApiModel({
    required super.id,
    required super.name,
    required super.baseUrl,
    super.apiKey = '',
    required super.modelId,
    super.systemPrompt = '',
    super.defaultTemperature = 0.7,
    super.maxContextTokens = 128000,
  }) : super(providerType: ApiProviderType.custom);
}
