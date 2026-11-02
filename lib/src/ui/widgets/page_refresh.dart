import 'package:flutter/widgets.dart';

import '../../controllers/app_controller.dart';

/// Marks whether the wrapped page is the visible tab of the shell.
///
/// Hidden pages keep their state (scroll position, selections) inside the
/// [IndexedStack] but are not rebuilt while the user works elsewhere.
class ActivePageScope extends InheritedWidget {
  const ActivePageScope({required this.active, required super.child, super.key});

  final bool active;

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ActivePageScope>()?.active ??
      true;

  @override
  bool updateShouldNotify(ActivePageScope oldWidget) =>
      oldWidget.active != active;
}

/// Rebuilds [builder] when [controller] notifies, but only while the page is
/// the active tab. A hidden page refreshes once when it becomes visible again
/// through the [ActivePageScope] dependency.
class PageRefresh extends StatefulWidget {
  const PageRefresh({
    required this.controller,
    required this.builder,
    super.key,
  });

  final AppController controller;
  final WidgetBuilder builder;

  @override
  State<PageRefresh> createState() => _PageRefreshState();
}

class _PageRefreshState extends State<PageRefresh> {
  bool _active = true;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleControllerChange);
  }

  @override
  void didUpdateWidget(PageRefresh oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleControllerChange);
      widget.controller.addListener(_handleControllerChange);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _active = ActivePageScope.of(context);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChange);
    super.dispose();
  }

  void _handleControllerChange() {
    if (!mounted || !_active) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}
