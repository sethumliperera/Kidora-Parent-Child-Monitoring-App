import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/modern_background.dart';
import '../widgets/glass_card.dart';

class ReminderAlertScreen extends StatelessWidget {
  final String title;
  final String message;
  final String priority;

  const ReminderAlertScreen({
    super.key,
    required this.title,
    required this.message,
    required this.priority,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isUrgent = priority.toLowerCase() == 'urgent';
    final accent = isUrgent ? AppTheme.errorColor : AppTheme.primaryColor;
    final subtitle = isUrgent
        ? 'Urgent reminder from your parent'
        : 'Reminder from your parent';

    return PopScope(
      canPop: false,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        body: ModernBackground(
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: isDark ? 0.22 : 0.14),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: accent.withValues(alpha: 0.55)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isUrgent
                              ? Icons.priority_high_rounded
                              : Icons.notifications_none_rounded,
                          color: accent,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isUrgent ? 'URGENT' : 'NORMAL',
                          style: TextStyle(
                            color: accent,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  GlassCard(
                    padding: const EdgeInsets.all(26),
                    borderRadius: 36,
                    color: accent.withValues(alpha: isUrgent ? 0.26 : 0.12),
                    child: Icon(
                      isUrgent
                          ? Icons.warning_rounded
                          : Icons.notifications_active_rounded,
                      size: 72,
                      color: accent,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    title.trim().isEmpty ? 'Reminder' : title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                      color: isDark ? Colors.white : AppTheme.lightTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: accent,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    message.trim().isEmpty ? 'You have a new reminder.' : message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.white70,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 40),
                  SizedBox(
                    width: double.infinity,
                    height: 58,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.white,
                        side: BorderSide(
                          color: accent.withValues(alpha: isDark ? 0.9 : 0.8),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                        elevation: 4,
                        shadowColor: accent.withValues(alpha: 0.35),
                      ),
                      child: Text(
                        isUrgent ? 'Acknowledge Urgent Reminder' : 'Dismiss',
                        style: TextStyle(
                          fontSize: isUrgent ? 16 : 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}