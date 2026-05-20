import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'login_screen.dart';
import '../widgets/modern_background.dart';
import '../widgets/glass_card.dart';
import '../services/auth_service.dart';
import '../utils/config.dart';
import '../theme/app_theme.dart';
class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmPasswordController = TextEditingController();
  final TextEditingController uninstallPinController = TextEditingController();
  final TextEditingController confirmUninstallPinController =
      TextEditingController();
  bool isLoading = false;

  bool get _hasMinLength => passwordController.text.length >= 8;
  bool get _hasUppercase => passwordController.text.contains(RegExp(r'[A-Z]'));
  bool get _hasLowercase => passwordController.text.contains(RegExp(r'[a-z]'));
  bool get _hasNumber => passwordController.text.contains(RegExp(r'[0-9]'));
  bool get _hasSpecialChar => passwordController.text.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'));
  bool get _isPasswordStrong => _hasMinLength && _hasUppercase && _hasLowercase && _hasNumber && _hasSpecialChar;

  @override
  void initState() {
    super.initState();
    passwordController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    uninstallPinController.dispose();
    confirmUninstallPinController.dispose();
    super.dispose();
  }

  Future<void> _syncUserToBackend(
    String uid,
    String email,
    String uninstallPin,
  ) async {
    try {
      await http.post(
        Uri.parse("${Config.baseUrl}/users"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "uid": uid,
          "email": email,
          "uninstall_pin": uninstallPin,
        }),
      );
    } catch (e) {
      debugPrint("Backend sync failed: $e");
    }
  }

  Future<void> handleSignup() async {
    final email = emailController.text.trim();
    final password = passwordController.text.trim();
    final confirmPassword = confirmPasswordController.text.trim();
    final uninstallPin = uninstallPinController.text.trim();
    final confirmUninstallPin = confirmUninstallPinController.text.trim();

    if (email.isEmpty || password.isEmpty || confirmPassword.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please fill all fields")));
      return;
    }

    if (!RegExp(r'^\d{4}$').hasMatch(uninstallPin)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Parent PIN must be exactly 4 digits")),
      );
      return;
    }

    if (uninstallPin != confirmUninstallPin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("PINs do not match")),
      );
      return;
    }

    if (!_isPasswordStrong) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Password is too weak.")));
      return;
    }

    if (password != confirmPassword) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Passwords do not match")));
      return;
    }

    setState(() => isLoading = true);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final result = await AuthService().signUp(email, password);
      final user = result['user'];
      final error = result['error'];

      if (!mounted) return;

      if (user != null) {
        await _syncUserToBackend(user.uid, user.email!, uninstallPin);
        messenger.showSnackBar(const SnackBar(content: Text("Account created! Please verify your email before logging in.")));
        navigator.pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
      } else {
        messenger.showSnackBar(SnackBar(content: Text(error ?? "Signup failed")));
      }
    } catch (e) {
      if (mounted) messenger.showSnackBar(SnackBar(content: Text("Error: ${e.toString()}")));
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> handleGoogleSignup() async {
    final uninstallPin = uninstallPinController.text.trim();
    final confirmUninstallPin = confirmUninstallPinController.text.trim();
    if (!RegExp(r'^\d{4}$').hasMatch(uninstallPin)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Set a 4-digit parent PIN first")),
      );
      return;
    }
    if (uninstallPin != confirmUninstallPin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("PINs do not match")),
      );
      return;
    }

    setState(() => isLoading = true);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final result = await AuthService().signInWithGoogle();
      final user = result['user'];
      final error = result['error'];

      if (!mounted) return;

      if (user != null) {
        await _syncUserToBackend(user.uid, user.email!, uninstallPin);
        messenger.showSnackBar(const SnackBar(content: Text("Successfully signed up with Google!")));
        navigator.pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
      } else {
        messenger.showSnackBar(SnackBar(content: Text(error ?? "Google sign-up failed")));
      }
    } catch (e) {
      if (mounted) messenger.showSnackBar(SnackBar(content: Text("Error: ${e.toString()}")));
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Widget _buildCriteriaRow(String text, bool met, bool isDark) => Row(
    children: [
      Icon(met ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, color: met ? Colors.greenAccent : (isDark ? Colors.white24 : AppTheme.lightTextSecondary.withValues(alpha: 0.3)), size: 16),
      const SizedBox(width: 8),
      Text(text, style: TextStyle(color: met ? (isDark ? Colors.white : AppTheme.lightTextPrimary) : (isDark ? Colors.white70 : AppTheme.lightTextSecondary), fontSize: 13, fontWeight: FontWeight.bold)),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, size: 22, color: isDark ? Colors.white : AppTheme.lightTextPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ModernBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 10),
                Center(
                  child: Hero(
                    tag: 'logo',
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.9), shape: BoxShape.circle),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(30),
                        child: Image.asset('assets/kidora_logo.jpeg', width: 50, height: 50),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 30),
                Text(
                  'Create Account',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 32, color: isDark ? Colors.white : AppTheme.lightTextPrimary),
                ),
                const SizedBox(height: 12),
                Text(
                  'Create your account and start protecting your family.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: isDark ? Colors.white70 : AppTheme.lightTextSecondary, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 40),
                GlassCard(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    children: [
                      _buildTextField(emailController, "Email", Icons.email_rounded, isDark),
                      const SizedBox(height: 20),
                      _buildTextField(passwordController, "Password", Icons.lock_rounded, isDark, obscureText: true),
                      const SizedBox(height: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildCriteriaRow("At least 8 characters", _hasMinLength, isDark),
                          const SizedBox(height: 4),
                          _buildCriteriaRow("Contains uppercase letter", _hasUppercase, isDark),
                          const SizedBox(height: 4),
                          _buildCriteriaRow("Contains lowercase letter", _hasLowercase, isDark),
                          const SizedBox(height: 4),
                          _buildCriteriaRow("Contains number", _hasNumber, isDark),
                          const SizedBox(height: 4),
                          _buildCriteriaRow("Contains special character (!@#\$%^&*)", _hasSpecialChar, isDark),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _buildTextField(confirmPasswordController, "Confirm Password", Icons.lock_rounded, isDark, obscureText: true),
                      const SizedBox(height: 20),
                      _buildTextField(
                        uninstallPinController,
                        "Set 4-digit Parent PIN",
                        Icons.pin_rounded,
                        isDark,
                        obscureText: true,
                        keyboardType: TextInputType.number,
                        maxLength: 4,
                      ),
                      const SizedBox(height: 12),
                      _buildTextField(
                        confirmUninstallPinController,
                        "Confirm Parent PIN",
                        Icons.pin_outlined,
                        isDark,
                        obscureText: true,
                        keyboardType: TextInputType.number,
                        maxLength: 4,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'On the child device, this PIN is required to disconnect from the parent or to remove the app (after a successful check).',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white60 : AppTheme.lightTextSecondary,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 32),
                      ElevatedButton(
                        onPressed: isLoading ? null : handleSignup,
                        child: isLoading
                            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Text("Sign Up"),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(child: Divider(color: isDark ? Colors.white24 : AppTheme.lightTextSecondary.withValues(alpha: 0.2))),
                          Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text("OR", style: TextStyle(color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary, fontWeight: FontWeight.bold))),
                          Expanded(child: Divider(color: isDark ? Colors.white24 : AppTheme.lightTextSecondary.withValues(alpha: 0.2))),
                        ],
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        onPressed: isLoading ? null : handleGoogleSignup,
                        icon: Image.asset('assets/icons/google.png', height: 20, width: 20),
                        label: Text("Continue with Google", style: TextStyle(color: isDark ? Colors.black : Colors.white)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isDark ? Colors.white : AppTheme.primaryColorDark,
                          foregroundColor: isDark ? Colors.black : Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String hint,
    IconData icon,
    bool isDark, {
    bool obscureText = false,
    TextInputType? keyboardType,
    int? maxLength,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      maxLength: maxLength,
      style: TextStyle(color: isDark ? Colors.white : AppTheme.lightTextPrimary, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        counterText: '',
        hintText: hint,
        hintStyle: TextStyle(color: AppTheme.fieldHint(isDark ? Brightness.dark : Brightness.light)),
        prefixIcon: Icon(icon, color: isDark ? Colors.white : AppTheme.lightTextPrimary, size: 22),
        filled: true,
        fillColor: isDark ? Colors.white.withValues(alpha: 0.14) : AppTheme.primaryColor.withValues(alpha: 0.06),
        contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: isDark ? Colors.white.withValues(alpha: 0.2) : AppTheme.primaryColor.withValues(alpha: 0.2)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.transparent),
        ),
      ),
    );
  }
}