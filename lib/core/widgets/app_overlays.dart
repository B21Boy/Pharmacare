import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// `.toast`: dark pill at the bottom, 2.3 s. Use showToast(context, 'Saved').
void showToast(BuildContext context, String message) {
  final m = ScaffoldMessenger.of(context);
  m.clearSnackBars();
  m.showSnackBar(SnackBar(
    content: Text(message,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white, fontSize: 13)),
    backgroundColor: AppColors.toastBg,
    behavior: SnackBarBehavior.floating,
    margin: const EdgeInsets.only(left: 40, right: 40, bottom: 100),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    duration: const Duration(milliseconds: 2300),
  ));
}

/// `.sheet`: bottom sheet, radius 20, grab handle, max 90% height.
Future<T?> showAppSheet<T>(BuildContext context,
    {required WidgetBuilder builder}) {
  final c = context.c;
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: c.card,
    barrierColor: const Color(0x80081028),
    constraints:
        BoxConstraints(maxHeight: MediaQuery.of(context).size.height * .9),
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            16, 10, 16, 18 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                      color: c.ln2, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Flexible(child: SingleChildScrollView(child: builder(ctx))),
            ]),
      ),
    ),
  );
}
