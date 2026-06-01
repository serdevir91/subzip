import 'dart:ui';
import 'package:flutter/material.dart';

class GlassPanel extends StatelessWidget {
  final Widget child;
  final double blur;
  final double borderRadius;
  final Color borderColor;
  final Color fillColor;
  final EdgeInsetsGeometry padding;
  final double? width;
  final double? height;

  const GlassPanel({
    super.key,
    required this.child,
    this.blur = 15.0,
    this.borderRadius = 16.0,
    this.borderColor = const Color(0x1BFFFFFF),
    this.fillColor = const Color(0x0EFFFFFF),
    this.padding = const EdgeInsets.all(16.0),
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          width: width,
          height: height,
          padding: padding,
          decoration: BoxDecoration(
            color: fillColor,
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(
              color: borderColor,
              width: 1.0,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
