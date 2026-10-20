import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/receipt_download.dart';
import '../../domain/entities/house_expense.dart';
import '../../domain/services/receipt_attachment_service.dart';

/// Modal sutil e não-bloqueante explicando a guarda de comprovantes para usuários Free.
class PremiumReceiptInfoSheet extends StatelessWidget {
  const PremiumReceiptInfoSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => const PremiumReceiptInfoSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.stars_rounded,
                    color: Color(0xFFF59E0B),
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Armazenamento de Comprovantes',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'Omni Lar Premium',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFB45309),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'A guarda em nuvem de cupons fiscais e notas de despesas é uma comodidade do plano Premium.\n\n'
              'No plano gratuito, você pode usar a leitura inteligente (IA) da câmera para extrair itens e valores automaticamente a qualquer momento, sem precisar salvar a foto original.\n\n'
              'No plano Premium, o arquivo original fica seguro e disponível para conferência e download durante o ciclo ativo e até 30 dias após o fechamento.',
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Entendi',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Visualizador interativo do comprovante anexado (remoto ou bytes locais).
class ReceiptViewerModal extends StatefulWidget {
  final String? attachmentPath;
  final Uint8List? localBytes;
  final String? attachmentName;
  final String? attachmentContentType;

  const ReceiptViewerModal({
    super.key,
    this.attachmentPath,
    this.localBytes,
    this.attachmentName,
    this.attachmentContentType,
  });

  static Future<void> show(
    BuildContext context, {
    String? attachmentPath,
    Uint8List? localBytes,
    String? attachmentName,
    String? attachmentContentType,
  }) {
    return showDialog(
      context: context,
      builder: (ctx) => ReceiptViewerModal(
        attachmentPath: attachmentPath,
        localBytes: localBytes,
        attachmentName: attachmentName,
        attachmentContentType: attachmentContentType,
      ),
    );
  }

  @override
  State<ReceiptViewerModal> createState() => _ReceiptViewerModalState();
}

class _ReceiptViewerModalState extends State<ReceiptViewerModal> {
  Future<String>? _signedUrlFuture;

  @override
  void initState() {
    super.initState();
    _loadUrl();
  }

  void _loadUrl() {
    if (widget.localBytes == null && widget.attachmentPath != null) {
      _signedUrlFuture = sl<ReceiptAttachmentService>().getSignedUrl(widget.attachmentPath!);
    }
  }

  bool get _isPdf =>
      widget.attachmentContentType == 'application/pdf' ||
      (widget.attachmentName?.toLowerCase().endsWith('.pdf') ?? false);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fileName = widget.attachmentName ?? 'comprovante';

    return Dialog(
      backgroundColor: theme.cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              child: Row(
                children: [
                  Icon(
                    _isPdf ? Icons.picture_as_pdf_rounded : Icons.receipt_long_rounded,
                    size: 20,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      fileName,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (_signedUrlFuture != null)
                    FutureBuilder<String>(
                      future: _signedUrlFuture,
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) return const SizedBox.shrink();
                        return IconButton(
                          icon: const Icon(Icons.download_rounded, size: 20),
                          tooltip: 'Baixar arquivo',
                          onPressed: () {
                            downloadReceiptFile(snapshot.data!, fileName);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Download iniciado.')),
                            );
                          },
                        );
                      },
                    ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    tooltip: 'Fechar',
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Content Viewer
            Expanded(
              child: _buildViewerContent(theme, fileName),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildViewerContent(ThemeData theme, String fileName) {
    if (widget.localBytes != null) {
      if (_isPdf) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.debtRed.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.picture_as_pdf_rounded,
                    size: 48,
                    color: AppColors.debtRed,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  fileName,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Documento em formato PDF pronto para envio.',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
        );
      }

      return Container(
        color: Colors.black.withValues(alpha: 0.05),
        child: InteractiveViewer(
          panEnabled: true,
          minScale: 0.8,
          maxScale: 4.0,
          child: Center(
            child: Image.memory(
              widget.localBytes!,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => const Center(
                child: Text('Erro ao carregar pré-visualização da imagem'),
              ),
            ),
          ),
        ),
      );
    }

    if (_signedUrlFuture == null) {
      return const Center(
        child: Text('Nenhum comprovante para exibir.', style: TextStyle(color: Colors.grey)),
      );
    }

    return FutureBuilder<String>(
      future: _signedUrlFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.broken_image_rounded, size: 48, color: Colors.grey),
                const SizedBox(height: 12),
                const Text(
                  'Não foi possível carregar o arquivo.',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
                const SizedBox(height: 12),
                TextButton.icon(
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Tentar novamente'),
                  onPressed: () => setState(_loadUrl),
                ),
              ],
            ),
          );
        }

        final url = snapshot.data!;

        if (_isPdf) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.debtRed.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.picture_as_pdf_rounded,
                      size: 48,
                      color: AppColors.debtRed,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    fileName,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Documento em formato PDF.',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: const Text('Abrir / Baixar PDF'),
                    onPressed: () => downloadReceiptFile(url, fileName),
                  ),
                ],
              ),
            ),
          );
        }

        return Container(
          color: Colors.black.withValues(alpha: 0.05),
          child: InteractiveViewer(
            panEnabled: true,
            minScale: 0.8,
            maxScale: 4.0,
            child: Center(
              child: Image.network(
                url,
                fit: BoxFit.contain,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Center(
                    child: CircularProgressIndicator(
                      value: loadingProgress.expectedTotalBytes != null
                          ? loadingProgress.cumulativeBytesLoaded /
                              loadingProgress.expectedTotalBytes!
                          : null,
                    ),
                  );
                },
                errorBuilder: (context, error, stackTrace) => const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline_rounded, size: 36, color: Colors.grey),
                      SizedBox(height: 8),
                      Text('Erro ao exibir imagem do comprovante', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Card embutido nos painéis de detalhe e modal da despesa.
class ReceiptAttachmentCard extends StatelessWidget {
  final HouseExpense expense;

  const ReceiptAttachmentCard({super.key, required this.expense});

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Se o arquivo já foi expurgado conforme o Modelo A
    if (expense.isAttachmentPurged) {
      final purgedDate = DateFormat('dd/MM/yyyy').format(expense.attachmentPurgedAt!);
      return Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.auto_delete_outlined, size: 18, color: Colors.grey),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Comprovante expurgado em $purgedDate (retenção de 30 dias após o ciclo). '
                'Os valores e dados da despesa continuam integralmente salvos.',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ),
          ],
        ),
      );
    }

    if (!expense.hasAttachment) {
      return const SizedBox.shrink();
    }

    final isPdf = expense.attachmentContentType == 'application/pdf' ||
        (expense.attachmentName?.toLowerCase().endsWith('.pdf') ?? false);
    final fileName = expense.attachmentName ?? 'comprovante_fiscal';
    final sizeText = expense.attachmentSizeBytes != null
        ? _formatBytes(expense.attachmentSizeBytes!)
        : null;

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              isPdf ? Icons.picture_as_pdf_rounded : Icons.receipt_long_rounded,
              size: 20,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fileName,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  sizeText != null ? 'Comprovante anexado • $sizeText' : 'Comprovante anexado',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: () {
              ReceiptViewerModal.show(
                context,
                attachmentPath: expense.attachmentPath!,
                attachmentName: expense.attachmentName,
                attachmentContentType: expense.attachmentContentType,
              );
            },
            child: const Text('Visualizar', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ),
          IconButton(
            icon: const Icon(Icons.download_rounded, size: 18),
            tooltip: 'Baixar comprovante',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () async {
              try {
                final url = await sl<ReceiptAttachmentService>().getSignedUrl(expense.attachmentPath!);
                downloadReceiptFile(url, fileName);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Download do comprovante iniciado.')),
                  );
                }
              } catch (_) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Não foi possível gerar link de download.')),
                  );
                }
              }
            },
          ),
        ],
      ),
    );
  }
}
