import 'package:flutter/material.dart';

/// Pushes [screen] as a full-screen page on the ROOT navigator.
///
/// Atrium's bottom-nav shell gives every tab its own branch navigator, and
/// GoRouter rebuilds those declaratively - a page pushed imperatively onto a
/// branch navigator is not in GoRouter's route table, so the next shell
/// rebuild sweeps it away (the screen opens, then vanishes). The root
/// navigator is not managed declaratively, so imperative pushes are safe
/// there - and a root-level page covers the bottom nav bar, which is exactly
/// what Atrium's detail screens want.
///
/// Use this instead of raw `Navigator.of(context).push(...)`. For sheets and
/// dialogs, pass `useRootNavigator: true` for the same reason (showDialog
/// already defaults to it; showModalBottomSheet and showSearch do not).
Future<T?> pushScreen<T>(BuildContext context, Widget screen) =>
    Navigator.of(context, rootNavigator: true).push<T>(
      MaterialPageRoute<T>(builder: (_) => screen),
    );
