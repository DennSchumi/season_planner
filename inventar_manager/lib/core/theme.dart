import 'package:flutter/material.dart';

class AppTheme {
  static const String fontFamily = 'Inter';

  static TextStyle _inter({
    double? fontSize,
    FontWeight? fontWeight,
    double? letterSpacing,
    Color? color,
  }) {
    return TextStyle(
      fontFamily: fontFamily,
      fontSize: fontSize,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
      color: color,
    );
  }

  // === Primär- & Marken-Tokens (Tragegurt / Revolut-inspirierter Light/Dark Mode) ===
  static const Color primaryColor = Color(0xFF5B3DF5);
  static const Color primaryTint = Color(0xFFEEEAFE);
  static const Color primaryDark = Color(0xFF4428D0);
  static const Color accentColor = Color(0xFF8B74FA);

  // === Flächen & Text (Light – warmer, weicher Canvas-Ton) ===
  static const Color backgroundColor = Color(0xFFEEEEEC);
  static const Color cardColor = Color(0xFFFFFFFF);
  static const Color textColor = Color(0xFF11131A);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color textTertiary = Color(0xFF9AA3B2);
  static const Color borderSubtle = Color(0xFFE4E4E0);

  // === Flächen & Text (Dark) ===
  static const Color darkBackground = Color(0xFF0E0F14);
  static const Color darkCard = Color(0xFF171821);
  static const Color darkCardElevated = Color(0xFF1F212D);
  static const Color darkBorder = Color(0xFF282B3A);
  static const Color darkPrimary = Color(0xFF8C78FF);

  // === Semantische Status- & Warnfarben (Text + Pastell-BG) ===
  static const Color successColor = Color(0xFF12805C);
  static const Color successBg = Color(0xFFE3F6ED);

  static const Color warningColor = Color(0xFFB45309);
  static const Color warningBg = Color(0xFFFEF3C7);

  static const Color dangerColor = Color(0xFFD92D20);
  static const Color dangerBg = Color(0xFFFEE4E2);

  static const Color infoColor = Color(0xFF1570EF);
  static const Color infoBg = Color(0xFFEFF6FF);

  static const Color swapColor = Color(0xFF0F766E);
  static const Color swapBg = Color(0xFFE4FBF7);

  static const Color stage1Color = Color(0xFF7C3AED);
  static const Color stage1Bg = Color(0xFFF3EAFE);

  /// Weicher Karten-Schatten für Light Mode (im Dark Mode dezent gehalten).
  static List<BoxShadow> cardShadow(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (isDark) {
      return const [
        BoxShadow(
          color: Color(0x33000000),
          blurRadius: 16,
          offset: Offset(0, 6),
        ),
      ];
    }
    return const [
      BoxShadow(
        color: Color(0x0A101828),
        blurRadius: 2,
        offset: Offset(0, 1),
      ),
      BoxShadow(
        color: Color(0x0F101828),
        blurRadius: 24,
        offset: Offset(0, 8),
      ),
    ];
  }

  /// Farbiger Glow für hervorgehobene Primär-CTAs / App-Badges.
  static const List<BoxShadow> primaryGlow = [
    BoxShadow(
      color: Color(0x405B3DF5),
      blurRadius: 20,
      offset: Offset(0, 8),
    ),
  ];

  static TextTheme _buildTextTheme(TextTheme base, Color ink, Color secondary) {
    final inter = base.apply(fontFamily: fontFamily);
    return inter.copyWith(
      displayLarge: inter.displayLarge?.copyWith(
        fontSize: 28,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
        color: ink,
      ),
      headlineSmall: inter.headlineSmall?.copyWith(
        fontSize: 22,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.4,
        color: ink,
      ),
      titleLarge: inter.titleLarge?.copyWith(
        fontSize: 19,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.25,
        color: ink,
      ),
      titleMedium: inter.titleMedium?.copyWith(
        fontSize: 15.5,
        fontWeight: FontWeight.w700,
        color: ink,
      ),
      bodyLarge: inter.bodyLarge?.copyWith(
        fontSize: 15,
        color: ink,
      ),
      bodyMedium: inter.bodyMedium?.copyWith(
        fontSize: 14,
        color: ink,
      ),
      bodySmall: inter.bodySmall?.copyWith(
        fontSize: 12.5,
        color: secondary,
      ),
      labelLarge: inter.labelLarge?.copyWith(
        fontWeight: FontWeight.w600,
      ),
    );
  }

  static ThemeData get lightTheme {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      fontFamily: fontFamily,
    );
    final cs = ColorScheme.fromSeed(
      seedColor: primaryColor,
      brightness: Brightness.light,
      primary: primaryColor,
      onPrimary: Colors.white,
      primaryContainer: primaryTint,
      onPrimaryContainer: primaryDark,
      secondary: accentColor,
      surface: cardColor,
      onSurface: textColor,
      onSurfaceVariant: textSecondary,
      outline: const Color(0xFFD6D6D1),
      outlineVariant: borderSubtle,
      error: dangerColor,
    );

    final textTheme = _buildTextTheme(base.textTheme, textColor, textSecondary);

    return base.copyWith(
      colorScheme: cs,
      scaffoldBackgroundColor: backgroundColor,
      canvasColor: backgroundColor,
      hoverColor: primaryColor.withValues(alpha: 0.05),
      splashColor: primaryColor.withValues(alpha: 0.08),
      highlightColor: primaryColor.withValues(alpha: 0.04),
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: backgroundColor,
        surfaceTintColor: Colors.transparent,
        foregroundColor: textColor,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        shadowColor: const Color(0x14101828),
        centerTitle: false,
        titleTextStyle: _inter(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.4,
          color: textColor,
        ),
        iconTheme: const IconThemeData(color: textColor, size: 22),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: cardColor,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shadowColor: const Color(0x1F101828),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: borderSubtle),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: cardColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 68,
        indicatorColor: primaryTint,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return _inter(
            fontSize: 11.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? primaryColor : textSecondary,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 22,
            color: selected ? primaryColor : textSecondary,
          );
        }),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: cardColor,
        selectedItemColor: primaryColor,
        unselectedItemColor: textSecondary,
        showUnselectedLabels: true,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: _inter(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelStyle: _inter(
          fontSize: 11.5,
          fontWeight: FontWeight.w500,
        ),
      ),
      cardTheme: CardThemeData(
        color: cardColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shadowColor: const Color(0x14101828),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: borderSubtle, width: 1),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: cardColor,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: backgroundColor,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: borderSubtle,
        thickness: 1,
        space: 1,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          textStyle: _inter(
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          textStyle: _inter(
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textColor,
          backgroundColor: cardColor,
          side: const BorderSide(color: Color(0xFFE2E6EF)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          textStyle: _inter(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primaryColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: _inter(
            fontWeight: FontWeight.w600,
            fontSize: 13.5,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: cardColor,
        selectedColor: primaryTint,
        side: const BorderSide(color: borderSubtle),
        shape: const StadiumBorder(),
        labelStyle: _inter(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cardColor,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        hintStyle: const TextStyle(color: textTertiary, fontSize: 14),
        labelStyle: const TextStyle(color: textSecondary, fontSize: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE5E8F0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE5E8F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: primaryColor, width: 1.8),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: textColor,
        contentTextStyle: _inter(color: Colors.white, fontSize: 13.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  static ThemeData get darkTheme {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: fontFamily,
    );
    const ink = Color(0xFFF3F4F6);
    const secondary = Color(0xFF9CA3AF);

    final cs = ColorScheme.fromSeed(
      seedColor: primaryColor,
      brightness: Brightness.dark,
      primary: darkPrimary,
      onPrimary: const Color(0xFF0E0F14),
      primaryContainer: const Color(0xFF271F4F),
      onPrimaryContainer: const Color(0xFFDDD6FE),
      secondary: accentColor,
      surface: darkCard,
      onSurface: ink,
      onSurfaceVariant: secondary,
      outline: const Color(0xFF34384A),
      outlineVariant: darkBorder,
      error: const Color(0xFFF97066),
    );

    final textTheme = _buildTextTheme(base.textTheme, ink, secondary);

    return base.copyWith(
      colorScheme: cs,
      scaffoldBackgroundColor: darkBackground,
      canvasColor: darkBackground,
      hoverColor: darkPrimary.withValues(alpha: 0.08),
      splashColor: darkPrimary.withValues(alpha: 0.12),
      highlightColor: darkPrimary.withValues(alpha: 0.06),
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: darkBackground,
        surfaceTintColor: Colors.transparent,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: _inter(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.4,
          color: ink,
        ),
        iconTheme: const IconThemeData(color: ink, size: 22),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: darkCardElevated,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: darkBorder),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: darkCard,
        selectedColor: const Color(0xFF271F4F),
        side: const BorderSide(color: darkBorder),
        shape: const StadiumBorder(),
        labelStyle: _inter(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: ink,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: darkCard,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 68,
        indicatorColor: const Color(0xFF271F4F),
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return _inter(
            fontSize: 11.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? darkPrimary : secondary,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 22,
            color: selected ? darkPrimary : secondary,
          );
        }),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: darkCard,
        selectedItemColor: darkPrimary,
        unselectedItemColor: secondary,
        showUnselectedLabels: true,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
      ),
      cardTheme: CardThemeData(
        color: darkCard,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: darkBorder, width: 1),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: darkCardElevated,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: darkCard,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: darkBorder,
        thickness: 1,
        space: 1,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          side: const BorderSide(color: darkBorder),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkCardElevated,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: darkBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: darkBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: darkPrimary, width: 1.8),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: darkCardElevated,
        contentTextStyle: _inter(color: ink, fontSize: 13.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}
