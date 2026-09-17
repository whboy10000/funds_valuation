import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// iOS App Store 风格设计令牌。
///
/// 配色参考 iOS Human Interface Guidelines：
/// 浅色分组背景 #F2F2F7、卡片纯白、强调色 #007AFF；
/// 深色纯黑底、卡片 #1C1C1E、强调色 #0A84FF。
class IosColors {
  IosColors._();

  static const blue = Color(0xFF007AFF);
  static const blueDark = Color(0xFF0A84FF);
  static const green = Color(0xFF34C759);

  static const groupedBgLight = Color(0xFFF2F2F7);
  static const groupedBgDark = Color(0xFF000000);

  static const cardLight = Color(0xFFFFFFFF);
  static const cardDark = Color(0xFF1C1C1E);

  static const fillLight = Color(0xFFEFEFF0); // tertiarySystemFill
  static const fillDark = Color(0xFF2C2C2E);

  static const groupedFillLight = Color(0xFFE9E9EB); // 分段控件底
  static const groupedFillDark = Color(0xFF3A3A3C);

  static const labelLight = Color(0xFF1C1C1E);
  static const labelDark = Color(0xFFFFFFFF);

  static const secondaryLight = Color(0xFF86868B);
  static const secondaryDark = Color(0xFF98989F);

  static const separatorLight = Color(0xFFC8C8CA);
  static const separatorDark = Color(0xFF38383A);

  static const dangerLight = Color(0xFFFF3B30);
  static const dangerDark = Color(0xFFFF453A);
}

/// 全局主题（[Brightness.light] / [Brightness.dark]）。
ThemeData buildAppTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;

  final primary = dark ? IosColors.blueDark : IosColors.blue;
  final scaffoldBg =
      dark ? IosColors.groupedBgDark : IosColors.groupedBgLight;
  final card = dark ? IosColors.cardDark : IosColors.cardLight;
  final fill = dark ? IosColors.fillDark : IosColors.fillLight;
  final label = dark ? IosColors.labelDark : IosColors.labelLight;
  final secondary = dark ? IosColors.secondaryDark : IosColors.secondaryLight;
  final separator =
      dark ? IosColors.separatorDark : IosColors.separatorLight;
  final danger = dark ? IosColors.dangerDark : IosColors.dangerLight;

  final scheme = ColorScheme(
    brightness: brightness,
    primary: primary,
    onPrimary: Colors.white,
    primaryContainer: primary.withValues(alpha: dark ? 0.24 : 0.12),
    onPrimaryContainer: primary,
    secondary: primary,
    onSecondary: Colors.white,
    secondaryContainer: primary.withValues(alpha: dark ? 0.24 : 0.12),
    onSecondaryContainer: primary,
    tertiary: const Color(0xFFAF52DE),
    onTertiary: Colors.white,
    error: danger,
    onError: Colors.white,
    surface: card,
    onSurface: label,
    surfaceContainerLowest: card,
    surfaceContainerLow: card,
    surfaceContainer: scaffoldBg,
    surfaceContainerHigh: fill,
    surfaceContainerHighest: fill,
    onSurfaceVariant: dark ? const Color(0xFFEBEBF5) : const Color(0xFF3C3C43),
    outline: secondary,
    outlineVariant: separator,
  );

  final textTheme = const TextTheme().apply(
    bodyColor: label,
    displayColor: label,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: scaffoldBg,
    textTheme: textTheme,
    splashFactory: NoSplash.splashFactory,
    splashColor: Colors.transparent,
    highlightColor: dark
        ? Colors.white.withValues(alpha: 0.05)
        : Colors.black.withValues(alpha: 0.04),
    dividerColor: separator,
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
        TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
      },
    ),

    // ---------- 导航栏（详情页使用紧凑内联标题） ----------
    appBarTheme: AppBarTheme(
      backgroundColor: scaffoldBg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: label,
        letterSpacing: -0.2,
      ),
      iconTheme: IconThemeData(color: label),
      actionsIconTheme: IconThemeData(color: primary),
    ),

    // ---------- 底部标签栏（无选中药丸，选中蓝图标） ----------
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: card,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 60,
      indicatorColor: Colors.transparent,
      indicatorShape: const StadiumBorder(),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
            size: 25,
            color: states.contains(WidgetState.selected)
                ? primary
                : secondary,
          )),
      labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
            fontSize: 10.5,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? primary
                : secondary,
          )),
    ),

    // ---------- 宽屏侧边导航 ----------
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: card,
      elevation: 0,
      minExtendedWidth: 92,
      indicatorColor: primary,
      selectedIconTheme: const IconThemeData(color: Colors.white, size: 24),
      unselectedIconTheme: IconThemeData(color: secondary, size: 24),
      selectedLabelTextStyle: TextStyle(
          fontSize: 12, fontWeight: FontWeight.w600, color: primary),
      unselectedLabelTextStyle:
          TextStyle(fontSize: 12, color: secondary),
    ),

    // ---------- 按钮 ----------
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: const StadiumBorder(),
        minimumSize: const Size(0, 46),
        padding: const EdgeInsets.symmetric(horizontal: 22),
        textStyle:
            const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: primary,
        shape: const StadiumBorder(),
        textStyle:
            const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: label,
        side: BorderSide(color: separator),
        shape: const StadiumBorder(),
        minimumSize: const Size(0, 38),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        textStyle:
            const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),

    // ---------- iOS 胶囊开关 ----------
    switchTheme: SwitchThemeData(
      thumbColor:
          const WidgetStatePropertyAll(Colors.white),
      trackColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected)
              ? IosColors.green
              : fill),
      trackOutlineColor:
          const WidgetStatePropertyAll(Colors.transparent),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),

    // ---------- 胶囊选择标签 ----------
    chipTheme: ChipThemeData(
      shape: const StadiumBorder(),
      side: BorderSide.none,
      showCheckmark: false,
      checkmarkColor: Colors.white,
      backgroundColor: fill,
      selectedColor: primary,
      disabledColor: fill,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      labelStyle: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: dark ? const Color(0xFFE5E5EA) : const Color(0xFF3C3C43),
      ),
      secondaryLabelStyle: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      ),
      brightness: brightness,
    ),

    // ---------- 分段控件（iOS segmented） ----------
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? (dark ? const Color(0xFF636363) : Colors.white)
                : Colors.transparent),
        foregroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? label : secondary),
        elevation: const WidgetStatePropertyAll(0),
        shadowColor: const WidgetStatePropertyAll(Colors.transparent),
        side: const WidgetStatePropertyAll(BorderSide.none),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
        textStyle: const WidgetStatePropertyAll(
            TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        iconColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? label : secondary),
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    ),

    // ---------- 输入框：灰底圆角填充 ----------
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: fill,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      labelStyle: TextStyle(fontSize: 14, color: secondary),
      hintStyle: TextStyle(fontSize: 14, color: secondary),
      helperStyle: TextStyle(fontSize: 12, color: secondary),
      prefixIconColor: secondary,
      suffixIconColor: secondary,
    ),

    // ---------- 卡片 / 列表 ----------
    cardTheme: CardThemeData(
      color: card,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: primary,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      titleTextStyle: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: label,
          height: 1.35),
      subtitleTextStyle: TextStyle(fontSize: 12.5, color: secondary),
    ),
    dividerTheme: DividerThemeData(
      color: separator,
      thickness: 0.5,
      space: 0.5,
    ),

    // ---------- 选项卡（板块页） ----------
    tabBarTheme: TabBarThemeData(
      labelColor: label,
      unselectedLabelColor: secondary,
      labelStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      unselectedLabelStyle:
          const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
      indicatorColor: primary,
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: Colors.transparent,
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      labelPadding: const EdgeInsets.symmetric(horizontal: 20),
    ),

    // ---------- 弹层 ----------
    dialogTheme: DialogThemeData(
      backgroundColor: card,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      titleTextStyle: TextStyle(
          fontSize: 17, fontWeight: FontWeight.w600, color: label),
      contentTextStyle: TextStyle(fontSize: 14, height: 1.5, color: label),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: card,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      modalElevation: 0,
      showDragHandle: true,
      dragHandleColor: dark
          ? const Color(0xFF48484A)
          : const Color(0xFFD1D1D6),
      dragHandleSize: const Size(36, 5),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: card,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.15),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: dark ? const Color(0xFFF2F2F7) : const Color(0xFF1C1C1E),
      contentTextStyle: TextStyle(
          fontSize: 13.5,
          color: dark ? IosColors.labelLight : Colors.white),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: const Color(0xCC1C1C1E),
        borderRadius: BorderRadius.circular(8),
      ),
      textStyle: const TextStyle(fontSize: 12, color: Colors.white),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    ),

    progressIndicatorTheme: ProgressIndicatorThemeData(color: primary),
    iconTheme: IconThemeData(color: label),
  );
}

/// 状态栏图标样式（浅色背景深色图标 / 深色背景浅色图标）。
SystemUiOverlayStyle overlayStyleFor(Brightness brightness) =>
    brightness == Brightness.light
        ? const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.dark,
            statusBarBrightness: Brightness.light,
            systemNavigationBarColor: Colors.transparent,
          )
        : const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.light,
            statusBarBrightness: Brightness.dark,
            systemNavigationBarColor: Colors.transparent,
          );

/// 全局滚动行为：iOS 回弹、无 Android 发光边缘。
class IosScrollBehavior extends MaterialScrollBehavior {
  const IosScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics());
}
