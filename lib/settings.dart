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
  static const _keyDefaultFormat = 'default_format';
  static const _keyPreferredVideoQuality = 'preferred_video_quality';
  static const _keyAppExe = 'app_exe';
  static const _keyAutoDownloadOnClick = 'auto_download_on_click';
  static const _keyLanguage = 'app_language';
  static const _keyFolderHistory = 'folder_history';
  static const _keyDownloadHistory = 'download_history_all';

  /// Zelfde map als shared_preferences op Windows: Roaming\com.example\Downloader
  static Future<Directory> appDataDir() async {
    if (Platform.isWindows) {
      final roaming = Platform.environment['APPDATA'];
      if (roaming != null && roaming.isNotEmpty) {
        final dir = Directory(p.join(roaming, 'com.example', 'Downloader'));
        await dir.create(recursive: true);
        return dir;
      }
    }
    return getApplicationSupportDirectory();
  }

  static Future<File> extensionInboxFile() async {
    final dir = await appDataDir();
    return File(p.join(dir.path, 'extension_inbox.json'));
  }

  static Future<String> getDownloadDir() async {
    final prefs = await SharedPreferences.getInstance();
    var saved = prefs.getString(_keyDownloadDir);
    if (saved == null || saved.isEmpty) {
      // Migreer vanaf oude lowercase prefs-map (com.example\downoader).
      saved = await _readLegacyDownloadDir();
      if (saved != null && saved.isNotEmpty) {
        await prefs.setString(_keyDownloadDir, saved);
        return saved;
      }
    }
    if (saved != null && saved.isNotEmpty) return saved;
    if (Platform.isAndroid) {
      final dir = await getExternalStorageDirectory();
      return p.join(dir!.path, 'Download', 'Downoader');
    }
    final userProfile = Platform.environment['USERPROFILE'] ?? 'C:\\';
    return '$userProfile\\Downloads';
  }

  static Future<String?> _readLegacyDownloadDir() async {
    if (!Platform.isWindows) return null;
    final roaming = Platform.environment['APPDATA'];
    if (roaming == null) return null;
    final file = File(p.join(roaming, 'com.example', 'downoader', 'shared_preferences.json'));
    if (!await file.exists()) return null;
    try {
      final data = jsonDecode(await file.readAsString());
      if (data is Map && data['flutter.download_dir'] is String) {
        final v = data['flutter.download_dir'] as String;
        if (v.isNotEmpty) return v;
      }
    } catch (_) {}
    return null;
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

  static Future<OutputFormat> getDefaultFormat() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyDefaultFormat);
    return OutputFormat.values.firstWhere(
      (f) => f.name == raw,
      orElse: () => OutputFormat.mp4,
    );
  }

  static Future<void> setDefaultFormat(OutputFormat format) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDefaultFormat, format.name);
  }

  static Future<PreferredVideoQuality> getPreferredVideoQuality() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyPreferredVideoQuality);
    return PreferredVideoQuality.values.firstWhere(
      (q) => q.name == raw,
      orElse: () => PreferredVideoQuality.p1080,
    );
  }

  static Future<void> setPreferredVideoQuality(PreferredVideoQuality q) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyPreferredVideoQuality, q.name);
  }

  static Future<void> setAppExePath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAppExe, path);
  }

  /// Of het icoon van de browser-extentie meteen moet downloaden (met de
  /// exe-instellingen) i.p.v. eerst de popup te openen. Staat standaard uit
  /// bij een verse installatie.
  static Future<bool> getAutoDownloadOnClick() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyAutoDownloadOnClick) ?? false;
  }

  static Future<void> setAutoDownloadOnClick(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAutoDownloadOnClick, value);
  }

  static Future<String?> getAppExePath() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_keyAppExe);
    if (saved == null || saved.isEmpty) return null;
    return saved;
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

  static Future<AppLanguage> getLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyLanguage);
    return AppLanguage.values.firstWhere(
      (l) => l.name == raw,
      orElse: () => AppLanguage.nl,
    );
  }

  static Future<void> setLanguage(AppLanguage language) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLanguage, language.name);
  }

  /// Meest recente map eerst. Gebruikt voor de mappen-geschiedenis in de
  /// instellingen (niet te verwarren met de "laatst gebruikte map"-instelling).
  static Future<List<String>> getFolderHistory() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_keyFolderHistory) ?? [];
  }

  static Future<void> addFolderHistory(String dir) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_keyFolderHistory) ?? [];
    list.remove(dir);
    list.insert(0, dir);
    if (list.length > 25) list.removeRange(25, list.length);
    await prefs.setStringList(_keyFolderHistory, list);
  }

  static Future<void> removeFolderHistory(String dir) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_keyFolderHistory) ?? [];
    list.remove(dir);
    await prefs.setStringList(_keyFolderHistory, list);
  }

  /// Alle ooit gedownloade bestanden (append-only, niet opgeschoond wanneer
  /// een bestand verdwijnt) zodat de mappen-geschiedenis kan tonen welke
  /// bestanden nog aanwezig, verwijderd of mogelijk verplaatst zijn.
  static Future<List<DownloadedItem>> getDownloadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyDownloadHistory);
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

  static Future<void> addDownloadHistoryItem(DownloadedItem item) async {
    final prefs = await SharedPreferences.getInstance();
    final items = await getDownloadHistory();
    items.removeWhere((i) => i.path == item.path);
    items.insert(0, item);
    if (items.length > 1000) items.removeRange(1000, items.length);
    await prefs.setString(
      _keyDownloadHistory,
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

  /// Inbox van de browser-extentie: een wachtrij van pending opdrachten
  /// (JSON-array, niet één enkel slot) — de extentie start bij elke
  /// popup-actie een nieuw host-proces, dus twee snel-na-elkaar geschreven
  /// jobs (bv. settings opslaan + meteen downloaden) zouden elkaar anders
  /// kunnen overschrijven voordat deze poller ze leest. Haalt en verwijdert
  /// steeds alleen de oudste job, de rest blijft staan voor de volgende poll.
  static Future<Map<String, dynamic>?> takeExtensionInbox() async {
    if (!Platform.isWindows) return null;
    final file = await extensionInboxFile();
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      final jobs = <dynamic>[];
      if (decoded is List) {
        jobs.addAll(decoded);
      } else if (decoded is Map) {
        jobs.add(decoded);
      }
      if (jobs.isEmpty) {
        await file.delete();
        return null;
      }
      final first = jobs.removeAt(0);
      if (jobs.isEmpty) {
        await file.delete();
      } else {
        await file.writeAsString(jsonEncode(jobs));
      }
      if (first is Map<String, dynamic>) return first;
      if (first is Map) return first.cast<String, dynamic>();
    } catch (_) {
      try {
        await file.delete();
      } catch (_) {}
    }
    return null;
  }
}
