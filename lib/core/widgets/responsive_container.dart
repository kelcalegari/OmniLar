import 'package:flutter/material.dart';
import '../utils/responsive.dart';

class ResponsiveContainer extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry? padding;

  const ResponsiveContainer({
    required this.child,
    this.maxWidth = kMaxContentWidth,
    this.padding,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final horizontalPadding = context.isMobile ? 16.0 : 28.0;
    final effectivePadding = padding ?? EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 12.0);

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: effectivePadding,
          child: child,
        ),
      ),
    );
  }
}
