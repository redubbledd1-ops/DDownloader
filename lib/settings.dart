import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

class Settings {
  static const _keyDownloadDir = 'download_dir';
  static const _keyDarkMode = 'dark_mode';

  static Future<String> getDownloadDir() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_keyDownloadDir);
    if (saved != null && saved.isNotEmpty) return saved;
    final userProfile = Platform.environment['USERPROFILE'] ?? 'C:\\';
    return '$userProfile\\Downloads';
  }

  static Future<void> setDownloadDir(String dir) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDownloadDir, dir);
  }

  static Future<bool> getDarkMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyDarkMode) ?? true;
  }

  static Future<void> setDarkMode(bool dark) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyDarkMode, dark);
  }
}
