import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'login_screen.dart';
import 'help_faq_page.dart';
import 'privacy_policy_page.dart';
import '../widgets/modern_background.dart';
import '../widgets/glass_card.dart';
import '../theme/app_theme.dart';
import '../services/auth_service.dart';
import '../services/api.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  Future<void> _confirmLogout() async {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final titleColor = isDark ? Colors.white : AppTheme.lightTextPrimary;
    final bodyColor = isDark ? Colors.white70 : AppTheme.lightTextSecondary;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            'Log out?',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: titleColor,
            ),
          ),
          content: Text(
            'Do you want to log out? You will need to sign in again to use the parent app.',
            style: TextStyle(
              color: bodyColor,
              height: 1.4,
              fontWeight: FontWeight.w500,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(
                'Cancel',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white70 : AppTheme.lightTextSecondary,
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
              child: const Text(
                'Log out',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    await AuthService().logout();
    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
      (Route<dynamic> route) => false,
    );
  }

  Future<void> _showUpdateParentPinSheet() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isDark ? Colors.white : AppTheme.lightTextPrimary;
    final bodyColor = isDark ? Colors.white70 : AppTheme.lightTextSecondary;
    final pin = TextEditingController();
    final confirm = TextEditingController();
    try {
      final saved = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text(
              'Parent security PIN',
              style: TextStyle(fontWeight: FontWeight.w800, color: titleColor),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Set a 4-digit PIN. The child app asks for this PIN before disconnecting or uninstalling Kidora.',
                    style: TextStyle(color: bodyColor, height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: pin,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    maxLength: 4,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'New PIN',
                      counterText: '',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: confirm,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    maxLength: 4,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Confirm PIN',
                      counterText: '',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(
                  'Cancel',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white70 : AppTheme.lightTextSecondary,
                  ),
                ),
              ),
              FilledButton(
                onPressed: () {
                  final a = pin.text.trim();
                  final b = confirm.text.trim();
                  if (!RegExp(r'^\d{4}$').hasMatch(a)) return;
                  if (a != b) return;
                  Navigator.pop(dialogContext, true);
                },
                child: const Text('Save', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ],
          );
        },
      );
      if (saved != true || !mounted) return;
      final p = pin.text.trim();
      if (!RegExp(r'^\d{4}$').hasMatch(p) || p != confirm.text.trim()) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PIN must be 4 digits and match confirmation.')),
        );
        return;
      }
      await ApiService.setParentUninstallPin(p);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Parent PIN updated.')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      pin.dispose();
      confirm.dispose();
    }
  }

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
          'Settings',
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                Text(
                  "Customize your experience and manage account preferences.",
                  style: TextStyle(
                    color: isDark ? Colors.white70 : AppTheme.lightTextSecondary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 24),

                Text(
                  "Support",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white70 : AppTheme.lightTextSecondary,
                    fontSize: 14,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 14),

                GlassCard(
                  padding: EdgeInsets.zero,
                  borderRadius: 22,
                  child: Column(
                    children: [
                      _buildSettingsOption(
                        context,
                        "Help & FAQ",
                        Icons.help_outline_rounded,
                        subtitle: "Find quick answers and guidance",
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const HelpFaqPage(),
                            ),
                          );
                        },
                      ),
                      const Divider(height: 1, indent: 64, endIndent: 24, color: Colors.white12),
                      _buildSettingsOption(
                        context,
                        "Privacy Policy",
                        Icons.privacy_tip_outlined,
                        subtitle: "Read how Kidora handles your data",
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const PrivacyPolicyPage(),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 36),
                Text(
                  "Account",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white70 : AppTheme.lightTextSecondary,
                    fontSize: 14,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 16),

                GlassCard(
                  padding: EdgeInsets.zero,
                  borderRadius: 22,
                  child: _buildSettingsOption(
                    context,
                    "Parent security PIN",
                    Icons.pin_outlined,
                    subtitle:
                        "Change the 4-digit PIN the child must enter to disconnect or uninstall",
                    onTap: _showUpdateParentPinSheet,
                  ),
                ),
                const SizedBox(height: 16),

                GlassCard(
                  padding: EdgeInsets.zero,
                  borderRadius: 22,
                  color: Colors.redAccent.withValues(alpha: 0.1),
                  child: _buildSettingsOption(
                    context,
                    "Logout",
                    Icons.logout_rounded,
                    subtitle: "Sign out of your account",
                    isDangerous: true,
                    onTap: _confirmLogout,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsOption(
    BuildContext context,
    String title,
    IconData icon, {
    String? subtitle,
    VoidCallback? onTap,
    bool isDangerous = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: (isDangerous ? Colors.redAccent : Colors.white).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  icon,
                  size: 22,
                  color: isDangerous ? Colors.redAccent : Colors.white,
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: isDangerous
                            ? Colors.redAccent
                            : (isDark
                                  ? Colors.white
                                  : AppTheme.lightTextPrimary),
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: isDark
                              ? Colors.white60
                              : AppTheme.lightTextSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: isDark ? Colors.white38 : AppTheme.lightTextSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }

}