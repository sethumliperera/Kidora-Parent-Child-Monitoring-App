import 'package:flutter/material.dart';
import 'signup_screen.dart';
import 'forgot_password.dart';
import 'parent_dashboard.dart';
import '../widgets/modern_background.dart';
import '../widgets/glass_card.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  bool isLoading = false;
  bool _isPasswordVisible = false;

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
                const SizedBox(height: 20),
                Center(
                  child: Hero(
                    tag: 'logo',
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.9),
                        shape: BoxShape.circle,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(30),
                        child: Image.asset(
                          'assets/kidora_logo.jpeg',
                          width: 60,
                          height: 60,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 40),
                Text(
                  'Welcome Back',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 32,
                    color: isDark ? Colors.white : AppTheme.lightTextPrimary,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Sign in to continue managing your child\'s safety.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    color: isDark ? Colors.white70 : AppTheme.lightTextSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 48),

                GlassCard(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildFieldLabel("Email Address", isDark),
                      TextField(
                        controller: emailController,
                        style: TextStyle(color: isDark ? Colors.white : AppTheme.lightTextPrimary, fontWeight: FontWeight.w600),
                        decoration: InputDecoration(
                          hintText: "hello@example.com",
                          hintStyle: TextStyle(color: AppTheme.fieldHint(isDark ? Brightness.dark : Brightness.light)),
                          prefixIcon: Icon(Icons.email_rounded, size: 22, color: isDark ? Colors.white : AppTheme.lightTextPrimary),
                          filled: true,
                          fillColor: isDark ? Colors.white.withValues(alpha: 0.14) : AppTheme.primaryColor.withValues(alpha: 0.06),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: BorderSide(color: isDark ? Colors.white.withValues(alpha: 0.2) : AppTheme.primaryColor.withValues(alpha: 0.2)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: BorderSide(color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.transparent),
                          ),
                        ),
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 24),
                      _buildFieldLabel("Password", isDark),
                      TextField(
                        controller: passwordController,
                        style: TextStyle(color: isDark ? Colors.white : AppTheme.lightTextPrimary, fontWeight: FontWeight.w600),
                        obscureText: !_isPasswordVisible,
                        decoration: InputDecoration(
                          hintText: "••••••••",
                          hintStyle: TextStyle(color: AppTheme.fieldHint(isDark ? Brightness.dark : Brightness.light)),
                          prefixIcon: Icon(Icons.lock_rounded, size: 22, color: isDark ? Colors.white : AppTheme.lightTextPrimary),
                          suffixIcon: IconButton(
                            onPressed: () {
                              setState(() {
                                _isPasswordVisible = !_isPasswordVisible;
                              });
                            },
                            icon: Icon(
                              _isPasswordVisible
                                  ? Icons.visibility_off_rounded
                                  : Icons.visibility_rounded,
                              color: isDark
                                  ? Colors.white70
                                  : AppTheme.lightTextSecondary,
                            ),
                          ),
                          filled: true,
                          fillColor: isDark ? Colors.white.withValues(alpha: 0.14) : AppTheme.primaryColor.withValues(alpha: 0.06),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: BorderSide(color: isDark ? Colors.white.withValues(alpha: 0.2) : AppTheme.primaryColor.withValues(alpha: 0.2)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: BorderSide(color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.transparent),
                          ),
                        ),
                      ),

                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const ForgotPasswordScreen(),
                            ),
                          ),
                          child: Text(
                            "Forgot Password?",
                            style: TextStyle(
                              color: isDark ? Colors.white : AppTheme.primaryColorDark,
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                              decoration: TextDecoration.underline,
                              decorationColor: isDark ? Colors.white30 : AppTheme.primaryColorDark.withValues(alpha: 0.5),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      ElevatedButton(
                        onPressed: isLoading ? null : _handleLogin,
                        child: isLoading
                            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Text("Log in"),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 48),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "Don't have an account? ",
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white70 : AppTheme.lightTextSecondary,
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const SignUpScreen(),
                        ),
                      ),
                      child: Text(
                        "Sign Up",
                        style: TextStyle(
                          color: isDark ? Colors.white : AppTheme.primaryColorDark,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleLogin() async {
    setState(() => isLoading = true);

    final email = emailController.text.trim();
    final password = passwordController.text.trim();

    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final user = await AuthService().login(email, password);

      if (!mounted) return;

      if (user != null) {
        if (user.emailVerified) {
          navigator.pushReplacement(
            MaterialPageRoute(
              builder: (context) => ParentDashboard(token: user.uid),
            ),
          );
        } else {
          messenger.showSnackBar(const SnackBar(content: Text("Please verify your email before logging in.")));
        }
      } else {
        messenger.showSnackBar(const SnackBar(content: Text("Login failed. Please check your credentials.")));
      }
    } catch (e) {
      if (mounted) messenger.showSnackBar(SnackBar(content: Text("Error: ${e.toString()}")));
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Widget _buildFieldLabel(String label, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 4),
      child: Text(
        label,
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: isDark ? Colors.white : AppTheme.lightTextPrimary, letterSpacing: 0.5),
      ),
    );
  }
}
