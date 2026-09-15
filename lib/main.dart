import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'models.dart';
import 'settings.dart';
import 'theme.dart';
import 'ytdlp_service.dart';

String? _argValue(List<String> args, String name) {
  final prefix = '--$name=';
  for (final a in args) {
    if (a.startsWith(prefix)) return a.substring(prefix.length);
  }
  final i = args.indexOf('--$name');
  if (i >= 0 && i + 1 < args.length) return args[i + 1];
  return null;
}

void main(List<String> args) {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isAndroid) {
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }
  runApp(
    DownoaderApp(
      initialUrl: _argValue(args, 'url'),
      initialFormat: _argValue(args, 'format'),
      initialFormatId: _argValue(args, 'formatId'),
    ),
  );
}

class DownoaderApp extends StatefulWidget {
  final String? initialUrl;
  final String? initialFormat;
  final String? initialFormatId;

  const DownoaderApp({
    super.key,
    this.initialUrl,
    this.initialFormat,
    this.initialFormatId,
  });

  @override
  State<DownoaderApp> createState() => _DownoaderAppState();
}

class _DownoaderAppState extends State<DownoaderApp> {
  ThemeMode _themeMode = ThemeMode.dark;

  @override
  void initState() {
    super.initState();
    _loadDarkMode();
    if (Platform.isWindows) {
      Settings.setAppExePath(Platform.resolvedExecutable);
    }
  }

  Future<void> _loadDarkMode() async {
    final dark = await Settings.getDarkMode();
    setState(() => _themeMode = dark ? ThemeMode.dark : ThemeMode.light);
  }

  void _toggleDarkMode(bool dark) {
    setState(() => _themeMode = dark ? ThemeMode.dark : ThemeMode.light);
    Settings.setDarkMode(dark);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Downloader',
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      themeMode: _themeMode,
      home: HomePage(
        isDarkMode: _themeMode == ThemeMode.dark,
        onToggleDarkMode: _toggleDarkMode,
        initialUrl: widget.initialUrl,
        initialFormat: widget.initialFormat,
        initialFormatId: widget.initialFormatId,
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  final bool isDarkMode;
  final ValueChanged<bool> onToggleDarkMode;
  final String? initialUrl;
  final String? initialFormat;
  final String? initialFormatId;

  const HomePage({
    super.key,
    required this.isDarkMode,
    required this.onToggleDarkMode,
    this.initialUrl,
    this.initialFormat,
    this.initialFormatId,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _urlController = TextEditingController();
  final _service = YtDlpService();

  OutputFormat _format = OutputFormat.mp4;
  PreferredVideoQuality _videoQuality = PreferredVideoQuality.p1080;
  bool _autoDownloadOnClick = false;
  PlaylistMode _playlistMode = PlaylistMode.ask;
  String _downloadDir = '';
  bool _busy = false;
  double _progress = 0;
  String _status = '';
  final List<DownloadedItem> _downloaded = [];

  final _searchController = TextEditingController();
  String _searchQuery = '';
  FileFilter _fileFilter = FileFilter.all;

  final List<String> _logs = [];
  final _logScrollController = ScrollController();
  bool _showLogs = false;
  Timer? _inboxTimer;
  String? _pendingFormatId;

  void _addLog(String message) {
    setState(() {
      _logs.add(message);
      if (_logs.length > 5000) _logs.removeAt(0);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScrollController.hasClients) {
        _logScrollController.jumpTo(
          _logScrollController.position.maxScrollExtent,
        );
      }
    });
  }

  IconData get _playlistModeIcon {
    switch (_playlistMode) {
      case PlaylistMode.playlist:
        return Icons.playlist_play;
      case PlaylistMode.single:
        return Icons.filter_1;
      case PlaylistMode.ask:
        return Icons.help_outline;
    }
  }

  String get _playlistModeTooltip {
    switch (_playlistMode) {
      case PlaylistMode.playlist:
        return 'Playlist-modus: altijd hele playlist downloaden';
      case PlaylistMode.single:
        return 'Playlist-modus: altijd maar 1 bestand downloaden';
      case PlaylistMode.ask:
        return 'Playlist-modus: elke keer vragen';
    }
  }

  void _cyclePlaylistMode() {
    const order = [
      PlaylistMode.ask,
      PlaylistMode.playlist,
      PlaylistMode.single,
    ];
    final next = order[(order.indexOf(_playlistMode) + 1) % order.length];
    setState(() => _playlistMode = next);
    Settings.setPlaylistMode(next);
  }

  List<DownloadedItem> get _filteredDownloaded {
    return _downloaded.where((item) {
      if (_fileFilter == FileFilter.video && item.format != OutputFormat.mp4)
        return false;
      if (_fileFilter == FileFilter.audio && item.format != OutputFormat.mp3)
        return false;
      if (_searchQuery.isNotEmpty &&
          !item.fileName.toLowerCase().contains(_searchQuery.toLowerCase())) {
        return false;
      }
      return true;
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _inboxTimer?.cancel();
    _urlController.dispose();
    _searchController.dispose();
    _logScrollController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await Future.wait([
      _loadDir(),
      _loadDownloaded(),
      _loadPlaylistMode(),
      _loadFormat(),
      _loadVideoQuality(),
      _loadAutoDownloadOnClick(),
    ]);
    if (widget.initialFormat != null) {
      final f = OutputFormat.values.where((e) => e.name == widget.initialFormat);
      if (f.isNotEmpty) {
        setState(() => _format = f.first);
        await Settings.setDefaultFormat(f.first);
      }
    }
    if (widget.initialFormatId != null && widget.initialFormatId!.isNotEmpty) {
      _pendingFormatId = widget.initialFormatId;
    }
    if (widget.initialUrl != null && widget.initialUrl!.isNotEmpty) {
      _urlController.text = widget.initialUrl!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startDownload(formatIdOverride: _pendingFormatId);
      });
    }
    if (Platform.isWindows) {
      _inboxTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        _pollExtensionInbox();
      });
    }
  }

  Future<void> _pollExtensionInbox() async {
    if (_busy || !mounted) return;
    final job = await Settings.takeExtensionInbox();
    if (job == null) return;

    // Extentie downloadde rechtstreeks via de native host (buiten de app
    // om) — alleen de app-lijst bijwerken, niets opnieuw downloaden.
    if (job['type']?.toString() == 'downloaded') {
      final path = job['path']?.toString() ?? '';
      if (path.isEmpty) return;
      final formatName = job['format']?.toString();
      final formatMatch = OutputFormat.values.where(
        (e) => e.name == formatName,
      );
      final format = formatMatch.isNotEmpty
          ? formatMatch.first
          : OutputFormat.mp4;
      setState(() {
        _downloaded.insert(
          0,
          DownloadedItem(
            path: path,
            isPlaylist: job['isPlaylist'] == true,
            format: format,
          ),
        );
      });
      await Settings.setDownloadedItems(_downloaded);
      _addLog('Extentie: bestand gedownload ($path)');
      return;
    }

    final patch = job['settings'];
    if (patch is Map) {
      final downloadDir = patch['downloadDir']?.toString();
      if (downloadDir != null && downloadDir.isNotEmpty) {
        await Settings.setDownloadDir(downloadDir);
        setState(() => _downloadDir = downloadDir);
      }
      final playlistMode = patch['playlistMode']?.toString();
      if (playlistMode != null) {
        final mode = PlaylistMode.values.where((e) => e.name == playlistMode);
        if (mode.isNotEmpty) {
          await Settings.setPlaylistMode(mode.first);
          setState(() => _playlistMode = mode.first);
        }
      }
      final formatName = patch['format']?.toString();
      if (formatName != null) {
        final match = OutputFormat.values.where((e) => e.name == formatName);
        if (match.isNotEmpty) {
          await Settings.setDefaultFormat(match.first);
          setState(() => _format = match.first);
        }
      }
      final qualityName = patch['preferredVideoQuality']?.toString();
      if (qualityName != null) {
        final match = PreferredVideoQuality.values.where(
          (e) => e.name == qualityName,
        );
        if (match.isNotEmpty) {
          await Settings.setPreferredVideoQuality(match.first);
          setState(() => _videoQuality = match.first);
        }
      }
      final autoDownload = patch['autoDownloadOnClick'];
      if (autoDownload is bool) {
        await Settings.setAutoDownloadOnClick(autoDownload);
        setState(() => _autoDownloadOnClick = autoDownload);
      }
    }

    // Alleen settings (van "Instellingen opslaan") — geen download.
    if (job['type']?.toString() == 'settings') {
      _addLog('Extentie: app-instellingen bijgewerkt');
      return;
    }

    final url = job['url']?.toString() ?? '';
    if (url.isEmpty) return;

    final formatName = job['format']?.toString();
    final formatId = job['formatId']?.toString();
    setState(() {
      _urlController.text = url;
      if (formatName != null) {
        final match = OutputFormat.values.where((e) => e.name == formatName);
        if (match.isNotEmpty) _format = match.first;
      }
    });
    if (formatName != null) {
      final match = OutputFormat.values.where((e) => e.name == formatName);
      if (match.isNotEmpty) await Settings.setDefaultFormat(match.first);
    }
    _addLog('Extentie: download gestart voor $url');
    await _startDownload(formatIdOverride: formatId);
  }

  Future<void> _loadFormat() async {
    final format = await Settings.getDefaultFormat();
    setState(() => _format = format);
  }

  Future<void> _loadVideoQuality() async {
    final q = await Settings.getPreferredVideoQuality();
    setState(() => _videoQuality = q);
  }

  Future<void> _loadAutoDownloadOnClick() async {
    final value = await Settings.getAutoDownloadOnClick();
    setState(() => _autoDownloadOnClick = value);
  }

  Future<void> _loadPlaylistMode() async {
    final mode = await Settings.getPlaylistMode();
    setState(() => _playlistMode = mode);
  }

  Future<void> _loadDir() async {
    final dir = await Settings.getDownloadDir();
    setState(() => _downloadDir = dir);
  }

  Future<void> _loadDownloaded() async {
    final items = await Settings.getDownloadedItems();
    final existing = items.where((i) => File(i.path).existsSync()).toList();
    setState(() {
      _downloaded.clear();
      _downloaded.addAll(existing);
    });
    if (existing.length != items.length) {
      await Settings.setDownloadedItems(existing);
    }
  }

  Future<void> _pickDir() async {
    final selected = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Kies downloadmap',
      initialDirectory: _downloadDir.isEmpty ? null : _downloadDir,
    );
    if (selected != null) {
      await Settings.setDownloadDir(selected);
      setState(() => _downloadDir = selected);
    }
  }

  Future<void> _startDownload({String? formatIdOverride}) async {
    if (_busy) return;

    var url = _urlController.text.trim();
    if (url.isEmpty) {
      final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
      final clipboardText = clipboard?.text?.trim() ?? '';
      if (clipboardText.isNotEmpty) {
        url = clipboardText;
        _urlController.text = url;
      }
    }
    if (url.isEmpty) return;

    if (!await _service.exeExists()) {
      _showError(_service.unavailableMessage);
      return;
    }

    setState(() => _busy = true);
    String? ffmpegDir;
    try {
      ffmpegDir = await _service.ensureFfmpeg(onLog: _addLog);
    } catch (e) {
      setState(() => _busy = false);
      _addLog('FOUT: $e');
      _showError('Kon ffmpeg niet installeren: $e');
      return;
    }

    await Directory(_downloadDir).create(recursive: true);

    setState(() {
      _busy = true;
      _progress = 0;
      _status = 'Controleren of het een playlist is...';
    });
    _addLog('----- Download gestart: $url -----');

    bool isPlaylist = false;
    PlaylistProbeResult probe;
    try {
      probe = await _service.probePlaylist(url);
      if (probe.isPlaylist && probe.entryCount > 1) {
        switch (_playlistMode) {
          case PlaylistMode.playlist:
            isPlaylist = true;
          case PlaylistMode.single:
            isPlaylist = false;
          case PlaylistMode.ask:
            final choice = await _askPlaylistChoice();
            if (choice == null) {
              setState(() {
                _busy = false;
                _status = '';
              });
              return;
            }
            isPlaylist = choice;
        }
      }
    } catch (e) {
      setState(() {
        _busy = false;
        _status = '';
      });
      _addLog('FOUT: $e');
      _showError('Kon URL niet controleren: $e');
      return;
    }

    String? formatId = formatIdOverride;
    if (_format == OutputFormat.mp4 && formatId == null) {
      if (_videoQuality != PreferredVideoQuality.ask) {
        formatId = _videoQuality.formatSelector;
      } else {
        List<FormatInfo> formats;
        try {
          if (probe.isPlaylist) {
            setState(() => _status = 'Kwaliteiten ophalen...');
            formats = await _service.fetchFormats(url);
          } else {
            // Niet-playlist URL: de probe-call heeft de volledige info al
            // opgehaald, dus geen tweede yt-dlp-aanroep nodig.
            formats = _service.parseFormats(probe.data);
          }
        } catch (e) {
          setState(() {
            _busy = false;
            _status = '';
          });
          _addLog('FOUT: $e');
          _showError('Kon kwaliteiten niet ophalen: $e');
          return;
        }
        if (formats.isEmpty) {
          setState(() {
            _busy = false;
            _status = '';
          });
          _showError('Geen video-formats gevonden voor deze URL.');
          return;
        }
        final chosen = await _askQuality(formats);
        if (chosen == null) {
          setState(() {
            _busy = false;
            _status = '';
          });
          return;
        }
        formatId = chosen.hasAudio
            ? chosen.formatId
            : '${chosen.formatId}+bestaudio/best';
      }
    }

    setState(() {
      _progress = 0;
      _status = 'Downloaden...';
    });

    bool firstFileSeen = false;
    try {
      await for (final event in _service.download(
        url: url,
        outputDir: _downloadDir,
        isPlaylist: isPlaylist,
        format: _format,
        formatId: formatId,
        ffmpegDir: ffmpegDir,
      )) {
        if (event is ProgressEvent) {
          setState(() => _progress = event.percent / 100);
        } else if (event is FileDownloadedEvent) {
          if (!isPlaylist || !firstFileSeen) {
            firstFileSeen = true;
            setState(() {
              _downloaded.insert(
                0,
                DownloadedItem(
                  path: event.path,
                  isPlaylist: isPlaylist,
                  format: _format,
                ),
              );
            });
            Settings.setDownloadedItems(_downloaded);
          }
        } else if (event is StatusEvent) {
          setState(() => _status = event.message);
        } else if (event is LogEvent) {
          _addLog(event.message);
        } else if (event is DownloadDoneEvent) {
          if (!event.success) {
            _addLog('FOUT: ${event.error}');
            _showError('Download mislukt: ${event.error}');
          } else {
            _addLog('Download voltooid.');
          }
        }
      }
    } catch (e) {
      _addLog('FOUT: $e');
      _showError('Download mislukt: $e');
    }

    setState(() {
      _busy = false;
      _progress = 0;
      _status = '';
    });
  }

  Future<bool?> _askPlaylistChoice() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Playlist gedetecteerd'),
        content: const Text(
          'Deze URL bevat een playlist. Wat wil je downloaden?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Alleen deze video'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hele playlist'),
          ),
        ],
      ),
    );
  }

  Future<FormatInfo?> _askQuality(List<FormatInfo> formats) {
    return showDialog<FormatInfo>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kies kwaliteit'),
        content: SizedBox(
          width: 360,
          height: 400,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: formats.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final f = formats[i];
              return ListTile(
                title: Text(f.label),
                subtitle: Text(
                  f.hasAudio
                      ? 'video + audio'
                      : 'video only (audio wordt toegevoegd)',
                ),
                onTap: () => Navigator.pop(ctx, f),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuleren'),
          ),
        ],
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red.shade700),
    );
  }

  void _showInfo(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _saveLogs() async {
    if (_logs.isEmpty) {
      _showError('Geen logs om op te slaan.');
      return;
    }
    try {
      final dir = _downloadDir.isNotEmpty
          ? _downloadDir
          : (await getTemporaryDirectory()).path;
      await Directory(dir).create(recursive: true);
      final fileName =
          'downloader_log_${DateTime.now().millisecondsSinceEpoch}.txt';
      final file = File('$dir${Platform.pathSeparator}$fileName');
      await file.writeAsString(_logs.join('\n'));
      _showInfo('Log opgeslagen: ${file.path}');
      await _service.openFolder(file.path);
    } catch (e) {
      _showError('Kon log niet opslaan: $e');
    }
  }

  Future<void> _openFile(String path) async {
    try {
      await _service.openFile(path);
    } catch (e) {
      _showError('Kon bestand niet openen: $e');
    }
  }

  Future<void> _openItemFolder(String path) async {
    try {
      await _service.openFolder(path);
    } catch (e) {
      _showError('Kon map niet openen: $e');
    }
  }

  Future<void> _openDownloadFolder() async {
    if (_downloadDir.isEmpty || Platform.isAndroid) return;
    try {
      await Process.start('explorer.exe', [
        _downloadDir,
      ], mode: ProcessStartMode.detached);
    } catch (e) {
      _showError('Kon map niet openen: $e');
    }
  }

  Future<bool> _confirmDialog(String title, String message) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuleren'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Verwijderen'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _deleteItem(DownloadedItem item) async {
    final confirmed = await _confirmDialog(
      'Bestand verwijderen?',
      'Weet je zeker dat je "${item.fileName}" wilt verwijderen? Dit kan niet ongedaan worden gemaakt.',
    );
    if (!confirmed) return;
    try {
      final file = File(item.path);
      if (await file.exists()) await file.delete();
    } catch (e) {
      _showError('Kon bestand niet verwijderen: $e');
      return;
    }
    setState(() => _downloaded.remove(item));
    await Settings.setDownloadedItems(_downloaded);
    _addLog('Verwijderd: ${item.fileName}');
  }

  Future<void> _deleteAllItems() async {
    if (_downloaded.isEmpty) return;
    final confirmed = await _confirmDialog(
      'Alle bestanden verwijderen?',
      'Weet je zeker dat je alle ${_downloaded.length} gedownloade bestanden wilt verwijderen? Dit kan niet ongedaan worden gemaakt.',
    );
    if (!confirmed) return;
    final items = List<DownloadedItem>.from(_downloaded);
    var failed = 0;
    for (final item in items) {
      try {
        final file = File(item.path);
        if (await file.exists()) await file.delete();
      } catch (_) {
        failed++;
      }
    }
    setState(() => _downloaded.clear());
    await Settings.setDownloadedItems(_downloaded);
    _addLog('Alle bestanden verwijderd${failed > 0 ? ' ($failed mislukt)' : ''}.');
    if (failed > 0) {
      _showError('$failed bestand(en) konden niet verwijderd worden.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const _AppBarTitle(),
        actions: [
          IconButton(
            icon: Icon(_playlistModeIcon),
            tooltip: _playlistModeTooltip,
            onPressed: _cyclePlaylistMode,
          ),
          IconButton(
            icon: Icon(_showLogs ? Icons.terminal : Icons.terminal_outlined),
            tooltip: 'Logs',
            onPressed: () => setState(() => _showLogs = !_showLogs),
          ),
          IconButton(
            icon: const Icon(Icons.download_for_offline_outlined),
            tooltip: 'Log opslaan als tekstbestand',
            onPressed: _saveLogs,
          ),
          if (!Platform.isAndroid)
            IconButton(
              icon: const Icon(Icons.folder_open),
              tooltip: 'Open downloadmap',
              onPressed: _downloadDir.isEmpty ? null : _openDownloadFolder,
            ),
          IconButton(
            icon: Icon(
              widget.isDarkMode ? Icons.dark_mode : Icons.light_mode,
            ),
            tooltip: widget.isDarkMode ? 'Donkere modus' : 'Lichte modus',
            onPressed: () => widget.onToggleDarkMode(!widget.isDarkMode),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_showLogs) ...[
                Container(
                  height: 220,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.all(8),
                  child: _logs.isEmpty
                      ? const Center(
                          child: Text(
                            'Nog geen logs',
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      : Scrollbar(
                          controller: _logScrollController,
                          child: ListView.builder(
                            controller: _logScrollController,
                            itemCount: _logs.length,
                            itemBuilder: (_, i) => Text(
                              _logs[i],
                              style: const TextStyle(
                                color: Colors.greenAccent,
                                fontFamily: 'monospace',
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ),
                ),
                const SizedBox(height: 12),
              ],
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _urlController,
                      decoration: const InputDecoration(
                        labelText: 'Video of playlist URL',
                        border: OutlineInputBorder(),
                      ),
                      enabled: !_busy,
                      onSubmitted: (_) => _startDownload(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: _busy ? null : _startDownload,
                    icon: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download),
                    label: const Text('Download'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Formaat: '),
                  const SizedBox(width: 8),
                  SegmentedButton<OutputFormat>(
                    segments: const [
                      ButtonSegment(
                        value: OutputFormat.mp4,
                        label: Text('MP4'),
                        icon: Icon(Icons.movie),
                      ),
                      ButtonSegment(
                        value: OutputFormat.mp3,
                        label: Text('MP3'),
                        icon: Icon(Icons.audiotrack),
                      ),
                    ],
                    selected: {_format},
                    onSelectionChanged: _busy
                        ? null
                        : (s) {
                            final next = s.first;
                            setState(() => _format = next);
                            Settings.setDefaultFormat(next);
                          },
                  ),
                ],
              ),
              if (_format == OutputFormat.mp4) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text('MP4-kwaliteit: '),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<PreferredVideoQuality>(
                        value: _videoQuality,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                        items: PreferredVideoQuality.values
                            .map(
                              (q) => DropdownMenuItem(
                                value: q,
                                child: Text(q.label),
                              ),
                            )
                            .toList(),
                        onChanged: _busy
                            ? null
                            : (q) {
                                if (q == null) return;
                                setState(() => _videoQuality = q);
                                Settings.setPreferredVideoQuality(q);
                              },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _videoQuality == PreferredVideoQuality.ask
                      ? 'Bij downloaden eerst kwaliteit kiezen.'
                      : 'Direct downloaden (app + extentie) gebruikt ${_videoQuality.label}.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              if (Platform.isWindows) ...[
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Extentie-icoon downloadt meteen'),
                  subtitle: Text(
                    _autoDownloadOnClick
                        ? 'Klik op het extentie-icoon start direct een download (app-instellingen).'
                        : 'Klik op het extentie-icoon opent eerst het venster.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  value: _autoDownloadOnClick,
                  onChanged: (value) {
                    setState(() => _autoDownloadOnClick = value);
                    Settings.setAutoDownloadOnClick(value);
                  },
                ),
              ],
              const SizedBox(height: 16),
              if (_busy) ...[
                LinearProgressIndicator(
                  value: _progress > 0 ? _progress : null,
                ),
                const SizedBox(height: 6),
                Text(_status, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 16),
              ],
              const Divider(),
              Row(
                children: [
                  const Expanded(child: Text('Gedownloade bestanden')),
                  IconButton(
                    icon: const Icon(Icons.delete_sweep_outlined),
                    tooltip: 'Alle bestanden verwijderen',
                    onPressed: _downloaded.isEmpty ? null : _deleteAllItems,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  hintText: 'Zoeken in bestanden...',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _searchQuery = v),
              ),
              const SizedBox(height: 8),
              SegmentedButton<FileFilter>(
                segments: const [
                  ButtonSegment(value: FileFilter.all, label: Text('Alles')),
                  ButtonSegment(
                    value: FileFilter.video,
                    label: Text("Video's"),
                    icon: Icon(Icons.movie),
                  ),
                  ButtonSegment(
                    value: FileFilter.audio,
                    label: Text('Audio'),
                    icon: Icon(Icons.audiotrack),
                  ),
                ],
                selected: {_fileFilter},
                onSelectionChanged: (s) =>
                    setState(() => _fileFilter = s.first),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Builder(
                  builder: (context) {
                    final items = _filteredDownloaded;
                    if (_downloaded.isEmpty) {
                      return const Center(
                        child: Text(
                          'Nog niets gedownload',
                          style: TextStyle(color: Colors.grey),
                        ),
                      );
                    }
                    if (items.isEmpty) {
                      return const Center(
                        child: Text(
                          'Geen resultaten',
                          style: TextStyle(color: Colors.grey),
                        ),
                      );
                    }
                    return ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (_, i) {
                        final item = items[i];
                        return ListTile(
                          leading: Icon(
                            item.isPlaylist
                                ? Icons.playlist_play
                                : (item.format == OutputFormat.mp3
                                      ? Icons.audiotrack
                                      : Icons.movie_outlined),
                          ),
                          title: Text(item.fileName),
                          subtitle: item.isPlaylist
                              ? const Text(
                                  'Onderdeel van een playlist-download',
                                )
                              : null,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.folder_open, size: 18),
                                tooltip: 'Open map',
                                onPressed: () => _openItemFolder(item.path),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, size: 18),
                                tooltip: 'Verwijderen',
                                onPressed: () => _deleteItem(item),
                              ),
                            ],
                          ),
                          onTap: () => _openFile(item.path),
                        );
                      },
                    );
                  },
                ),
              ),
              const Divider(),
              Row(
                children: [
                  const Icon(Icons.folder_outlined),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _downloadDir.isEmpty
                          ? 'Downloadmap laden...'
                          : _downloadDir,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton(
                    onPressed: _busy ? null : _pickDir,
                    child: const Text('Wijzig...'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppBarTitle extends StatelessWidget {
  const _AppBarTitle();

  static const _iconAsset = 'Download.icoon.png';
  // Ruimte voor icoon (28) + gap (10) + "Downloader" (~95) ≈ 135.
  static const _minWidthForText = 140.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final showText =
            !Platform.isAndroid && constraints.maxWidth >= _minWidthForText;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.asset(
                _iconAsset,
                width: 28,
                height: 28,
                fit: BoxFit.cover,
              ),
            ),
            if (showText) ...[
              const SizedBox(width: 10),
              const Text('Downloader'),
            ],
          ],
        );
      },
    );
  }
}
