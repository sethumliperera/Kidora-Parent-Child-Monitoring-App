import 'package:flutter/material.dart';
import '../widgets/modern_background.dart';
import '../widgets/glass_card.dart';
import '../theme/app_theme.dart';

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

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
          "Privacy Policy",
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
            child: GlassCard(
              borderRadius: 24,
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _heading(context, "Kidora Privacy Policy"),
                  const SizedBox(height: 10),
                  _body(
                    context,
                    "We value your privacy and are committed to protecting parent and child data used by Kidora.",
                  ),
                  const SizedBox(height: 18),
                  _subheading(context, "1. Information We Collect"),
                  _body(
                    context,
                    "- Account information such as email and user role\n"
                    "- Child profile details (name, age, optional interests/photo)\n"
                    "- App usage and parental control metadata required for core features",
                  ),
                  const SizedBox(height: 14),
                  _subheading(context, "2. How We Use Data"),
                  _body(
                    context,
                    "Data is used only to provide parental controls, reminder delivery, activity insights, and account security functionality.",
                  ),
                  const SizedBox(height: 14),
                  _subheading(context, "3. Notification Data"),
                  _body(
                    context,
                    "Kidora may store device messaging tokens to deliver reminders and alerts, including when the child app is in the background.",
                  ),
                  const SizedBox(height: 14),
                  _subheading(context, "4. Security"),
                  _body(
                    context,
                    "We use authenticated access controls and secure backend communication to help protect account and device data.",
                  ),
                  const SizedBox(height: 14),
                  _subheading(context, "5. Parental Responsibility"),
                  _body(
                    context,
                    "Parents are responsible for managing child consent requirements and ensuring legal compliance in their region.",
                  ),
                  const SizedBox(height: 14),
                  _subheading(context, "6. Updates"),
                  _body(
                    context,
                    "This policy may be updated over time. Continued use of Kidora indicates acceptance of the updated policy.",
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _heading(BuildContext context, String text) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Text(
      text,
      style: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w900,
        color: isDark ? Colors.white : AppTheme.lightTextPrimary,
      ),
    );
  }

  Widget _subheading(BuildContext context, String text) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w800,
          color: isDark ? Colors.white : AppTheme.lightTextPrimary,
        ),
      ),
    );
  }

  Widget _body(BuildContext context, String text) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Text(
      text,
      style: TextStyle(
        fontSize: 14,
        height: 1.55,
        fontWeight: FontWeight.w500,
        color: isDark ? Colors.white70 : AppTheme.lightTextSecondary,
      ),
    );
  }
}