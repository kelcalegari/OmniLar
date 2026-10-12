import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/responsive.dart';
import '../../../../core/widgets/responsive_container.dart';

class HomeSkeleton extends StatefulWidget {
  const HomeSkeleton({super.key});

  @override
  State<HomeSkeleton> createState() => _HomeSkeletonState();
}

class _HomeSkeletonState extends State<HomeSkeleton>
    with SingleTickerProviderStateMixin {
  late AnimationController _shimmerController;
  late Animation<double> _shimmerAnimation;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _shimmerAnimation = CurvedAnimation(
      parent: _shimmerController,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isDesktop = context.isDesktop;

    final baseColor = isDark
        ? const Color(0xFF1E293B)
        : const Color(0xFFF1F5F9);
    final highlightColor = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFE2E8F0);

    return AnimatedBuilder(
      animation: _shimmerAnimation,
      builder: (context, child) {
        final color = Color.lerp(baseColor, highlightColor, _shimmerAnimation.value)!;

        return SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          child: ResponsiveContainer(
            child: isDesktop
                ? _buildDesktopSkeleton(context, color, isDark)
                : _buildMobileSkeleton(context, color, isDark),
          ),
        );
      },
    );
  }

  Widget _buildMobileSkeleton(BuildContext context, Color boneColor, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Fôlego Gauge Card Placeholder
        _buildBox(height: 220, borderRadius: 20, color: boneColor),
        const SizedBox(height: 16),
        // Super Pix / Fechamento Card Placeholder
        _buildBox(height: 110, borderRadius: 16, color: boneColor),
        const SizedBox(height: 16),
        // Atalhos da Rotina Placeholder
        Row(
          children: [
            Expanded(child: _buildBox(height: 72, borderRadius: 14, color: boneColor)),
            const SizedBox(width: 12),
            Expanded(child: _buildBox(height: 72, borderRadius: 14, color: boneColor)),
            const SizedBox(width: 12),
            Expanded(child: _buildBox(height: 72, borderRadius: 14, color: boneColor)),
          ],
        ),
        const SizedBox(height: 24),
        // Despesas Recentes Placeholder
        _buildExpenseListSkeleton(boneColor),
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _buildDesktopSkeleton(BuildContext context, Color boneColor, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Coluna Esquerda: Cards Financeiros
            Expanded(
              flex: 4,
              child: Column(
                children: [
                  _buildBox(height: 230, borderRadius: 20, color: boneColor),
                  const SizedBox(height: 16),
                  _buildBox(height: 100, borderRadius: 16, color: boneColor),
                  const SizedBox(height: 16),
                  _buildBox(height: 110, borderRadius: 16, color: boneColor),
                ],
              ),
            ),
            const SizedBox(width: 24),
            // Coluna Direita: Gastos do Ciclo
            Expanded(
              flex: 5,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B).withValues(alpha: 0.3) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.grey.withValues(alpha: 0.12),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildBox(width: 160, height: 22, borderRadius: 6, color: boneColor),
                    const SizedBox(height: 20),
                    _buildExpenseListSkeleton(boneColor, count: 5),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildExpenseListSkeleton(Color boneColor, {int count = 3}) {
    return Column(
      children: List.generate(count, (index) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              _buildBox(width: 44, height: 44, borderRadius: 12, color: boneColor),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildBox(width: 140, height: 16, borderRadius: 4, color: boneColor),
                    const SizedBox(height: 6),
                    _buildBox(width: 80, height: 12, borderRadius: 4, color: boneColor),
                  ],
                ),
              ),
              _buildBox(width: 68, height: 18, borderRadius: 4, color: boneColor),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildBox({
    double? width,
    required double height,
    required double borderRadius,
    required Color color,
  }) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}
