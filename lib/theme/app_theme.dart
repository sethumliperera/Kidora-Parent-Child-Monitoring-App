import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Light Theme Colors (Pearl Amethyst)
  static const Color lightPrimaryColor = Color(0xFF9C27B0); // Amethyst Purple
  static const Color lightAccentColor = Color(0xFF00E5FF); // Cyan
  static const Color lightBackground = Color(0xFFF5F0FF); // Pearl Lavender-White
  static const Color lightSurface = Colors.white;
  static const Color lightTextPrimary = Color(0xFF1A0824);
  static const Color lightTextSecondary =
      Color(0xFF5E456E); // readable purple-grey on pastel bg
  static const Color lightBorder = Color(0xFFE1BEE7);

  // Unified full-screen gradients (used by ModernBackground)
  static const Color backdropGradientLightTop = Color(0xFFF5F0FF);
  static const Color backdropGradientLightBottom = Color(0xFFDECCEB);
  static const Color backdropGradientDarkTop = Color(0xFF4A148C);
  static const Color backdropGradientDarkBottom = Color(0xFF283593);

  // Dark Theme Colors (Deep Blue/Mint Glass)
  static const Color darkPrimaryColor = Color(0xFF69F0AE); // Vibrant Mint Green
  static const Color darkAccentColor = Color(0xFF00E5FF);
  static const Color darkBackground = Color(0xFF4A148C); // Base Purple
  static const Color darkSurface =
      Color(0xFF3D206B); // solid surface for dialogs / overlays
  static const Color darkTextPrimary = Colors.white;
  static const Color darkTextSecondary =
      Color(0xFFEAD6FB); // high contrast lavender on purple
  static const Color darkBorder = Color(0x40FFFFFF); // visible but soft

  /// Headlines placed directly on the gradient (outside glass cards).
  static Color textOnBackdropPrimary(Brightness brightness) =>
      brightness == Brightness.dark ? Colors.white : const Color(0xFF2D084A);

  /// Subtitles on the gradient.
  static Color textOnBackdropSecondary(Brightness brightness) =>
      brightness == Brightness.dark ? darkTextSecondary : lightTextSecondary;

  /// Hints inside text fields over glass/light fills.
  static Color fieldHint(Brightness brightness) =>
      brightness == Brightness.dark
          ? const Color(0xFFC9BADD)
          : const Color(0xFF7D6B8A);

  // Legacy Aliases used by internal screens
  static const Color primaryColor = Color(0xFF9C27B0);
  static const Color primaryColorLight = Color(0xFFBA68C8);
  static const Color primaryColorDark = Color(0xFF4A148C);
  static const Color snackBarBackground = primaryColorDark;
  static const Color accentColor = Color(0xFF00E5FF);
  static const Color errorColor = Color(0xFFFF5252);

  static TextTheme _buildTextTheme(Color primaryText, Color secondaryText) {
    return GoogleFonts.outfitTextTheme().copyWith(
      displayLarge: GoogleFonts.outfit(
        fontSize: 32,
        fontWeight: FontWeight.bold,
        color: primaryText,
      ),
      displayMedium: GoogleFonts.outfit(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: primaryText,
      ),
      titleLarge: GoogleFonts.outfit(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        color: primaryText,
      ),
      headlineMedium: GoogleFonts.outfit(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: primaryText,
      ),
      titleMedium: GoogleFonts.outfit(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: primaryText,
      ),
      bodyLarge: GoogleFonts.outfit(
        fontSize: 16,
        fontWeight: FontWeight.normal,
        color: primaryText,
      ),
      bodyMedium: GoogleFonts.outfit(
        fontSize: 14,
        fontWeight: FontWeight.normal,
        color: secondaryText,
      ),
      bodySmall: GoogleFonts.outfit(
        fontSize: 12,
        fontWeight: FontWeight.normal,
        color: secondaryText,
      ),
    );
  }

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      primaryColor: lightPrimaryColor,
      scaffoldBackgroundColor: lightBackground,
      colorScheme: ColorScheme.fromSeed(
        brightness: Brightness.light,
        seedColor: lightPrimaryColor,
        primary: lightPrimaryColor,
        secondary: lightAccentColor,
        surface: lightBackground,
        error: errorColor,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: lightTextPrimary,
      ),
      textTheme: _buildTextTheme(lightTextPrimary, lightTextSecondary),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent, 
        elevation: 0,
        centerTitle: true,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: GoogleFonts.outfit(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: lightTextPrimary,
        ),
        iconTheme: const IconThemeData(color: AppTheme.lightTextPrimary), 
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: lightPrimaryColor,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 60),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          elevation: 4,
          shadowColor: lightPrimaryColor.withValues(alpha: 0.4),
          textStyle: GoogleFonts.outfit(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: lightPrimaryColor,
          side: const BorderSide(color: lightPrimaryColor, width: 2.0),
          minimumSize: const Size(double.infinity, 60),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: GoogleFonts.outfit(
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: lightPrimaryColor,
          textStyle: GoogleFonts.outfit(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: lightSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: lightPrimaryColor, width: 2.0),
        ),
        hintStyle: GoogleFonts.outfit(
          color: lightTextSecondary,
          fontSize: 14,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      ),
      cardTheme: CardThemeData(
        color: lightSurface,
        elevation: 2,
        shadowColor: Colors.black12,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      iconTheme: const IconThemeData(color: lightPrimaryColor),
      dialogTheme: DialogThemeData(
        backgroundColor: lightSurface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      primaryColor: darkPrimaryColor,
      scaffoldBackgroundColor: darkBackground,
      colorScheme: ColorScheme.fromSeed(
        brightness: Brightness.dark,
        seedColor: darkPrimaryColor,
        primary: darkPrimaryColor,
        secondary: darkAccentColor,
        surface: darkSurface,
        error: errorColor,
        onPrimary: Colors.black,
        onSecondary: Colors.black,
        onSurface: darkTextPrimary,
      ).copyWith(surfaceContainerHighest: const Color(0xFF4A3570)),
      textTheme: _buildTextTheme(darkTextPrimary, darkTextSecondary),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent, 
        elevation: 0,
        centerTitle: true,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: GoogleFonts.outfit(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: darkTextPrimary,
        ),
        iconTheme: const IconThemeData(color: Colors.white), 
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: darkPrimaryColor,
          foregroundColor: Colors.black87,
          minimumSize: const Size(double.infinity, 60),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          elevation: 8,
          shadowColor: darkPrimaryColor.withValues(alpha: 0.4),
          textStyle: GoogleFonts.outfit(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: darkPrimaryColor,
          side: const BorderSide(color: darkPrimaryColor, width: 2.5),
          minimumSize: const Size(double.infinity, 60),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: GoogleFonts.outfit(
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: darkPrimaryColor,
          textStyle: GoogleFonts.outfit(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: darkPrimaryColor, width: 2.0),
        ),
        hintStyle: GoogleFonts.outfit(
          color: darkTextSecondary,
          fontSize: 14,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      ),
      cardTheme: CardThemeData(
        color: Colors.white.withValues(alpha: 0.16),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      iconTheme: const IconThemeData(color: Colors.white),
      dialogTheme: DialogThemeData(
        backgroundColor: darkSurface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
    );
  }
}
