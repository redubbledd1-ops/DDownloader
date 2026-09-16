import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'l10n.dart';
import 'models.dart';
import 'settings.dart';

enum _FileStatus { present, deleted, moved }

class FolderHistoryPage extends StatefulWidget {
  final AppLanguage language;
  final String currentDir;
  final ValueChanged<String> onSelectFolder;

  const FolderHistoryPage({
    super.key,
    required this.language,
    required this.currentDir,
    required this.onSelectFolder,
  });

  @override
  State<FolderHistoryPage> createState() => _FolderHistoryPageState();
}

class _FolderHistoryPageState extends State<FolderHistoryPage> {
  L10n get t => L10n(widget.language);

  bool _loading = true;
  List<String> _folders = [];
  List<DownloadedItem> _history = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final folders = await Settings.getFolderHistory();
    final history = await Settings.getDownloadHistory();
    final dirs = <String>{...folders};
    for (final item in history) {
      dirs.add(p.dirname(item.path));
    }
    if (widget.currentDir.isNotEmpty) dirs.add(widget.currentDir);
    setState(() {
      _folders = dirs.toList();
      _history = history;
      _loading = false;
    });
  }

  List<DownloadedItem> _itemsIn(String dir) {
    return _history.where((i) => p.dirname(i.path) == dir).toList();
  }

  _FileStatus _statusOf(DownloadedItem item) {
    if (File(item.path).existsSync()) return _FileStatus.present;
    final name = item.fileName;
    final movedElsewhere = _history.any(
      (other) =>
          other.path != item.path &&
          other.fileName == name &&
          File(other.path).existsSync(),
    );
    return movedElsewhere ? _FileStatus.moved : _FileStatus.deleted;
  }

  Future<void> _removeFolder(String dir) async {
    await Settings.removeFolderHistory(dir);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(t.folderHistoryTitle)),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _folders.isEmpty
            ? Center(
                child: Text(
                  t.folderHistoryEmpty,
                  style: const TextStyle(color: Colors.grey),
                ),
              )
            : ListView.builder(
                itemCount: _folders.length,
                itemBuilder: (context, i) {
                  final dir = _folders[i];
                  final items = _itemsIn(dir);
                  final isCurrent = dir == widget.currentDir;
                  return ExpansionTile(
                    leading: Icon(
                      Icons.folder,
                      color: isCurrent
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                    title: Text(dir, overflow: TextOverflow.ellipsis),
                    subtitle: Text(t.filesInFolder(items.length)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!isCurrent)
                          IconButton(
                            icon: const Icon(Icons.check_circle_outline),
                            tooltip: t.useThisFolder,
                            onPressed: () => widget.onSelectFolder(dir),
                          ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: t.removeFromHistory,
                          onPressed: () => _removeFolder(dir),
                        ),
                      ],
                    ),
                    children: items.isEmpty
                        ? [
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              child: Text(
                                t.folderHistoryEmpty,
                                style: const TextStyle(color: Colors.grey),
                              ),
                            ),
                          ]
                        : items.map((item) {
                            final status = _statusOf(item);
                            final (icon, color, label) = switch (status) {
                              _FileStatus.present => (
                                Icons.check_circle_outline,
                                Colors.green,
                                t.fileStatusPresent,
                              ),
                              _FileStatus.moved => (
                                Icons.drive_file_move_outline,
                                Colors.orange,
                                t.fileStatusMoved,
                              ),
                              _FileStatus.deleted => (
                                Icons.remove_circle_outline,
                                Colors.red,
                                t.fileStatusDeleted,
                              ),
                            };
                            return ListTile(
                              dense: true,
                              leading: Icon(icon, color: color, size: 20),
                              title: Text(
                                item.fileName,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: Text(
                                label,
                                style: TextStyle(color: color, fontSize: 12),
                              ),
                            );
                          }).toList(),
                  );
                },
              ),
      ),
    );
  }
}
