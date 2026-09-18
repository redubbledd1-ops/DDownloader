import 'dart:io';

import 'package:flutter/services.dart';

/// Windows: voorkomt dat UI-updates (extentie-downloads) de app naar voren trekken.
class WindowBridge {
  static const _channel = MethodChannel('downoader/window');

  static Future<bool> isActive() async {
    if (!Platform.isWindows) return true;
    try {
      final v = await _channel.invokeMethod<bool>('isActive');
      return v ?? true;
    } catch (_) {
      return true;
    }
  }

  static Future<void> beginBackgroundUpdate() async {
    if (!Platform.isWindows) return;
    try {
      await _channel.invokeMethod<void>('beginBackgroundUpdate');
    } catch (_) {}
  }

  static Future<void> endBackgroundUpdate() async {
    if (!Platform.isWindows) return;
    try {
      await _channel.invokeMethod<void>('endBackgroundUpdate');
    } catch (_) {}
  }

  /// Voert [fn] uit zonder de app te activeren als die niet al op de voorgrond is.
  static Future<T> withoutStealingFocus<T>(Future<T> Function() fn) async {
    if (!Platform.isWindows) return fn();
    final active = await isActive();
    if (active) return fn();
    await beginBackgroundUpdate();
    try {
      return await fn();
    } finally {
      await endBackgroundUpdate();
    }
  }
}
