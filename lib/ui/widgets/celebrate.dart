/// Feestelijke melding (reeks, level, nieuwe badge) bovenaan het scherm, in de stijl van de app.
///
/// Geen zwarte SnackBar: die stond onderaan tussen de knoppen, en met een knop ("Delen") bleef ze staan tot je
/// tikte. Deze komt bovenaan, verdwijnt na een paar seconden vanzelf, en weg met een tik of een veeg omhoog.
/// Meerdere meldingen na elkaar wachten op hun beurt.
library;

import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';

import '../theme.dart';

class _Celebration {
  _Celebration(this.leading, this.text, this.actionLabel, this.onAction);
  final Widget leading;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;
}

final _queue = Queue<_Celebration>();
OverlayEntry? _current;

/// Hoe lang een melding blijft staan.
const celebrationDuration = Duration(seconds: 4);

void showCelebration(BuildContext context, {required Widget leading, required String text, String? actionLabel, VoidCallback? onAction}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  _queue.add(_Celebration(leading, text, actionLabel, onAction));
  if (_current == null) _next(overlay);
}

void _next(OverlayState overlay) {
  if (_queue.isEmpty || !overlay.mounted) {
    _current = null;
    return;
  }
  final c = _queue.removeFirst();
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _CelebrationToast(
      c: c,
      onGone: () {
        entry.remove();
        _next(overlay);
      },
    ),
  );
  _current = entry;
  overlay.insert(entry);
}

class _CelebrationToast extends StatefulWidget {
  const _CelebrationToast({required this.c, required this.onGone});
  final _Celebration c;
  final VoidCallback onGone;

  @override
  State<_CelebrationToast> createState() => _CelebrationToastState();
}

class _CelebrationToastState extends State<_CelebrationToast> with SingleTickerProviderStateMixin {
  late final _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 220))..forward();
  Timer? _timer;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(celebrationDuration, _close);
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    _timer?.cancel();
    if (mounted) await _anim.reverse();
    widget.onGone();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final top = MediaQuery.paddingOf(context).top + 10;
    final c = widget.c;
    return Positioned(
      top: top,
      left: 0,
      right: 0,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, -1.4), end: Offset.zero).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic)),
        child: FadeTransition(
          opacity: _anim,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Dismissible(
                  key: const ValueKey('celebration'),
                  direction: DismissDirection.up,
                  onDismissed: (_) {
                    _timer?.cancel();
                    _closing = true;
                    widget.onGone();
                  },
                  child: Material(
                    color: p.surface,
                    elevation: 6,
                    shadowColor: Colors.black.withValues(alpha: 0.25),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: p.line)),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: _close,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
                        child: Row(
                          children: [
                            c.leading,
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(c.text, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.ink)),
                            ),
                            if (c.actionLabel != null)
                              TextButton(
                                onPressed: () {
                                  _close();
                                  c.onAction?.call();
                                },
                                child: Text(c.actionLabel!),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
