import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/app_state_provider.dart';
import 'glass_panel.dart';

class AppNotificationBanner extends StatelessWidget {
  const AppNotificationBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppStateProvider>(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    final message = appState.bannerMessage;
    final isError = appState.bannerIsError;

    return AnimatedCrossFade(
      firstChild: const SizedBox(width: double.infinity, height: 0),
      secondChild: message == null
          ? const SizedBox(width: double.infinity, height: 0)
          : Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: GlassPanel(
                borderRadius: 16,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                borderColor: isError
                    ? Colors.redAccent.withValues(alpha: 0.4)
                    : appState.accentColor.withValues(alpha: 0.4),
                fillColor: isError
                    ? Colors.redAccent.withValues(alpha: isDark ? 0.08 : 0.05)
                    : appState.accentColor.withValues(alpha: isDark ? 0.08 : 0.05),
                child: Row(
                  children: [
                    Icon(
                      isError ? Icons.error_outline_rounded : Icons.info_outline_rounded,
                      color: isError ? Colors.redAccent : appState.accentColor,
                      size: 22,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        message,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      style: IconButton.styleFrom(
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () {
                        appState.dismissBannerNotification();
                      },
                    ),
                  ],
                ),
              ),
            ),
      crossFadeState: message != null
          ? CrossFadeState.showSecond
          : CrossFadeState.showFirst,
      duration: const Duration(milliseconds: 250),
    );
  }
}
