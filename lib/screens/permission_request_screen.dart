import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/usage_service.dart';
import '../widgets/modern_background.dart';
import '../widgets/glass_card.dart';
import '../theme/app_theme.dart';

class PermissionRequestScreen extends StatefulWidget {
  final VoidCallback onPermissionGranted;

  const PermissionRequestScreen({
    super.key,
    required this.onPermissionGranted,
  });

  @override
  State<PermissionRequestScreen> createState() => _PermissionRequestScreenState();
}

class _PermissionRequestScreenState extends State<PermissionRequestScreen> with WidgetsBindingObserver {
  bool _isChecking = false;
  static const platform = MethodChannel('app.channel');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _verifyPermission();
    }
  }

  Future<void> _verifyPermission() async {
    if (!Platform.isAndroid) return;
    
    setState(() => _isChecking = true);
    
    try {
      final bool granted = await platform.invokeMethod('checkUsagePermission') ?? false;
      if (granted) {
        widget.onPermissionGranted();
      }
    } catch (e) {
      debugPrint("PermissionRequestScreen: Error checking permission: $e");
    } finally {
      if (mounted) setState(() => _isChecking = false);
    }
  }

  Future<void> _handleGrantPermission() async {
    await UsageService.requestUsagePermission();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final theme = Theme.of(context);

    return Scaffold(
      extendBodyBehindAppBar: true,
      body: ModernBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 40),
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppTheme.primaryColor.withValues(alpha: 0.2),
                        width: 2,
                      ),
                    ),
                    child: Icon(
                      Icons.security_update_good_rounded,
                      size: 80,
                      color: isDark ? AppTheme.darkPrimaryColor : AppTheme.lightPrimaryColor,
                    ),
                  ),
                ),
                const SizedBox(height: 48),
                Text(
                  "Almost Ready!",
                  textAlign: TextAlign.center,
                  style: theme.textTheme.displayMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  "Kidora needs 'Usage Access' permission to monitor screen time and keep your device safe.",
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: Colors.white,
                    height: 1.5,
                  ),
                ),
                const Spacer(),
                GlassCard(
                  padding: const EdgeInsets.all(24),
                  borderRadius: 24,
                  child: Column(
                    children: [
                      _buildStepItem(
                        icon: Icons.settings_applications_rounded,
                        text: "Tap 'Grant Permission' below",
                      ),
                      const SizedBox(height: 16),
                      _buildStepItem(
                        icon: Icons.toggle_on_rounded,
                        text: "Find 'Kidora' and enable Usage Access",
                      ),
                      const SizedBox(height: 16),
                      _buildStepItem(
                        icon: Icons.check_circle_rounded,
                        text: "Return here to finish setup",
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 40),
                ElevatedButton(
                  onPressed: _isChecking ? null : _handleGrantPermission,
                  child: _isChecking
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text("Grant Permission"),
                ),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: _isChecking ? null : _verifyPermission,
                  child: const Text("I've Already Granted It"),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStepItem({required IconData icon, required String text}) {
    return Row(
      children: [
        Icon(icon, color: AppTheme.accentColor, size: 24),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
