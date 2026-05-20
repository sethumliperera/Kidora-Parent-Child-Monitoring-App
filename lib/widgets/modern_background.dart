import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class ModernBackground extends StatelessWidget {
  final Widget child;

  const ModernBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Stack(
      children: [
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? const [
                        AppTheme.backdropGradientDarkTop,
                        AppTheme.backdropGradientDarkBottom,
                      ]
                    : const [
                        AppTheme.backdropGradientLightTop,
                        AppTheme.backdropGradientLightBottom,
                      ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ),

        // Main Content
        Positioned.fill(child: child),
      ],
    );
  }
}
