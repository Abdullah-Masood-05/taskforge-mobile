import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tokens.dart';

/// Typography helpers. Geist for UI text, JetBrains Mono for eyebrows,
/// references and numbers — same pairing as the web app.
class TFText {
  TFText._();

  static const sansFamily = 'Geist';
  static const monoFamily = 'JetBrainsMono';

  static TextStyle sans({
    double size = 15,
    FontWeight weight = FontWeight.w400,
    Color color = TF.textPrimary,
    double? height,
    double? letterSpacing,
  }) =>
      TextStyle(
        fontFamily: sansFamily,
        fontSize: size,
        fontWeight: weight,
        // Bundled fonts are variable — drive the weight axis explicitly.
        fontVariations: [FontVariation.weight(weight.value.toDouble())],
        color: color,
        height: height,
        letterSpacing: letterSpacing,
      );

  static TextStyle mono({
    double size = 12,
    FontWeight weight = FontWeight.w500,
    Color color = TF.textMuted,
    double? letterSpacing,
  }) =>
      TextStyle(
        fontFamily: monoFamily,
        fontSize: size,
        fontWeight: weight,
        fontVariations: [FontVariation.weight(weight.value.toDouble())],
        color: color,
        letterSpacing: letterSpacing,
      );

  /// Editorial monospace eyebrow / section label (`.eyebrow` on the web).
  static TextStyle eyebrow({Color color = TF.textMuted}) => mono(
        size: 11,
        weight: FontWeight.w600,
        color: color,
        letterSpacing: 2.2,
      );

  static TextStyle h1() => sans(
      size: 28, weight: FontWeight.w600, letterSpacing: -0.6, height: 1.25);
  static TextStyle h2() => sans(
      size: 22, weight: FontWeight.w600, letterSpacing: -0.45, height: 1.3);
  static TextStyle h3() =>
      sans(size: 18, weight: FontWeight.w600, letterSpacing: -0.3, height: 1.3);
  static TextStyle body({Color color = TF.textSecondary}) =>
      sans(size: 14.5, color: color, height: 1.55);
  static TextStyle small({Color color = TF.textMuted}) =>
      sans(size: 12.5, color: color, height: 1.45);
}

class AppTheme {
  AppTheme._();

  static const systemOverlay = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: TF.bgBase,
    systemNavigationBarIconBrightness: Brightness.light,
  );

  static ThemeData dark() {
    const scheme = ColorScheme.dark(
      primary: TF.brand,
      onPrimary: TF.onBrand,
      secondary: TF.brandSecondary,
      onSecondary: TF.onBrand,
      surface: TF.bgSurface,
      onSurface: TF.textPrimary,
      error: TF.danger,
      onError: TF.bgBase,
      outline: TF.borderDefault,
      outlineVariant: TF.borderSubtle,
    );

    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(TF.radiusMd),
      borderSide: const BorderSide(color: TF.borderDefault),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: TF.bgBase,
      canvasColor: TF.bgBase,
      splashFactory: InkSparkle.splashFactory,
      fontFamily: TFText.sansFamily,
      textTheme: TextTheme(
        displaySmall: TFText.h1(),
        headlineMedium: TFText.h2(),
        titleLarge: TFText.h3(),
        titleMedium: TFText.sans(size: 15, weight: FontWeight.w600),
        bodyLarge: TFText.sans(size: 15),
        bodyMedium: TFText.body(),
        bodySmall: TFText.small(),
        labelLarge: TFText.sans(size: 14, weight: FontWeight.w600),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: TF.bgBase,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: systemOverlay,
        titleTextStyle: TFText.sans(size: 17, weight: FontWeight.w600),
        iconTheme: const IconThemeData(color: TF.textSecondary),
      ),
      dividerTheme: const DividerThemeData(
          color: TF.borderSubtle, thickness: 1, space: 1),
      iconTheme: const IconThemeData(color: TF.textSecondary, size: 20),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: TF.bgElevated,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        hintStyle: TFText.sans(size: 14, color: TF.textDisabled),
        labelStyle: TFText.sans(size: 14, color: TF.textMuted),
        border: border,
        enabledBorder: border,
        focusedBorder: border.copyWith(
            borderSide: const BorderSide(color: TF.brand, width: 1.2)),
        errorBorder:
            border.copyWith(borderSide: const BorderSide(color: TF.danger)),
        focusedErrorBorder: border.copyWith(
            borderSide: const BorderSide(color: TF.danger, width: 1.2)),
        errorStyle: TFText.small(color: TF.danger),
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: TF.brand,
        selectionColor: Color(0x4DF5A623),
        selectionHandleColor: TF.brand,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: TF.bgSurface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: TF.bgSurface,
        showDragHandle: true,
        dragHandleColor: TF.borderStrong,
        shape: RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(TF.radiusXl * 2)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: TF.bgSurface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(TF.radiusXl),
          side: const BorderSide(color: TF.borderDefault),
        ),
        titleTextStyle: TFText.h3(),
        contentTextStyle: TFText.body(),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: TF.bgElevated,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(TF.radiusLg),
          side: const BorderSide(color: TF.borderDefault),
        ),
        textStyle: TFText.sans(size: 14),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: TF.bgElevated,
        contentTextStyle: TFText.sans(size: 14),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(TF.radiusLg),
          side: const BorderSide(color: TF.borderDefault),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: TF.brand,
        linearTrackColor: TF.borderDefault,
        circularTrackColor: Colors.transparent,
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(TF.radiusSm)),
        side: const BorderSide(color: TF.borderStrong, width: 1.2),
        fillColor: WidgetStateProperty.resolveWith(
          (s) =>
              s.contains(WidgetState.selected) ? TF.brand : Colors.transparent,
        ),
        checkColor: const WidgetStatePropertyAll(TF.onBrand),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: TF.bgElevated,
        selectedColor: TF.brandLight,
        side: const BorderSide(color: TF.borderDefault),
        labelStyle: TFText.sans(size: 13, color: TF.textSecondary),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(TF.radiusMd)),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: TF.textPrimary,
        unselectedLabelColor: TF.textMuted,
        indicatorColor: TF.brand,
        dividerColor: TF.borderSubtle,
        labelStyle: TFText.sans(size: 14, weight: FontWeight.w600),
        unselectedLabelStyle: TFText.sans(size: 14),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}
