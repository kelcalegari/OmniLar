import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/utils/uuid.dart';

class ReceiptAttachmentFile {
  final String name;
  final Uint8List bytes;
  final int sizeBytes;
  final String contentType;

  const ReceiptAttachmentFile({
    required this.name,
    required this.bytes,
    required this.sizeBytes,
    required this.contentType,
  });

  bool get isPdf => contentType == 'application/pdf' || name.toLowerCase().endsWith('.pdf');
  bool get isImage => contentType.startsWith('image/');
}

class ReceiptAttachmentException implements Exception {
  final String message;
  const ReceiptAttachmentException(this.message);

  @override
  String toString() => message;
}

class ReceiptAttachmentService {
  final SupabaseClient? _client;

  ReceiptAttachmentService({SupabaseClient? client}) : _client = client;

  SupabaseClient get _supabase => _client ?? Supabase.instance.client;

  static const String bucketName = 'receipts';
  static const int maxSizeBytes = 10 * 1024 * 1024; // 10 MB

  /// Abre o seletor de arquivos do dispositivo (imagens e PDF).
  Future<ReceiptAttachmentFile?> pickReceiptFile() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
    );

    if (files.isEmpty) return null;

    final file = files.first;
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      throw const ReceiptAttachmentException('Não foi possível ler os dados do arquivo selecionado.');
    }

    if (bytes.length > maxSizeBytes) {
      throw const ReceiptAttachmentException('O arquivo excede o limite máximo de 10 MB.');
    }

    final ext = _extensionFromName(file.name);
    final contentType = _mimeTypeForExtension(ext);

    return ReceiptAttachmentFile(
      name: file.name,
      bytes: bytes,
      sizeBytes: bytes.length,
      contentType: contentType,
    );
  }

  /// Faz upload do arquivo para o bucket privado `receipts`.
  /// Caminho: `{houseId}/expenses/{expenseId}_{timestamp}.{ext}`
  Future<String> uploadReceipt({
    required String houseId,
    required ReceiptAttachmentFile file,
    String? expenseId,
  }) async {
    final ext = _extensionFromName(file.name);
    final targetExpenseId = expenseId ?? generateUuidV4();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final path = '$houseId/expenses/${targetExpenseId}_$timestamp.$ext';

    await _supabase.storage.from(bucketName).uploadBinary(
          path,
          file.bytes,
          fileOptions: FileOptions(
            contentType: file.contentType,
            upsert: true,
          ),
        );

    return path;
  }

  /// Gera uma URL assinada temporária para visualização/download do anexo privado.
  Future<String> getSignedUrl(String path, {int expiresInSeconds = 3600}) async {
    return await _supabase.storage.from(bucketName).createSignedUrl(path, expiresInSeconds);
  }

  /// Baixa os bytes do anexo diretamente da storage.
  Future<Uint8List> downloadReceipt(String path) async {
    return await _supabase.storage.from(bucketName).download(path);
  }

  /// Remove o anexo do bucket.
  Future<void> deleteReceipt(String path) async {
    try {
      await _supabase.storage.from(bucketName).remove([path]);
    } catch (_) {
      // Ignora falha se o arquivo já não existir
    }
  }

  static String _mimeTypeForExtension(String ext) {
    switch (ext) {
      case 'pdf':
        return 'application/pdf';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'jpg':
      case 'jpeg':
      default:
        return 'image/jpeg';
    }
  }

  static String _extensionFromName(String name) {
    final dot = name.lastIndexOf('.');
    if (dot != -1 && dot < name.length - 1) {
      return name.substring(dot + 1).toLowerCase();
    }
    return 'jpg';
  }
}
