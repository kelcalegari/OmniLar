import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'offline_snapshot.dart';

/// Faixa no topo enquanto o app mostra a cópia local (sem internet).
class OfflineBanner extends StatelessWidget {
  final Widget child;
  final OfflineSnapshot? snapshot;

  const OfflineBanner({super.key, required this.child, this.snapshot});

  @override
  Widget build(BuildContext context) {
    final source = snapshot ?? OfflineSnapshot.instance;
    return ValueListenableBuilder<DateTime?>(
      valueListenable: source.showingSince,
      builder: (context, since, _) {
        if (since == null) return child;
        return Column(
          children: [
            Material(
              color: Colors.orange.shade700,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Row(
                    children: [
                      const Icon(Icons.cloud_off_rounded, size: 16, color: Colors.white),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Sem internet — mostrando os dados de ${DateFormat("dd/MM 'às' HH:mm").format(since)}',
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(child: MediaQuery.removePadding(context: context, removeTop: true, child: child)),
          ],
        );
      },
    );
  }
}
