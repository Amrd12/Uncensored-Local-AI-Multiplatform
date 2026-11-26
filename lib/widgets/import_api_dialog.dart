import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/model_controller.dart';
import '../models/api_models/abstract_api_model.dart';
import '../models/api_models/api_model_factory.dart';
import '../theme/app_colors.dart';

/// Dialog for connecting an external or local API model (OpenAI, LM Studio,
/// Ollama, or any OpenAI-compatible server).
class ImportApiDialog extends StatefulWidget {
  final ModelController ctrl;

  const ImportApiDialog({super.key, required this.ctrl});

  @override
  State<ImportApiDialog> createState() => _ImportApiDialogState();
}

class _ImportApiDialogState extends State<ImportApiDialog> {
  ApiProviderType _provider = ApiProviderType.lmStudio;
  final _nameCtrl = TextEditingController();
  final _baseUrlCtrl =
      TextEditingController(text: ApiProviderType.lmStudio.defaultBaseUrl);
  final _apiKeyCtrl = TextEditingController();
  final _modelIdCtrl = TextEditingController();
  final _systemPromptCtrl = TextEditingController();

  bool _obscureKey = true;
  bool _isTesting = false;
  bool _autoLoad = true;
  ConnectionStatus? _status;
  String? _statusMessage;
  List<String> _fetchedModels = [];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _baseUrlCtrl.dispose();
    _apiKeyCtrl.dispose();
    _modelIdCtrl.dispose();
    _systemPromptCtrl.dispose();
    super.dispose();
  }

  void _selectProvider(ApiProviderType type) {
    final prevDefault = _provider.defaultBaseUrl;
    setState(() {
      _provider = type;
      if (_baseUrlCtrl.text.trim().isEmpty ||
          _baseUrlCtrl.text.trim() == prevDefault) {
        _baseUrlCtrl.text = type.defaultBaseUrl;
      }
      _status = null;
      _statusMessage = null;
      _fetchedModels = [];
    });
  }

  Future<void> _testAndFetchModels() async {
    final baseUrl = _baseUrlCtrl.text.trim();
    if (baseUrl.isEmpty || !baseUrl.startsWith('http')) {
      setState(() {
        _status = ConnectionStatus.error;
        _statusMessage = 'Enter a valid http:// or https:// URL';
      });
      return;
    }

    setState(() {
      _isTesting = true;
      _status = ConnectionStatus.connecting;
      _statusMessage = 'Connecting...';
      _fetchedModels = [];
    });

    try {
      final probe = ApiModelFactory.create(
        id: 'probe',
        name: 'Probe',
        providerType: _provider,
        baseUrl: baseUrl,
        apiKey: _apiKeyCtrl.text.trim(),
        modelId: _modelIdCtrl.text.trim().isNotEmpty
            ? _modelIdCtrl.text.trim()
            : 'default',
      );

      final connStatus = await probe.validateConnection();
      List<String> models = [];
      if (connStatus == ConnectionStatus.connected) {
        try {
          models = await probe.fetchAvailableModels();
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() {
        _status = connStatus;
        _fetchedModels = models;
        if (connStatus == ConnectionStatus.connected) {
          _statusMessage = models.isNotEmpty
              ? 'Connected • ${models.length} model(s) found'
              : 'Connected to server';
          if (_modelIdCtrl.text.trim().isEmpty && models.isNotEmpty) {
            _modelIdCtrl.text = models.first;
          }
        } else {
          _statusMessage = 'Could not verify endpoint (check URL or API key)';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = ConnectionStatus.error;
        _statusMessage = 'Connection failed: $e';
      });
    } finally {
      if (mounted) {
        setState(() => _isTesting = false);
      }
    }
  }

  Future<void> _save() async {
    final baseUrl = _baseUrlCtrl.text.trim();
    final modelId = _modelIdCtrl.text.trim();
    final apiKey = _apiKeyCtrl.text.trim();

    if (baseUrl.isEmpty || !baseUrl.startsWith('http')) {
      Get.snackbar(
        'Invalid URL',
        'Base URL must start with http:// or https://',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    if (modelId.isEmpty) {
      Get.snackbar(
        'Missing Model ID',
        'Enter or select a model ID (e.g. gpt-4o-mini or llama-3.2-3b).',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    if (_provider.requiresApiKey && apiKey.isEmpty) {
      Get.snackbar(
        'API Key Required',
        'OpenAI requires an API key.',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    Get.back();
    await widget.ctrl.addApiModel(
      name: _nameCtrl.text.trim(),
      providerType: _provider,
      baseUrl: baseUrl,
      apiKey: apiKey,
      modelId: modelId,
      systemPrompt: _systemPromptCtrl.text.trim(),
      autoLoad: _autoLoad,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: context.bgPanel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Icon(Icons.cloud_queue_rounded,
              color: AppColors.accent, size: 22),
          const SizedBox(width: 8),
          Text(
            'Import from API',
            style: TextStyle(color: context.text, fontSize: 18),
          ),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Provider',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: context.textM,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ApiProviderType.values.map((type) {
                  final selected = _provider == type;
                  return ChoiceChip(
                    label: Text(
                      type.displayName,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w400,
                        color: selected ? Colors.white : context.textM,
                      ),
                    ),
                    selected: selected,
                    onSelected: (_) => _selectProvider(type),
                    selectedColor: AppColors.accent,
                    backgroundColor: context.bgInput,
                    side: BorderSide(
                      color: selected ? AppColors.accent : context.border,
                    ),
                    showCheckmark: false,
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),
              _buildTextField(
                context,
                controller: _baseUrlCtrl,
                label: 'Server Base URL',
                hint: _provider.defaultBaseUrl,
              ),
              const SizedBox(height: 12),
              _buildTextField(
                context,
                controller: _apiKeyCtrl,
                label: _provider.requiresApiKey
                    ? 'API Key'
                    : 'API Key (Optional)',
                hint: 'sk-...',
                obscureText: _obscureKey,
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureKey
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 18,
                    color: context.textD,
                  ),
                  onPressed: () => setState(() => _obscureKey = !_obscureKey),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _isTesting ? null : _testAndFetchModels,
                    icon: _isTesting
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.sync_rounded, size: 16),
                    label: Text(
                      _isTesting ? 'Checking...' : 'Test & Fetch Models',
                      style: const TextStyle(fontSize: 12),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.accentHi,
                      side: const BorderSide(color: AppColors.accent),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  if (_statusMessage != null) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _statusMessage!,
                        style: TextStyle(
                          fontSize: 11,
                          color: _status == ConnectionStatus.connected
                              ? AppColors.green
                              : _status == ConnectionStatus.connecting
                                  ? AppColors.orange
                                  : AppColors.red,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
              if (_fetchedModels.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  'Available Models (tap to select):',
                  style: TextStyle(fontSize: 11, color: context.textD),
                ),
                const SizedBox(height: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 110),
                  child: SingleChildScrollView(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: _fetchedModels.map((m) {
                        final isPicked = _modelIdCtrl.text.trim() == m;
                        return ActionChip(
                          label: Text(
                            m,
                            style: TextStyle(
                              fontSize: 11,
                              color: isPicked ? Colors.white : context.text,
                            ),
                          ),
                          backgroundColor:
                              isPicked ? AppColors.accent : context.bgInput,
                          side: BorderSide(
                            color:
                                isPicked ? AppColors.accent : context.border,
                          ),
                          onPressed: () {
                            setState(() {
                              _modelIdCtrl.text = m;
                            });
                          },
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              _buildTextField(
                context,
                controller: _modelIdCtrl,
                label: 'Model ID',
                hint: _provider == ApiProviderType.openai
                    ? 'e.g. gpt-4o-mini'
                    : _provider == ApiProviderType.ollama
                        ? 'e.g. llama3.2:latest'
                        : 'e.g. local-model',
              ),
              const SizedBox(height: 12),
              _buildTextField(
                context,
                controller: _nameCtrl,
                label: 'Display Name (Optional)',
                hint: 'Defaults to Model ID if empty',
              ),
              const SizedBox(height: 12),
              _buildTextField(
                context,
                controller: _systemPromptCtrl,
                label: 'System Prompt Override (Optional)',
                hint: 'Leave empty to use your global/chat system prompt',
                maxLines: 2,
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                value: _autoLoad,
                onChanged: (v) => setState(() => _autoLoad = v ?? true),
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                activeColor: AppColors.accent,
                title: Text(
                  'Activate model immediately after saving',
                  style: TextStyle(fontSize: 12, color: context.textM),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Get.back(),
          child: Text('Cancel', style: TextStyle(color: context.textD)),
        ),
        ElevatedButton(
          onPressed: _save,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.accent,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: const Text(
            'Save & Connect',
            style: TextStyle(color: Colors.white),
          ),
        ),
      ],
    );
  }

  Widget _buildTextField(
    BuildContext context, {
    required TextEditingController controller,
    required String label,
    required String hint,
    bool obscureText = false,
    int maxLines = 1,
    Widget? suffixIcon,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      maxLines: obscureText ? 1 : maxLines,
      style: TextStyle(color: context.text, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: context.textD, fontSize: 12),
        hintText: hint,
        hintStyle: TextStyle(color: context.textD.withValues(alpha: 0.5)),
        filled: true,
        fillColor: context.bgInput,
        suffixIcon: suffixIcon,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: context.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: context.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.accent),
        ),
      ),
    );
  }
}
