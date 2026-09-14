import 'package:flutter/material.dart';

class AppTheme {
  // Colores principales basados en los mockups del taller
  static const Color primary = Color(0xFF1E88E5);       // Azul principal
  static const Color primaryDark = Color(0xFF1565C0);    // Azul oscuro
  static const Color accent = Color(0xFF00C853);         // Verde para acciones positivas
  static const Color background = Color(0xFF0D1B2A);     // Fondo oscuro principal
  static const Color surface = Color(0xFF1B2838);        // Fondo de tarjetas
  static const Color surfaceLight = Color(0xFF243447);   // Fondo de inputs
  static const Color error = Color(0xFFEF5350);          // Rojo para errores
  static const Color warning = Color(0xFFFF9800);        // Naranja para pendientes
  static const Color buttonAccent = Color(0xFFE65100);   // Naranja fuerte para botón login
  static const Color textPrimary = Color(0xFFFFFFFF);    // Texto principal
  static const Color textSecondary = Color(0xFFB0BEC5);  // Texto secundario
  static const Color divider = Color(0xFF37474F);        // Divisores

  // Colores de estado de stock
  static const Color stockAvailable = Color(0xFF00C853);
  static const Color stockEmpty = Color(0xFFEF5350);

  // Colores de estado de órdenes
  static const Color statusEnProceso = Color(0xFF1E88E5);
  static const Color statusEmitido = Color(0xFF00C853);
  static const Color statusPendiente = Color(0xFFFF9800);
  static const Color statusAnulado = Color(0xFFEF5350);
  static const Color statusFacturado = Color(0xFF7E57C2);

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      primaryColor: primary,
      scaffoldBackgroundColor: background,
      colorScheme: const ColorScheme.dark(
        primary: primary,
        secondary: accent,
        surface: surface,
        error: error,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        foregroundColor: textPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceLight,
        hintStyle: const TextStyle(color: textSecondary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: error, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: Colors.white,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: primary,
        unselectedItemColor: textSecondary,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surface,
        contentTextStyle: const TextStyle(color: textPrimary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        behavior: SnackBarBehavior.floating,
      ),
      dividerTheme: const DividerThemeData(
        color: divider,
        thickness: 0.5,
      ),
    );
  }
}