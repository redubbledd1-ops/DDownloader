import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

class Settings {
  static const _keyDownloadDir = 'download_dir';
  static const _keyDarkMode = 'dark_mode';
  static const _keyDownloaded = 'downloaded_items';
  static const _keyPlaylistMode = 'playlist_mode';

  static Future<String> getDownloadDir() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_keyDownloadDir);
    if (saved != null && saved.isNotEmpty) return saved;
    if (Platform.isAndroid) {
      final dir = await getExternalStorageDirectory();
      return p.join(dir!.path, 'Download', 'Downoader');
    }
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

  static Future<List<DownloadedItem>> getDownloadedItems() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyDownloaded);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .whereType<Map>()
          .map((m) => DownloadedItem.fromJson(m.cast<String, dynamic>()))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> setDownloadedItems(List<DownloadedItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _keyDownloaded,
      jsonEncode(items.map((i) => i.toJson()).toList()),
    );
  }

  static Future<PlaylistMode> getPlaylistMode() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyPlaylistMode);
    return PlaylistMode.values.firstWhere(
      (m) => m.name == raw,
      orElse: () => PlaylistMode.ask,
    );
  }

  static Future<void> setPlaylistMode(PlaylistMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyPlaylistMode, mode.name);
  }
}
