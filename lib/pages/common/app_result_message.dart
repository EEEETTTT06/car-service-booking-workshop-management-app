import 'dart:async';

import 'package:flutter/material.dart';

enum AppResultType {
  success,
  error,
  warning,
  info,
}

class AppResultMessage {
  AppResultMessage._();

  static OverlayEntry? _currentEntry;

  static void show(
    BuildContext context, {
    required String message,
    AppResultType? type,
    Duration duration = const Duration(seconds: 3),
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);

    if (overlay == null) {
      debugPrint('Result message: $message');
      return;
    }

    showOnOverlay(
      overlay,
      message: message,
      type: type,
      duration: duration,
    );
  }

  static void showOnOverlay(
    OverlayState overlay, {
    required String message,
    AppResultType? type,
    Duration duration = const Duration(seconds: 3),
  }) {
    final cleanMessage = message.trim();
    if (cleanMessage.isEmpty) return;

    _removeCurrentEntry();

    final resolvedType = type ?? inferType(cleanMessage);
    late final OverlayEntry entry;

    entry = OverlayEntry(
      builder: (context) => _AppResultOverlay(
        message: cleanMessage,
        type: resolvedType,
        duration: duration,
        onDismiss: () {
          if (entry.mounted) {
            entry.remove();
          }

          if (identical(_currentEntry, entry)) {
            _currentEntry = null;
          }
        },
      ),
    );

    _currentEntry = entry;
    overlay.insert(entry);
  }

  static void success(
    BuildContext context, {
    required String message,
    Duration duration = const Duration(seconds: 3),
  }) {
    show(
      context,
      message: message,
      type: AppResultType.success,
      duration: duration,
    );
  }

  static void error(
    BuildContext context, {
    required String message,
    Duration duration = const Duration(seconds: 4),
  }) {
    show(
      context,
      message: message,
      type: AppResultType.error,
      duration: duration,
    );
  }

  static void warning(
    BuildContext context, {
    required String message,
    Duration duration = const Duration(seconds: 3),
  }) {
    show(
      context,
      message: message,
      type: AppResultType.warning,
      duration: duration,
    );
  }

  static void info(
    BuildContext context, {
    required String message,
    Duration duration = const Duration(seconds: 3),
  }) {
    show(
      context,
      message: message,
      type: AppResultType.info,
      duration: duration,
    );
  }

  static AppResultType inferType(String message) {
    final value = message.toLowerCase();

    const errorWords = <String>[
      'failed',
      'failure',
      'error',
      'exception',
      'unable',
      'unavailable',
      'invalid',
      'incorrect',
      'denied',
      'not logged in',
      'not authorised',
      'not authorized',
      'permission',
      'duplicate',
      'violates',
      'database',
      'relation',
      'column',
      'syntax',
      'policy',
      'missing from-clause',
    ];

    const warningWords = <String>[
      'please',
      'required',
      'must ',
      'must be',
      'cannot',
      "can't",
      'not available',
      'not found',
      'is missing',
      'missing.',
      'already',
      'fully booked',
      'full date',
      'closed',
      'limit',
      'past date',
      'no workshop',
      'no vehicle',
      'no service',
      'no notification',
      'no quotation',
      'no record',
      'wait',
    ];

    const successWords = <String>[
      'success',
      'successfully',
      'created',
      'saved',
      'updated',
      'approved',
      'rejected',
      'confirmed',
      'completed',
      'cancelled',
      'canceled',
      'deleted',
      'cleared',
      'restored',
      'added',
      'removed',
      'submitted',
      'uploaded',
      'selected',
      'verified',
      'sent',
      'marked as read',
      'turned on',
      'turned off',
      'enabled',
      'disabled',
      'changed',
      'linked',
    ];

    if (errorWords.any(value.contains)) {
      return AppResultType.error;
    }

    if (warningWords.any(value.contains)) {
      return AppResultType.warning;
    }

    if (successWords.any(value.contains)) {
      return AppResultType.success;
    }

    return AppResultType.info;
  }

  static void _removeCurrentEntry() {
    final entry = _currentEntry;
    _currentEntry = null;

    if (entry != null && entry.mounted) {
      entry.remove();
    }
  }
}

class _AppResultOverlay extends StatefulWidget {
  final String message;
  final AppResultType type;
  final Duration duration;
  final VoidCallback onDismiss;

  const _AppResultOverlay({
    required this.message,
    required this.type,
    required this.duration,
    required this.onDismiss,
  });

  @override
  State<_AppResultOverlay> createState() => _AppResultOverlayState();
}

class _AppResultOverlayState extends State<_AppResultOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController animationController;
  late final Animation<double> fadeAnimation;
  late final Animation<Offset> slideAnimation;
  Timer? dismissTimer;
  bool isDismissing = false;

  @override
  void initState() {
    super.initState();

    animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
      reverseDuration: const Duration(milliseconds: 190),
    );

    fadeAnimation = CurvedAnimation(
      parent: animationController,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    );

    slideAnimation = Tween<Offset>(
      begin: const Offset(0, -0.35),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: animationController,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      ),
    );

    animationController.forward();
    dismissTimer = Timer(widget.duration, dismiss);
  }

  Future<void> dismiss() async {
    if (isDismissing) return;
    isDismissing = true;
    dismissTimer?.cancel();

    if (mounted) {
      await animationController.reverse();
    }

    widget.onDismiss();
  }

  @override
  void dispose() {
    dismissTimer?.cancel();
    animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = _ResultStyle.fromType(widget.type);

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        minimum: const EdgeInsets.fromLTRB(14, 12, 14, 0),
        child: SlideTransition(
          position: slideAnimation,
          child: FadeTransition(
            opacity: fadeAnimation,
            child: Material(
              color: Colors.transparent,
              child: Semantics(
                liveRegion: true,
                label: '${style.title}: ${widget.message}',
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 560),
                  padding: const EdgeInsets.fromLTRB(14, 13, 8, 13),
                  decoration: BoxDecoration(
                    color: style.backgroundColor,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: style.color.withOpacity(0.28),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.14),
                        blurRadius: 18,
                        offset: const Offset(0, 7),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: style.color,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          style.icon,
                          color: Colors.white,
                          size: 27,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              style.title,
                              style: TextStyle(
                                color: style.textColor,
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              widget.message,
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: style.textColor.withOpacity(0.82),
                                fontSize: 13.5,
                                fontWeight: FontWeight.w500,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        visualDensity: VisualDensity.compact,
                        onPressed: dismiss,
                        icon: Icon(
                          Icons.close_rounded,
                          color: style.textColor.withOpacity(0.62),
                          size: 21,
                        ),
                      ),
                    ],
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

class _ResultStyle {
  final String title;
  final IconData icon;
  final Color color;
  final Color backgroundColor;
  final Color textColor;

  const _ResultStyle({
    required this.title,
    required this.icon,
    required this.color,
    required this.backgroundColor,
    required this.textColor,
  });

  factory _ResultStyle.fromType(AppResultType type) {
    switch (type) {
      case AppResultType.success:
        return const _ResultStyle(
          title: 'Successful',
          icon: Icons.check_rounded,
          color: Color(0xFF16A34A),
          backgroundColor: Color(0xFFF0FDF4),
          textColor: Color(0xFF14532D),
        );
      case AppResultType.error:
        return const _ResultStyle(
          title: 'Unsuccessful',
          icon: Icons.close_rounded,
          color: Color(0xFFDC2626),
          backgroundColor: Color(0xFFFEF2F2),
          textColor: Color(0xFF7F1D1D),
        );
      case AppResultType.warning:
        return const _ResultStyle(
          title: 'Attention',
          icon: Icons.warning_amber_rounded,
          color: Color(0xFFF59E0B),
          backgroundColor: Color(0xFFFFFBEB),
          textColor: Color(0xFF78350F),
        );
      case AppResultType.info:
        return const _ResultStyle(
          title: 'Information',
          icon: Icons.info_outline_rounded,
          color: Color(0xFF339BFF),
          backgroundColor: Color(0xFFEFF6FF),
          textColor: Color(0xFF1E3A8A),
        );
    }
  }
}
