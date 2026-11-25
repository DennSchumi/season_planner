import 'package:flutter/material.dart';
import 'package:season_planner/core/theme.dart';

/// Zentraler Breakpoint für die Desktop-Web-Ansicht (PC-Browser).
/// Unterhalb dieses Werts bleibt die bewährte Smartphone-Oberfläche 1:1 unverändert.
const double kDesktopBreakpoint = 960.0;
const double kWideDesktopBreakpoint = 1280.0;

extension ResponsiveContext on BuildContext {
  /// `true` auf PC-Browsern / breiten Tablets im Querformat (`>= 960 px`).
  bool get isDesktop => MediaQuery.sizeOf(this).width >= kDesktopBreakpoint;

  /// `true` auf großen Monitoren (`>= 1280 px`).
  bool get isWideDesktop =>
      MediaQuery.sizeOf(this).width >= kWideDesktopBreakpoint;
}

/// Signalisiert untergeordneten Screens, dass sie innerhalb der Desktop-Sidebar-Shell
/// gerendert werden (so blenden sich redundante Mobile-AppBar-Chips wie Modus-Wechsel
/// oder Verbindungsstatus automatisch aus, da sie bereits fest in der Sidebar sitzen).
class DesktopShellScope extends InheritedWidget {
  final bool isDesktopShell;

  const DesktopShellScope({
    super.key,
    required this.isDesktopShell,
    required super.child,
  });

  static bool isInDesktopShell(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<DesktopShellScope>();
    return scope?.isDesktopShell ?? false;
  }

  @override
  bool updateShouldNotify(covariant DesktopShellScope oldWidget) =>
      oldWidget.isDesktopShell != isDesktopShell;
}

/// Zeigt auf dem Smartphone (`< 960 px`) unverändert das gewohnte `showModalBottomSheet`,
/// auf dem PC-Browser (`>= 960 px`) hingegen ein sauberes, zentriertes Desktop-Modal
/// mit abgerundeten Ecken und max. Breite.
Future<T?> showAdaptiveSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
  bool showDragHandle = false,
  Color? backgroundColor,
  Color? barrierColor,
  double desktopMaxWidth = 560,
  double desktopMaxHeightFactor = 0.86,
  bool wrapDesktopCard = true,
}) {
  if (!context.isDesktop) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      showDragHandle: showDragHandle,
      backgroundColor: backgroundColor,
      barrierColor: barrierColor,
      builder: builder,
    );
  }

  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: barrierColor ?? Colors.black.withValues(alpha: 0.42),
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (ctx, _, __) {
      final isDark = Theme.of(ctx).brightness == Brightness.dark;
      final maxHeight =
          MediaQuery.sizeOf(ctx).height * desktopMaxHeightFactor;

      final content = builder(ctx);
      final Widget dialogSurface;
      if (wrapDesktopCard) {
        dialogSurface = Container(
          decoration: BoxDecoration(
            color: isDark ? AppTheme.darkCard : AppTheme.desktopBackground,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isDark ? AppTheme.darkBorder : AppTheme.desktopBorder,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x24101828),
                blurRadius: 36,
                offset: Offset(0, 14),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Material(
            color: Colors.transparent,
            child: content,
          ),
        );
      } else {
        dialogSurface = Material(
          color: Colors.transparent,
          child: content,
        );
      }

      return SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: desktopMaxWidth,
                maxHeight: maxHeight,
              ),
              child: dialogSurface,
            ),
          ),
        ),
      );
    },
    transitionBuilder: (ctx, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}
