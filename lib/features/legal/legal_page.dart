import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/responsive_container.dart';
import 'legal_texts.dart';

/// Página pública dos Termos de uso ou da Política de privacidade (sem login).
class LegalPage extends StatelessWidget {
  final LegalDocument document;

  const LegalPage({super.key, required this.document});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(document.title, style: const TextStyle(fontWeight: FontWeight.bold)),
        leading: Navigator.of(context).canPop()
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                tooltip: 'Voltar',
                onPressed: () => context.go('/'),
              ),
      ),
      body: ResponsiveContainer(
        maxWidth: 760,
        child: SelectionArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 48),
            children: [
              Text('Versão de $kLegalVersionLabel', style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey)),
              const SizedBox(height: 12),
              Text(document.intro, style: theme.textTheme.bodyLarge),
              for (final section in document.sections) ...[
                const SizedBox(height: 20),
                Text(section.title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                for (final paragraph in section.paragraphs) ...[
                  const SizedBox(height: 8),
                  Text(paragraph, style: theme.textTheme.bodyMedium?.copyWith(height: 1.5)),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
