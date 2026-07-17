import 'package:flutter/material.dart';

/// Central theme configuration for Blueprint UI
class BpTheme {
  BpTheme._();

  /// Light theme
  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,

      /// 🔹 Colors
      colorScheme: const ColorScheme.light(
        primary: Colors.black,
        secondary: Colors.grey,
        surface: Colors.white,
      ),

      /// 🔹 Scaffold
      scaffoldBackgroundColor: Colors.white,

      /// 🔹 Typography
      textTheme: const TextTheme(
        bodyLarge: TextStyle(fontSize: 16),
        bodyMedium: TextStyle(fontSize: 14),
        titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
      ),

      /// 🔹 AppBar
      appBarTheme: const AppBarTheme(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
    );
  }

  /// Dark theme (optional but ready)
  static ThemeData dark() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,

      colorScheme: const ColorScheme.dark(
        primary: Colors.white,
        secondary: Colors.grey,
        surface: Colors.black,
      ),

      scaffoldBackgroundColor: Colors.black,
    );
  }
}