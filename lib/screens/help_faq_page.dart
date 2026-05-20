import 'package:flutter/material.dart';
import '../widgets/modern_background.dart';
import '../widgets/glass_card.dart';
import '../theme/app_theme.dart';

class HelpFaqPage extends StatelessWidget {
  const HelpFaqPage({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 22,
            color: isDark ? Colors.white : AppTheme.lightTextPrimary,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          "Help & FAQ",
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: isDark ? Colors.white : AppTheme.lightTextPrimary,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ModernBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: const [
                _FaqItem(
                  question: "How do I link my child device?",
                  answer:
                      "Open the child app and tap Link Device. Then enter the 6-digit pairing code generated from the parent app.",
                ),
                SizedBox(height: 14),
                _FaqItem(
                  question: "Why are reminders not arriving instantly?",
                  answer:
                      "Check internet connectivity on both devices and ensure the child app has notification permission and background activity enabled.",
                ),
                SizedBox(height: 14),
                _FaqItem(
                  question: "Does Kidora monitor Chrome incognito or private browsing?",
                  answer:
                      "Yes. With Accessibility enabled on the child device, Kidora reads search text in Chrome incognito, Edge InPrivate, Brave, Firefox private tabs, and similar browsers. Flagged searches trigger an urgent email and a push notification on the parent's phone—even when Kidora is closed. The bell icon shows how many unread alerts you have.",
                ),
                SizedBox(height: 14),
                _FaqItem(
                  question: "How does uninstall protection work?",
                  answer:
                      "If uninstall is attempted, Kidora requests the parent PIN. A short uninstall window is granted only after successful PIN verification.",
                ),
                SizedBox(height: 14),
                _FaqItem(
                  question: "What if I forget my parent PIN?",
                  answer:
                      "Use your parent account to reset security settings. If needed, contact support for account recovery assistance.",
                ),
                SizedBox(height: 14),
                _FaqItem(
                  question: "How do I improve child device syncing?",
                  answer:
                      "Keep Accessibility and Usage Access enabled, allow notifications, and disable battery restrictions for Kidora.",
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FaqItem extends StatelessWidget {
  final String question;
  final String answer;

  const _FaqItem({required this.question, required this.answer});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GlassCard(
      borderRadius: 20,
      padding: const EdgeInsets.all(18),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 6),
        iconColor: isDark ? Colors.white70 : AppTheme.lightTextSecondary,
        collapsedIconColor: isDark ? Colors.white70 : AppTheme.lightTextSecondary,
        title: Text(
          question,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : AppTheme.lightTextPrimary,
            fontSize: 15,
          ),
        ),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              answer,
              style: TextStyle(
                color: isDark ? Colors.white70 : AppTheme.lightTextSecondary,
                height: 1.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}