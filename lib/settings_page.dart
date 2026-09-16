import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'folder_history_page.dart';
import 'l10n.dart';
import 'models.dart';
import 'settings.dart';

class SettingsPage extends StatefulWidget {
  final bool isDarkMode;
  final ValueChanged<bool> onToggleDarkMode;
  final AppLanguage language;
  final ValueChanged<AppLanguage> onChangeLanguage;
  final String downloadDir;
  final ValueChanged<String> onChangeDownloadDir;
  final bool autoDownloadOnClick;
  final ValueChanged<bool> onChangeAutoDownloadOnClick;
  final bool showLogs;
  final ValueChanged<bool> onToggleShowLogs;
  final VoidCallback onSaveLogs;
  final List<String> logs;
  final Listenable logsTick;

  const SettingsPage({
    super.key,
    required this.isDarkMode,
    required this.onToggleDarkMode,
    required this.language,
    required this.onChangeLanguage,
    required this.downloadDir,
    required this.onChangeDownloadDir,
    required this.autoDownloadOnClick,
    required this.onChangeAutoDownloadOnClick,
    required this.showLogs,
    required this.onToggleShowLogs,
    required this.onSaveLogs,
    required this.logs,
    required this.logsTick,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late String _downloadDir = widget.downloadDir;
  final _logScrollController = ScrollController();

  @override
  void dispose() {
    _logScrollController.dispose();
    super.dispose();
  }

  L10n get t => L10n(widget.language);

  Future<void> _pickDir() async {
    final selected = await FilePicker.platform.getDirectoryPath(
      dialogTitle: t.changeFolderButton,
      initialDirectory: _downloadDir.isEmpty ? null : _downloadDir,
    );
    if (selected == null) return;
    await Settings.setDownloadDir(selected);
    await Settings.addFolderHistory(selected);
    setState(() => _downloadDir = selected);
    widget.onChangeDownloadDir(selected);
  }

  Future<void> _pickLanguage() async {
    final chosen = await showDialog<AppLanguage>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.selectLanguageTitle),
        content: SizedBox(
          width: 320,
          child: RadioGroup<AppLanguage>(
            groupValue: widget.language,
            onChanged: (lang) {
              if (lang != null) Navigator.pop(ctx, lang);
            },
            child: ListView(
              shrinkWrap: true,
              children: AppLanguage.values
                  .map(
                    (lang) => RadioListTile<AppLanguage>(
                      value: lang,
                      title: Text(lang.nativeName),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(t.cancel),
          ),
        ],
      ),
    );
    if (chosen != null) widget.onChangeLanguage(chosen);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(t.settingsTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            _SectionHeader(title: t.themeSection),
            SwitchListTile(
              title: Text(
                widget.isDarkMode ? t.darkModeLabel : t.lightModeLabel,
              ),
              secondary: Icon(
                widget.isDarkMode ? Icons.dark_mode : Icons.light_mode,
              ),
              value: widget.isDarkMode,
              onChanged: widget.onToggleDarkMode,
            ),
            _SectionHeader(title: t.languageSection),
            ListTile(
              leading: const Icon(Icons.language),
              title: Text(t.languageSection),
              subtitle: Text(widget.language.nativeName),
              onTap: _pickLanguage,
            ),
            _SectionHeader(title: t.folderSection),
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: Text(t.currentFolderLabel),
              subtitle: Text(
                _downloadDir.isEmpty ? t.loadingDownloadDir : _downloadDir,
              ),
              onTap: _pickDir,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _pickDir,
                      icon: const Icon(Icons.drive_file_move_outline),
                      label: Text(t.changeFolderButton),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.history),
              title: Text(t.folderHistoryButton),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => FolderHistoryPage(
                      language: widget.language,
                      currentDir: _downloadDir,
                      onSelectFolder: (dir) async {
                        await Settings.setDownloadDir(dir);
                        await Settings.addFolderHistory(dir);
                        setState(() => _downloadDir = dir);
                        widget.onChangeDownloadDir(dir);
                      },
                    ),
                  ),
                );
              },
            ),
            if (!Platform.isAndroid)
              ListTile(
                leading: const Icon(Icons.folder_open),
                title: Text(t.openDownloadFolderTooltip),
                onTap: _downloadDir.isEmpty
                    ? null
                    : () => Process.start('explorer.exe', [
                        _downloadDir,
                      ], mode: ProcessStartMode.detached),
              ),
            if (Platform.isWindows) ...[
              _SectionHeader(title: t.extensionSection),
              SwitchListTile(
                title: Text(t.extAutoDownloadTitle),
                subtitle: Text(
                  widget.autoDownloadOnClick
                      ? t.extAutoDownloadOnSubtitle
                      : t.extAutoDownloadOffSubtitle,
                ),
                value: widget.autoDownloadOnClick,
                onChanged: widget.onChangeAutoDownloadOnClick,
              ),
            ],
            _SectionHeader(title: t.logsTooltip),
            SwitchListTile(
              title: Text(t.showLogsLabel),
              subtitle: Text(t.showLogsSubtitle),
              value: widget.showLogs,
              onChanged: widget.onToggleShowLogs,
            ),
            if (widget.showLogs)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: ListenableBuilder(
                  listenable: widget.logsTick,
                  builder: (context, _) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (_logScrollController.hasClients) {
                        _logScrollController.jumpTo(
                          _logScrollController.position.maxScrollExtent,
                        );
                      }
                    });
                    return Container(
                      height: 220,
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.all(8),
                      child: widget.logs.isEmpty
                          ? Center(
                              child: Text(
                                t.noLogsYet,
                                style: const TextStyle(color: Colors.grey),
                              ),
                            )
                          : Scrollbar(
                              controller: _logScrollController,
                              child: ListView.builder(
                                controller: _logScrollController,
                                itemCount: widget.logs.length,
                                itemBuilder: (_, i) => Text(
                                  widget.logs[i],
                                  style: const TextStyle(
                                    color: Colors.greenAccent,
                                    fontFamily: 'monospace',
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ),
                    );
                  },
                ),
              ),
            ListTile(
              leading: const Icon(Icons.download_for_offline_outlined),
              title: Text(t.saveLogsTooltip),
              onTap: widget.onSaveLogs,
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: TextStyle(
          color: isLight ? Colors.black87 : Colors.white70,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
