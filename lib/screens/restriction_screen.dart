import 'package:flutter/material.dart';
import '../widgets/modern_background.dart';
import '../widgets/glass_card.dart';

class RestrictionScreen extends StatelessWidget {
  final String appName;
  final String reason; // "Limit Reached" or "Blocked"

  const RestrictionScreen({
    super.key,
    required this.appName,
    required this.reason,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      body: ModernBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Friendly Icon (Glassy)
                GlassCard(
                  padding: const EdgeInsets.all(40),
                  borderRadius: 100,
                  child: const Icon(
                    Icons.timer_off_rounded,
                    size: 80,
                    color: Colors.orangeAccent,
                  ),
                ),
                const SizedBox(height: 48),

                // Title
                const Text(
                  "Time for a break!",
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),

                // Description
                Text(
                  reason == "Blocked"
                      ? "$appName is currently blocked by your parent."
                      : "You've reached your daily limit for $appName.",
                  style: const TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 64),

                // Back to Dashboard Button
                SizedBox(
                  width: double.infinity,
                  height: 64,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.1),
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white24),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      "Back to Dashboard",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
