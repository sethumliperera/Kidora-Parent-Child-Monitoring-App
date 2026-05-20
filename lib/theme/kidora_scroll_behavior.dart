import "package:flutter/gestures.dart";
import "package:flutter/material.dart";

/// Tuned scroll/touch so vertical scrolling feels smooth across the app
/// (physics + full pointer set for high-refresh and trackpad).
class KidoraScrollBehavior extends MaterialScrollBehavior {
  const KidoraScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.stylus,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.mouse,
      };

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const BouncingScrollPhysics(
      parent: AlwaysScrollableScrollPhysics(),
    );
  }
}