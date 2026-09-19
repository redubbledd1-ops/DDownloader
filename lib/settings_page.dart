import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'folder_history_page.dart';
import 'l10n.dart';
import 'models.dart';
import 'settings.dart';
import 'app_version.dart';

class SettingsPage extends StatefulWidget {
  final bool isDarkMode;
  final ValueChanged<bool> onToggleDarkMode;
  final AppLanguage language;
  final ValueChanged<AppLanguage> onChangeLanguage;
  final String downloadDir;
  final ValueChanged<String> onChangeDownloadDir;
  final bool autoDownloadOnClick;
  final ValueChanged<bool> onChangeAutoDownloadOnClick;
  final CookiesBrowser cookiesBrowser;
  final ValueChanged<CookiesBrowser> onChangeCookiesBrowser;
  final ValueNotifier<bool> showLogs;
  final ValueChanged<bool> onToggleShowLogs;
  final VoidCallback onSaveLogs;
  final VoidCallback onShareLogs;
  final Future<String?> Function() onUpdateYtDlp;
  final Future<String?> Function() ytDlpVersion;
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
    required this.cookiesBrowser,
    required this.onChangeCookiesBrowser,
    required this.showLogs,
    required this.onToggleShowLogs,
    required this.onSaveLogs,
    required this.onShareLogs,
    required this.onUpdateYtDlp,
    required this.ytDlpVersion,
    required this.logs,
    required this.logsTick,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late String _downloadDir = widget.downloadDir;
  bool _splitFormatDirs = false;
  String _mp4Dir = '';
  String _mp3Dir = '';
  String? _ytDlpVersion;
  bool _updatingYtDlp = false;
  final _logScrollController = ScrollController();
  String _dataDir = '';

  @override
  void initState() {
    super.initState();
    Settings.appDataDir().then((dir) {
      if (mounted) setState(() => _dataDir = dir.path);
    });
    _loadFormatDirs();
    if (Platform.isAndroid) {
      widget.ytDlpVersion().then((v) {
        if (mounted) setState(() => _ytDlpVersion = v);
      });
    }
  }

  @override
  void dispose() {
    _logScrollController.dispose();
    super.dispose();
  }

  L10n get t => L10n(widget.language);

  Future<void> _copyLogs() async {
    await Clipboard.setData(ClipboardData(text: widget.logs.join('\n')));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(t.logsCopied)));
  }

  Future<void> _pickDir() async {
    final selected = await FilePicker.platform.getDirectoryPath(
      dialogTitle: t.changeFolderButton,
      initialDirectory: _downloadDir.isEmpty ? null : _downloadDir,
    );
    if (selected == null) return;
    await _applyMainDir(selected);
  }

  Future<void> _applyMainDir(String dir) async {
    await Settings.setDownloadDir(dir);
    await Settings.addFolderHistory(dir);
    if (!mounted) return;
    setState(() => _downloadDir = dir);
    widget.onChangeDownloadDir(dir);
  }

  Future<void> _applyFormatDir(OutputFormat format, String dir) async {
    await Settings.setFormatDir(format, dir);
    await Settings.addFolderHistory(dir);
    if (!mounted) return;
    setState(() {
      if (format == OutputFormat.mp3) {
        _mp3Dir = dir;
      } else {
        _mp4Dir = dir;
      }
    });
  }

  Widget _folderTile(
    IconData icon,
    String title,
    String path,
    VoidCallback onTap,
  ) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(path.isEmpty ? t.loadingDownloadDir : path),
      onTap: onTap,
    );
  }

  Widget _changeFolderButton(String label, VoidCallback onPressed) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: onPressed,
          icon: const Icon(Icons.drive_file_move_outline),
          label: Text(label),
        ),
      ),
    );
  }

  /// De mappen-geschiedenis is gedeeld; alleen het doel verschilt, zodat een
  /// keuze bij (MP3) ook echt de MP3-map zet en niet de hoofdmap.
  Widget _historyTile(
    String title,
    String currentDir,
    Future<void> Function(String) onSelect,
  ) {
    return ListTile(
      leading: const Icon(Icons.history),
      title: Text(title),
      trailing: const Icon(Icons.chevron_right),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => FolderHistoryPage(
              language: widget.language,
              currentDir: currentDir,
              onSelectFolder: onSelect,
            ),
          ),
        );
      },
    );
  }

  Widget _openFolderTile(String title, String dir) {
    return ListTile(
      leading: const Icon(Icons.folder_open),
      title: Text(title),
      onTap: dir.isEmpty
          ? null
          : () => Process.start('explorer.exe', [
              dir,
            ], mode: ProcessStartMode.detached),
    );
  }

  Future<void> _loadFormatDirs() async {
    final split = await Settings.getSplitFormatDirs();
    final mp4 = await Settings.getFormatDir(OutputFormat.mp4);
    final mp3 = await Settings.getFormatDir(OutputFormat.mp3);
    if (!mounted) return;
    setState(() {
      _splitFormatDirs = split;
      _mp4Dir = mp4 ?? '';
      _mp3Dir = mp3 ?? '';
    });
  }

  Future<void> _pickFormatDir(OutputFormat format) async {
    final current = format == OutputFormat.mp3 ? _mp3Dir : _mp4Dir;
    final initial = current.isNotEmpty ? current : _downloadDir;
    final selected = await FilePicker.platform.getDirectoryPath(
      dialogTitle: t.changeFolderButton,
      initialDirectory: initial.isEmpty ? null : initial,
    );
    if (selected == null) return;
    await _applyFormatDir(format, selected);
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

  Future<void> _pickCookiesBrowser() async {
    final chosen = await showDialog<CookiesBrowser>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.cookiesBrowserLabel),
        content: SizedBox(
          width: 320,
          child: RadioGroup<CookiesBrowser>(
            groupValue: widget.cookiesBrowser,
            onChanged: (browser) {
              if (browser != null) Navigator.pop(ctx, browser);
            },
            child: ListView(
              shrinkWrap: true,
              children: CookiesBrowser.values
                  .map(
                    (browser) => RadioListTile<CookiesBrowser>(
                      value: browser,
                      title: Text(t.cookiesBrowserName(browser)),
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
    if (chosen != null) widget.onChangeCookiesBrowser(chosen);
  }

  @override
  Widget build(BuildContext context) {
    // Zonder eigen keuze valt een formaat terug op de hoofdmap; dat tonen we
    // ook zo, i.p.v. een leeg pad.
    final mp4Dir = _mp4Dir.isEmpty ? _downloadDir : _mp4Dir;
    final mp3Dir = _mp3Dir.isEmpty ? _downloadDir : _mp3Dir;
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
            // Keuze bovenaan, want die bepaalt wat er hieronder staat: een
            // map met een knop, of twee mappen met twee knoppen.
            SwitchListTile(
              secondary: const Icon(Icons.folder_copy_outlined),
              title: Text(t.sameFolderBothFormatsTitle),
              subtitle: Text(t.sameFolderBothFormatsSubtitle),
              value: !_splitFormatDirs,
              onChanged: (value) async {
                setState(() => _splitFormatDirs = !value);
                await Settings.setSplitFormatDirs(!value);
              },
            ),
            if (!_splitFormatDirs) ...[
              _folderTile(
                Icons.folder_outlined,
                t.currentFolderLabel,
                _downloadDir,
                _pickDir,
              ),
              _changeFolderButton(t.changeFolderButton, _pickDir),
              _historyTile(t.folderHistoryButton, _downloadDir, _applyMainDir),
              if (!Platform.isAndroid)
                _openFolderTile(t.openDownloadFolderTooltip, _downloadDir),
            ] else ...[
              _folderTile(
                Icons.movie_outlined,
                t.mp4FolderLabel,
                mp4Dir,
                () => _pickFormatDir(OutputFormat.mp4),
              ),
              _folderTile(
                Icons.audiotrack,
                t.mp3FolderLabel,
                mp3Dir,
                () => _pickFormatDir(OutputFormat.mp3),
              ),
              _changeFolderButton(
                t.changeMp4FolderButton,
                () => _pickFormatDir(OutputFormat.mp4),
              ),
              _changeFolderButton(
                t.changeMp3FolderButton,
                () => _pickFormatDir(OutputFormat.mp3),
              ),
              _historyTile(
                '${t.folderHistoryButton} (MP4)',
                mp4Dir,
                (dir) => _applyFormatDir(OutputFormat.mp4, dir),
              ),
              _historyTile(
                '${t.folderHistoryButton} (MP3)',
                mp3Dir,
                (dir) => _applyFormatDir(OutputFormat.mp3, dir),
              ),
              if (!Platform.isAndroid) ...[
                _openFolderTile('${t.openDownloadFolderTooltip} (MP4)', mp4Dir),
                _openFolderTile('${t.openDownloadFolderTooltip} (MP3)', mp3Dir),
              ],
            ],
            if (!Platform.isAndroid) ...[
              _SectionHeader(title: t.cookiesSection),
              ListTile(
                leading: const Icon(Icons.cookie_outlined),
                title: Text(t.cookiesBrowserLabel),
                subtitle: Text(
                  '${t.cookiesBrowserName(widget.cookiesBrowser)}\n${t.cookiesBrowserSubtitle}',
                ),
                isThreeLine: true,
                onTap: _pickCookiesBrowser,
              ),
            ],
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
            if (Platform.isAndroid) ...[
              _SectionHeader(title: 'yt-dlp'),
              ListTile(
                leading: _updatingYtDlp
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.system_update_alt),
                title: Text(t.updateYtDlpTitle),
                subtitle: Text(t.updateYtDlpSubtitle(_ytDlpVersion)),
                onTap: _updatingYtDlp
                    ? null
                    : () async {
                        setState(() => _updatingYtDlp = true);
                        final version = await widget.onUpdateYtDlp();
                        if (!mounted) return;
                        setState(() {
                          _updatingYtDlp = false;
                          if (version != null) _ytDlpVersion = version;
                        });
                      },
              ),
            ],
            _SectionHeader(title: t.logsTooltip),
            // Schakelaar en paneel lezen allebei rechtstreeks uit de notifier
            // van HomePage. Een eigen kopie hier liep uit de pas zodra deze
            // route of HomePage opnieuw werd opgebouwd.
            ValueListenableBuilder<bool>(
              valueListenable: widget.showLogs,
              builder: (context, showLogs, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SwitchListTile(
                    title: Text(t.showLogsLabel),
                    subtitle: Text(t.showLogsSubtitle),
                    value: showLogs,
                    onChanged: widget.onToggleShowLogs,
                  ),
                  if (showLogs) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton.icon(
                            icon: const Icon(Icons.copy_all, size: 18),
                            label: Text(t.copyLogsTooltip),
                            onPressed: widget.logs.isEmpty ? null : _copyLogs,
                          ),
                          const SizedBox(width: 8),
                          TextButton.icon(
                            icon: const Icon(Icons.share, size: 18),
                            label: Text(t.shareLogsTooltip),
                            onPressed: widget.logs.isEmpty
                                ? null
                                : widget.onShareLogs,
                          ),
                        ],
                      ),
                    ),
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
                                      style: const TextStyle(
                                        color: Colors.grey,
                                      ),
                                    ),
                                  )
                                // SelectionArea maakt de regels met de vinger
                                // selecteerbaar; los daarvan blijft de
                                // Kopieer-knop hierboven de snelste weg naar
                                // het hele log.
                                : SelectionArea(
                                    child: Scrollbar(
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
                                  ),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.download_for_offline_outlined),
              title: Text(t.saveLogsTooltip),
              onTap: widget.onSaveLogs,
            ),
            _SectionHeader(title: t.aboutSection),
            if (_dataDir.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.folder_shared_outlined),
                title: Text(t.dataFolderLabel),
                subtitle: Text(_dataDir),
                onTap: Platform.isWindows
                    ? () => Process.start('explorer.exe', [
                        _dataDir,
                      ], mode: ProcessStartMode.detached)
                    : null,
              ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(t.appVersionLabel),
              subtitle: const Text(kAppVersion),
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
