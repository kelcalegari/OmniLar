import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/services/ai_config_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/responsive.dart';

class AiKeyConfigSheet extends StatefulWidget {
  const AiKeyConfigSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showAdaptiveModal(
      context: context,
      maxWidth: 540,
      child: const AiKeyConfigSheet(),
    );
  }

  @override
  State<AiKeyConfigSheet> createState() => _AiKeyConfigSheetState();
}

class _AiKeyConfigSheetState extends State<AiKeyConfigSheet> {
  final _keyController = TextEditingController();
  String _selectedModel = AiConfigService.defaultModel;
  bool _obscureKey = true;
  bool _isLoading = true;
  bool _isTesting = false;
  bool _isSaving = false;
  String? _testResult;
  bool _testSuccess = false;
  bool _hasSavedKey = false;

  final _aiConfigService = sl<AiConfigService>();

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    final key = await _aiConfigService.getUserApiKey();
    final model = await _aiConfigService.getSelectedModel();

    if (mounted) {
      setState(() {
        if (key != null && key.isNotEmpty) {
          _keyController.text = key;
          _hasSavedKey = true;
        }
        _selectedModel = model;
        _isLoading = false;
      });
    }
  }

  Future<void> _testKey() async {
    final key = _keyController.text.trim();
    if (key.isEmpty) {
      setState(() {
        _testResult = 'Informe uma chave para testar.';
        _testSuccess = false;
      });
      return;
    }

    setState(() {
      _isTesting = true;
      _testResult = null;
    });

    final result = await _aiConfigService.testApiKey(key, _selectedModel);

    if (mounted) {
      setState(() {
        _isTesting = false;
        _testSuccess = result.isValid;
        _testResult = result.isValid
            ? 'Conexão estabelecida com sucesso! Modelo $_selectedModel respondeu perfeitamente.'
            : (result.errorMessage ?? 'Falha ao validar chave.');
      });
    }
  }

  Future<void> _saveConfig() async {
    final key = _keyController.text.trim();

    setState(() => _isSaving = true);

    await _aiConfigService.saveConfig(
      apiKey: key.isEmpty ? null : key,
      model: _selectedModel,
    );

    if (mounted) {
      setState(() {
        _isSaving = false;
        _hasSavedKey = key.isNotEmpty;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.creditGreen,
          content: Text(
            key.isNotEmpty
                ? 'Chave pessoal salva com sucesso! Modelo ativo: $_selectedModel 🧠✨'
                : 'Configurações salvas. Usando cota padrão do Omni Lar.',
          ),
        ),
      );
      Navigator.pop(context);
    }
  }

  Future<void> _removeKey() async {
    setState(() => _isSaving = true);
    await _aiConfigService.clearConfig();

    if (mounted) {
      setState(() {
        _keyController.clear();
        _hasSavedKey = false;
        _selectedModel = AiConfigService.defaultModel;
        _testResult = null;
        _isSaving = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.primary,
          content: Text('Chave removida. Usando cota padrão do Omni Lar.'),
        ),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.all(40),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Barra de arrastar
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Cabeçalho
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.auto_awesome_rounded, color: Colors.purple, size: 24),
                      SizedBox(width: 10),
                      Text(
                        'Chave de IA & Modelo (BYOK)',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Explicação da Versão Free e BYOK
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _hasSavedKey ? Icons.key_rounded : Icons.info_outline_rounded,
                          size: 18,
                          color: _hasSavedKey ? AppColors.creditGreen : AppColors.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _hasSavedKey ? 'Modo Chave Pessoal Ativo' : 'Cota Padrão Ativa (Modo Free/Trial)',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: _hasSavedKey ? AppColors.creditGreen : AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _hasSavedKey
                          ? 'Suas leituras de comprovantes e consultas usam sua cota própria do Google AI Studio de forma ilimitada.'
                          : 'Se você não cadastrar sua chave, o app utiliza a cota padrão compartilhada do Omni Lar (ou você pode ler boletos manualmente).',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Campo de Chave API
              TextField(
                controller: _keyController,
                obscureText: _obscureKey,
                decoration: InputDecoration(
                  labelText: 'Sua Chave de API do Google AI Studio',
                  hintText: 'AIzaSy...',
                  prefixIcon: const Icon(Icons.vpn_key_outlined),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(_obscureKey ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                        onPressed: () => setState(() => _obscureKey = !_obscureKey),
                        tooltip: 'Mostrar/ocultar chave',
                      ),
                      IconButton(
                        icon: const Icon(Icons.content_paste_rounded),
                        onPressed: () async {
                          final data = await Clipboard.getData('text/plain');
                          if (data?.text != null) {
                            _keyController.text = data!.text!.trim();
                          }
                        },
                        tooltip: 'Colar da área de transferência',
                      ),
                    ],
                  ),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Dica: Obtenha gratuitamente em aistudio.google.com (15 requisições/min sem custo).',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
              const SizedBox(height: 16),

              // Seletor de Modelo Gemini
              const Text(
                'Modelo Gemini',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'gemini-3.1-flash-lite',
                    label: Text('3.1 Lite (Rápido)'),
                    icon: Icon(Icons.bolt_rounded, size: 16),
                  ),
                  ButtonSegment(
                    value: 'gemini-3.8-flash',
                    label: Text('3.8 Flash'),
                    icon: Icon(Icons.speed_rounded, size: 16),
                  ),
                  ButtonSegment(
                    value: 'gemini-3.5-flash',
                    label: Text('3.5 Flash'),
                    icon: Icon(Icons.psychology_rounded, size: 16),
                  ),
                ],
                selected: {_selectedModel},
                onSelectionChanged: (set) {
                  setState(() {
                    _selectedModel = set.first;
                    _testResult = null;
                  });
                },
              ),
              const SizedBox(height: 12),

              // Feedback do Teste
              if (_testResult != null) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _testSuccess
                        ? AppColors.creditGreen.withValues(alpha: 0.1)
                        : AppColors.debtRed.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _testSuccess
                          ? AppColors.creditGreen.withValues(alpha: 0.4)
                          : AppColors.debtRed.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _testSuccess ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                        color: _testSuccess ? AppColors.creditGreen : AppColors.debtRed,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _testResult!,
                          style: TextStyle(
                            fontSize: 12,
                            color: _testSuccess ? AppColors.creditGreen : AppColors.debtRed,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Botão Testar Conexão
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: _isTesting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.network_check_rounded),
                label: Text(_isTesting ? 'Validando chave com o Google...' : 'Testar Conexão da Chave'),
                onPressed: _isTesting ? null : _testKey,
              ),
              const SizedBox(height: 12),

              // Botões Salvar e Remover
              Row(
                children: [
                  if (_hasSavedKey)
                    Expanded(
                      flex: 1,
                      child: TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.debtRed,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: _isSaving ? null : _removeKey,
                        child: const Text('Remover Chave'),
                      ),
                    ),
                  if (_hasSavedKey) const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _isSaving ? null : _saveConfig,
                      child: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : const Text(
                              'Salvar Configurações',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
