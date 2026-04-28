import 'package:flutter/material.dart';

class AppResponsive {
  static const double railBreakpoint = 1024;
  static const double extendedRailBreakpoint = 1360;
  static const double sheetDialogBreakpoint = 900;
  static const double wideContentBreakpoint = 1440;

  static bool useNavigationRail(double width) => width >= railBreakpoint;

  static bool extendNavigationRail(double width) =>
      width >= extendedRailBreakpoint;

  static bool preferSheetDialog(double width) => width >= sheetDialogBreakpoint;

  static double horizontalPadding(double width) {
    if (width >= wideContentBreakpoint) {
      return 32;
    }
    if (width >= railBreakpoint) {
      return 24;
    }
    return 16;
  }

  static double defaultPageMaxWidth(double width) {
    if (width >= wideContentBreakpoint) {
      return 1120;
    }
    if (width >= railBreakpoint) {
      return 1040;
    }
    return double.infinity;
  }
}

class AppPageScrollView extends StatelessWidget {
  const AppPageScrollView({
    super.key,
    required this.children,
    this.maxWidth,
    this.topPadding = 16,
    this.bottomPadding = 24,
    this.keyboardDismissBehavior = ScrollViewKeyboardDismissBehavior.manual,
  });

  final List<Widget> children;
  final double? maxWidth;
  final double topPadding;
  final double bottomPadding;
  final ScrollViewKeyboardDismissBehavior keyboardDismissBehavior;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.maxWidth;
        final double horizontalPadding = AppResponsive.horizontalPadding(width);
        final double resolvedMaxWidth =
            maxWidth ?? AppResponsive.defaultPageMaxWidth(width);

        final Widget listView = ListView(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            topPadding,
            horizontalPadding,
            bottomPadding,
          ),
          keyboardDismissBehavior: keyboardDismissBehavior,
          children: children,
        );

        if (!resolvedMaxWidth.isFinite) {
          return listView;
        }

        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: resolvedMaxWidth),
            child: listView,
          ),
        );
      },
    );
  }
}

Future<T?> showAdaptiveSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  double maxWidth = 720,
  bool isScrollControlled = true,
  bool showDragHandle = true,
}) {
  final double width = MediaQuery.sizeOf(context).width;
  if (!AppResponsive.preferSheetDialog(width)) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      showDragHandle: showDragHandle,
      builder: builder,
    );
  }

  final double horizontalInset = width >= AppResponsive.wideContentBreakpoint
      ? 56
      : 32;

  return showDialog<T>(
    context: context,
    builder: (BuildContext dialogContext) {
      return Dialog(
        clipBehavior: Clip.antiAlias,
        insetPadding: EdgeInsets.symmetric(
          horizontal: horizontalInset,
          vertical: 24,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: builder(dialogContext),
        ),
      );
    },
  );
}
