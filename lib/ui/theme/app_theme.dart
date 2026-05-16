import 'package:flutter/material.dart';

/// Тема Nusha 3 — Telegram-стиль
class AppTheme {
  // ───── Цвета светлой темы ─────
  static const Color lightBackground     = Color(0xFFFFFFFF);
  static const Color lightSurface        = Color(0xFFF5F5F5);
  static const Color lightBubbleOutgoing = Color(0xFFEFFDDE); // зелёный как Telegram
  static const Color lightBubbleIncoming = Color(0xFFFFFFFF);
  static const Color lightAccent         = Color(0xFF2AABEE); // синий Telegram
  static const Color lightAccentDark     = Color(0xFF1A96D9);
  static const Color lightText           = Color(0xFF000000);
  static const Color lightTextSecondary  = Color(0xFF8E8E93);
  static const Color lightDivider        = Color(0xFFE5E5EA);
  static const Color lightNavBar         = Color(0xFFFFFFFF);
  static const Color lightUnread         = Color(0xFF2AABEE);

  // ───── Цвета тёмной темы ─────
  static const Color darkBackground      = Color(0xFF1C1C1E);
  static const Color darkSurface         = Color(0xFF2C2C2E);
  static const Color darkBubbleOutgoing  = Color(0xFF2B5278);
  static const Color darkBubbleIncoming  = Color(0xFF2C2C2E);
  static const Color darkAccent          = Color(0xFF2AABEE);
  static const Color darkText            = Color(0xFFFFFFFF);
  static const Color darkTextSecondary   = Color(0xFF8E8E93);
  static const Color darkDivider         = Color(0xFF38383A);
  static const Color darkNavBar          = Color(0xFF1C1C1E);

  // ───── Цвета статусов доставки ─────
  static const Color deliveryInternet   = Color(0xFF2AABEE);  // синий ✓✓
  static const Color deliveryWifi       = Color(0xFF4CAF50);  // зелёный
  static const Color deliveryBluetooth  = Color(0xFF9C27B0);  // фиолетовый
  static const Color deliverySms        = Color(0xFFFF9800);  // оранжевый
  static const Color deliveryPending    = Color(0xFF9E9E9E);  // серый

  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.light(
        primary: lightAccent,
        secondary: lightAccent,
        surface: lightSurface,
        background: lightBackground,
        onPrimary: Colors.white,
        onSurface: lightText,
      ),
      fontFamily: 'Inter',
      scaffoldBackgroundColor: lightBackground,
      appBarTheme: const AppBarTheme(
        backgroundColor: lightNavBar,
        foregroundColor: lightText,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: lightText, fontFamily: 'Inter',
          fontSize: 17, fontWeight: FontWeight.w600,
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: lightNavBar,
        selectedItemColor: lightAccent,
        unselectedItemColor: Color(0xFF8E8E93),
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedLabelStyle: TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
        unselectedLabelStyle: TextStyle(fontSize: 10),
      ),
      dividerTheme: const DividerThemeData(color: lightDivider, thickness: 0.5, space: 0),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: lightSurface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        hintStyle: const TextStyle(color: Color(0xFF8E8E93)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: lightAccent, foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          minimumSize: const Size(double.infinity, 50),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, fontFamily: 'Inter'),
        ),
      ),
    );
  }

  static ThemeData dark() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.dark(
        primary: darkAccent,
        secondary: darkAccent,
        surface: darkSurface,
        background: darkBackground,
        onPrimary: Colors.white,
        onSurface: darkText,
      ),
      fontFamily: 'Inter',
      scaffoldBackgroundColor: darkBackground,
      appBarTheme: const AppBarTheme(
        backgroundColor: darkNavBar,
        foregroundColor: darkText,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: darkText, fontFamily: 'Inter',
          fontSize: 17, fontWeight: FontWeight.w600,
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: darkNavBar,
        selectedItemColor: darkAccent,
        unselectedItemColor: Color(0xFF8E8E93),
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      dividerTheme: const DividerThemeData(color: darkDivider, thickness: 0.5, space: 0),
    );
  }
}
