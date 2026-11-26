import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../message_model.dart';
import 'abstract_api_model.dart';

/// Ollama API provider.
///
/// Supports Ollama's native `/api/chat` NDJSON streaming and `/api/tags` model
/// discovery (default `http://localhost:11434`).
class OllamaApiModel extends AbstractApiModel {
  http.Client? _activeClient;

  OllamaApiModel({
    required super.id,
    required super.name,
    super.baseUrl = 'http://localhost:11434',
    super.apiKey = '',
    required super.modelId,
    super.systemPrompt = '',
    super.defaultTemperature = 0.7,
    super.maxContextTokens = 128000,
  }) : super(providerType: ApiProviderType.ollama);

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (apiKey.trim().isNotEmpty) 'Authorization': 'Bearer ${apiKey.trim()}',
      };

  String get _rootUrl {
    final base = normalizedBaseUrl;
    if (base.endsWith('/v1')) {
      return base.substring(0, base.length - 3);
    }
    return base;
  }

  @override
  String buildConnectionUrl([Map<String, dynamic>? params]) {
    final overrideBase = (params?['baseUrl'] as String?)?.trim();
    final base = (overrideBase != null && overrideBase.isNotEmpty)
        ? overrideBase.replaceAll(RegExp(r'/+$'), '')
        : _rootUrl;
    if (base.endsWith('/api/chat')) return base;
    return '$base/api/chat';
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
          .get(Uri.parse('$_rootUrl/api/tags'), headers: _headers)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic> && decoded['models'] is List) {
          final models = <String>[];
          for (final item in decoded['models'] as List) {
            if (item is Map && item['name'] != null) {
              models.add(item['name'].toString());
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
          .get(Uri.parse('$_rootUrl/api/tags'), headers: _headers)
          .timeout(const Duration(seconds: 8));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return ConnectionStatus.connected;
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
        'stream': true,
        'options': {'temperature': temperature},
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
        throw Exception('Ollama API error (${response.statusCode}): $errorBody');
      }

      final lineStream = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      await for (final line in lineStream) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;

        try {
          final jsonMap = jsonDecode(trimmed) as Map<String, dynamic>;
          final message = jsonMap['message'] as Map<String, dynamic>?;
          final content = message?['content'] as String?;
          if (content != null && content.isNotEmpty) {
            yield content;
          }
          if (jsonMap['done'] == true) break;
        } catch (_) {
          // Ignore malformed lines
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
        'stream': false,
        'options': {'temperature': temperature},
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
          'Ollama API error (${response.statusCode}): ${response.body}',
        );
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final message = decoded['message'] as Map<String, dynamic>?;
      return message?['content']?.toString() ?? '';
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
}
