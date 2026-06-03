import 'package:flutter/material.dart';

import 'app_design.dart';

class AppTheme {
  static ThemeData light() {
    final ColorScheme scheme =
        ColorScheme.fromSeed(
          seedColor: AppDesign.brand,
          primary: AppDesign.brand,
          secondary: AppDesign.accent,
          surface: AppDesign.canvas,
          brightness: Brightness.light,
        ).copyWith(
          surface: AppDesign.canvas,
          onSurface: AppDesign.ink,
          surfaceContainerLowest: AppDesign.paper,
          surfaceContainerLow: AppDesign.paper,
          surfaceContainer: AppDesign.paperSoft,
          surfaceContainerHigh: AppDesign.paperSoft,
          surfaceContainerHighest: const Color(0xFFECEAE5),
          outline: const Color(0xFFD8D5CD),
          outlineVariant: AppDesign.line,
          primaryContainer: AppDesign.brandSoft,
          onPrimaryContainer: AppDesign.brand,
          secondaryContainer: const Color(0xFFF0E7E1),
          onSecondaryContainer: AppDesign.accent,
        );

    return _base(
      scheme: scheme,
      scaffold: AppDesign.canvas,
      card: AppDesign.paper,
      field: AppDesign.paper,
      shadow: const Color(0x08000000),
      brightness: Brightness.light,
    );
  }

  static ThemeData dark() {
    final ColorScheme scheme =
        ColorScheme.fromSeed(
          seedColor: AppDesign.brand,
          brightness: Brightness.dark,
        ).copyWith(
          surface: AppDesign.darkCanvas,
          onSurface: AppDesign.darkInk,
          surfaceContainerLowest: AppDesign.darkPaper,
          surfaceContainerLow: AppDesign.darkPaper,
          surfaceContainer: AppDesign.darkPaperSoft,
          surfaceContainerHigh: AppDesign.darkPaperSoft,
          surfaceContainerHighest: const Color(0xFF333333),
          outline: const Color(0xFF464646),
          outlineVariant: AppDesign.darkLine,
          primary: const Color(0xFF7FB9B0),
          primaryContainer: const Color(0xFF243B38),
          onPrimaryContainer: const Color(0xFFCBE7E1),
          secondary: const Color(0xFFD0A58F),
          secondaryContainer: const Color(0xFF3C2D26),
          onSecondaryContainer: const Color(0xFFF0D2C2),
        );

    return _base(
      scheme: scheme,
      scaffold: AppDesign.darkCanvas,
      card: AppDesign.darkPaper,
      field: AppDesign.darkPaper,
      shadow: Colors.transparent,
      brightness: Brightness.dark,
    );
  }

  static ThemeData _base({
    required ColorScheme scheme,
    required Color scaffold,
    required Color card,
    required Color field,
    required Color shadow,
    required Brightness brightness,
  }) {
    final TextTheme textTheme = Typography.material2021(
      platform: TargetPlatform.iOS,
    ).black.apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffold,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: 20,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: scheme.onSurface,
          fontSize: 22,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        ),
        iconTheme: IconThemeData(color: scheme.onSurfaceVariant),
        actionsIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
      ),
      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        shadowColor: shadow,
        surfaceTintColor: Colors.transparent,
        margin: const EdgeInsets.symmetric(vertical: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDesign.radiusMd),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.onSurface,
          foregroundColor: scheme.surface,
          disabledBackgroundColor: scheme.surfaceContainerHighest,
          disabledForegroundColor: scheme.onSurfaceVariant,
          minimumSize: const Size.fromHeight(44),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDesign.radiusSm),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.onSurface,
        foregroundColor: scheme.surface,
        elevation: 1,
        highlightElevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDesign.radiusLg),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.onSurface,
          minimumSize: const Size.fromHeight(44),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          side: BorderSide(color: scheme.outlineVariant),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDesign.radiusSm),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.onSurfaceVariant,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDesign.radiusSm),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainer,
        selectedColor: scheme.primaryContainer,
        secondarySelectedColor: scheme.primaryContainer,
        side: BorderSide(color: scheme.outlineVariant),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDesign.radiusSm),
        ),
        labelStyle: TextStyle(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w500,
          letterSpacing: 0,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 64,
        elevation: 0,
        backgroundColor: scheme.surfaceContainerLowest,
        indicatorColor: scheme.surfaceContainerHighest,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDesign.radiusSm),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith<TextStyle?>((
          Set<WidgetState> states,
        ) {
          return TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w500,
            letterSpacing: 0,
          );
        }),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        indicatorColor: scheme.surfaceContainerHighest,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDesign.radiusSm),
        ),
        selectedIconTheme: IconThemeData(color: scheme.onSurface),
        unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
        selectedLabelTextStyle: TextStyle(
          color: scheme.onSurface,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        ),
        unselectedLabelTextStyle: TextStyle(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w500,
          letterSpacing: 0,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: field,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        hintStyle: TextStyle(color: scheme.onSurfaceVariant),
        labelStyle: TextStyle(color: scheme.onSurfaceVariant),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDesign.radiusSm),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDesign.radiusSm),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDesign.radiusSm),
          borderSide: BorderSide(color: scheme.onSurface, width: 1.2),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDesign.radiusLg),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppDesign.radiusLg),
          ),
        ),
      ),
      textTheme: textTheme.copyWith(
        displaySmall: textTheme.displaySmall?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
          height: 1.08,
        ),
        headlineMedium: textTheme.headlineMedium?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
          height: 1.12,
        ),
        headlineSmall: textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        ),
        titleLarge: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        ),
        titleMedium: textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        ),
        bodyLarge: textTheme.bodyLarge?.copyWith(height: 1.5, letterSpacing: 0),
        bodyMedium: textTheme.bodyMedium?.copyWith(
          height: 1.5,
          letterSpacing: 0,
        ),
        labelLarge: textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        ),
      ),
    );
  }
}
