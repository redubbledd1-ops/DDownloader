import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'models.dart';
import 'settings.dart';
import 'theme.dart';
import 'ytdlp_service.dart';

void main() {
  runApp(const DownoaderApp());
}

class DownoaderApp extends StatefulWidget {
  const DownoaderApp({super.key});

  @override
  State<DownoaderApp> createState() => _DownoaderAppState();
}

class _DownoaderAppState extends State<DownoaderApp> {
  ThemeMode _themeMode = ThemeMode.dark;

  @override
  void initState() {
    super.initState();
    _loadDarkMode();
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
      title: 'Downoader',
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      themeMode: _themeMode,
      home: HomePage(
        isDarkMode: _themeMode == ThemeMode.dark,
        onToggleDarkMode: _toggleDarkMode,
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  final bool isDarkMode;
  final ValueChanged<bool> onToggleDarkMode;

  const HomePage({super.key, required this.isDarkMode, required this.onToggleDarkMode});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _urlController = TextEditingController();
  final _service = YtDlpService();

  OutputFormat _format = OutputFormat.mp4;
  String _downloadDir = '';
  bool _busy = false;
  double _progress = 0;
  String _status = '';
  final List<DownloadedItem> _downloaded = [];

  final _searchController = TextEditingController();
  String _searchQuery = '';
  FileFilter _fileFilter = FileFilter.all;

  List<DownloadedItem> get _filteredDownloaded {
    return _downloaded.where((item) {
      if (_fileFilter == FileFilter.video && item.format != OutputFormat.mp4) return false;
      if (_fileFilter == FileFilter.audio && item.format != OutputFormat.mp3) return false;
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
    _loadDir();
  }

  Future<void> _loadDir() async {
    final dir = await Settings.getDownloadDir();
    setState(() => _downloadDir = dir);
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

  Future<void> _startDownload() async {
    final url = _urlController.text.trim();
    if (url.isEmpty || _busy) return;

    if (!await _service.exeExists()) {
      _showError('yt-dlp.exe niet gevonden op $ytDlpPath');
      return;
    }

    setState(() {
      _busy = true;
      _progress = 0;
      _status = 'Controleren of het een playlist is...';
    });

    bool isPlaylist = false;
    try {
      final probe = await _service.probePlaylist(url);
      if (probe.isPlaylist && probe.entryCount > 1) {
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
    } catch (e) {
      setState(() {
        _busy = false;
        _status = '';
      });
      _showError('Kon URL niet controleren: $e');
      return;
    }

    String? formatId;
    if (_format == OutputFormat.mp4) {
      setState(() => _status = 'Kwaliteiten ophalen...');
      List<FormatInfo> formats;
      try {
        formats = await _service.fetchFormats(url);
      } catch (e) {
        setState(() {
          _busy = false;
          _status = '';
        });
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
      formatId = chosen.hasAudio ? chosen.formatId : '${chosen.formatId}+bestaudio/best';
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
      )) {
        if (event is ProgressEvent) {
          setState(() => _progress = event.percent / 100);
        } else if (event is FileDownloadedEvent) {
          if (!isPlaylist || !firstFileSeen) {
            firstFileSeen = true;
            setState(() {
              _downloaded.insert(
                0,
                DownloadedItem(path: event.path, isPlaylist: isPlaylist, format: _format),
              );
            });
          }
        } else if (event is StatusEvent) {
          setState(() => _status = event.message);
        } else if (event is DownloadDoneEvent) {
          if (!event.success) {
            _showError('Download mislukt: ${event.error}');
          }
        }
      }
    } catch (e) {
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
        content: const Text('Deze URL bevat een playlist. Wat wil je downloaden?'),
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
                subtitle: Text(f.hasAudio ? 'video + audio' : 'video only (audio wordt toegevoegd)'),
                onTap: () => Navigator.pop(ctx, f),
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuleren')),
        ],
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red.shade700),
    );
  }

  Future<void> _openFile(String path) async {
    try {
      await Process.start('explorer.exe', [path], mode: ProcessStartMode.detached);
    } catch (e) {
      _showError('Kon bestand niet openen: $e');
    }
  }

  Future<void> _openDownloadFolder() async {
    if (_downloadDir.isEmpty) return;
    try {
      await Process.start('explorer.exe', [_downloadDir], mode: ProcessStartMode.detached);
    } catch (e) {
      _showError('Kon map niet openen: $e');
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Downoader'),
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_open),
            tooltip: 'Open downloadmap',
            onPressed: _downloadDir.isEmpty ? null : _openDownloadFolder,
          ),
          const SizedBox(width: 4),
          Icon(widget.isDarkMode ? Icons.dark_mode : Icons.light_mode),
          Switch(
            value: widget.isDarkMode,
            onChanged: widget.onToggleDarkMode,
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
                    ButtonSegment(value: OutputFormat.mp4, label: Text('MP4'), icon: Icon(Icons.movie)),
                    ButtonSegment(value: OutputFormat.mp3, label: Text('MP3'), icon: Icon(Icons.audiotrack)),
                  ],
                  selected: {_format},
                  onSelectionChanged: _busy
                      ? null
                      : (s) => setState(() => _format = s.first),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_busy) ...[
              LinearProgressIndicator(value: _progress > 0 ? _progress : null),
              const SizedBox(height: 6),
              Text(_status, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 16),
            ],
            const Divider(),
            const Align(alignment: Alignment.centerLeft, child: Text('Gedownloade bestanden')),
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
                ButtonSegment(value: FileFilter.video, label: Text("Video's"), icon: Icon(Icons.movie)),
                ButtonSegment(value: FileFilter.audio, label: Text('Audio'), icon: Icon(Icons.audiotrack)),
              ],
              selected: {_fileFilter},
              onSelectionChanged: (s) => setState(() => _fileFilter = s.first),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Builder(builder: (context) {
                final items = _filteredDownloaded;
                if (_downloaded.isEmpty) {
                  return const Center(child: Text('Nog niets gedownload', style: TextStyle(color: Colors.grey)));
                }
                if (items.isEmpty) {
                  return const Center(child: Text('Geen resultaten', style: TextStyle(color: Colors.grey)));
                }
                return ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (_, i) {
                    final item = items[i];
                    return ListTile(
                      leading: Icon(
                        item.isPlaylist
                            ? Icons.playlist_play
                            : (item.format == OutputFormat.mp3 ? Icons.audiotrack : Icons.movie_outlined),
                      ),
                      title: Text(item.fileName),
                      subtitle: item.isPlaylist ? const Text('Onderdeel van een playlist-download') : null,
                      trailing: const Icon(Icons.open_in_new, size: 18),
                      onTap: () => _openFile(item.path),
                    );
                  },
                );
              }),
            ),
            const Divider(),
            Row(
              children: [
                const Icon(Icons.folder_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _downloadDir.isEmpty ? 'Downloadmap laden...' : _downloadDir,
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
    );
  }
}
