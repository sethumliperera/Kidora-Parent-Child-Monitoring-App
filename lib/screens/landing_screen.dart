import 'package:flutter/material.dart';
import 'login_screen.dart';
import 'signup_screen.dart';
import 'link_device_screen.dart';
import '../widgets/modern_background.dart';
import '../theme/app_theme.dart';

class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final primaryOnBackdrop = AppTheme.textOnBackdropPrimary(brightness);
    final secondaryOnBackdrop = AppTheme.textOnBackdropSecondary(brightness);

    return Scaffold(
      body: ModernBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              children: [
                const Spacer(flex: 3),
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.9),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: theme.primaryColor.withValues(alpha: 0.15),
                        blurRadius: 50,
                        spreadRadius: 10,
                      ),
                    ],
                  ),
                  child: Hero(
                    tag: 'logo',
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(60),
                      child: Image.asset(
                        'assets/kidora_logo.jpeg',
                        width: 130,
                        height: 130,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 36),
                Text(
                  'KIDORA',
                  style: theme.textTheme.displayMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: primaryOnBackdrop,
                    letterSpacing: 8,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Smart Parenting Starts Here',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: secondaryOnBackdrop,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(flex: 5),
                Column(
                  children: [
                    ElevatedButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const LoginScreen(),
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: brightness == Brightness.dark
                            ? Colors.white
                            : AppTheme.lightPrimaryColor,
                        foregroundColor: brightness == Brightness.dark
                            ? AppTheme.primaryColorDark
                            : Colors.white,
                        minimumSize: const Size(double.infinity, 60),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      child: const Text(
                        'Log in',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const SignUpScreen(),
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        foregroundColor: primaryOnBackdrop,
                        side: BorderSide(
                          color: primaryOnBackdrop.withValues(alpha: 0.85),
                          width: 2.5,
                        ),
                        minimumSize: const Size(double.infinity, 60),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      child: Text(
                        "Sign up",
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: primaryOnBackdrop,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const LinkDeviceScreen(),
                        ),
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                      ),
                      child: Text(
                        "Link your child's device",
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: secondaryOnBackdrop,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                          decoration: TextDecoration.underline,
                          decorationColor:
                              secondaryOnBackdrop.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
