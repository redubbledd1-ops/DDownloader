enum OutputFormat { mp4, mp3 }

enum PlaylistMode { ask, playlist, single }

class FormatInfo {
  final String formatId;
  final String ext;
  final String note;
  final int? filesizeBytes;
  final bool isApproxSize;
  final String? vcodec;
  final String? acodec;
  final int? height;

  FormatInfo({
    required this.formatId,
    required this.ext,
    required this.note,
    required this.filesizeBytes,
    required this.isApproxSize,
    required this.vcodec,
    required this.acodec,
    required this.height,
  });

  factory FormatInfo.fromJson(Map<String, dynamic> json) {
    final height = json['height'];
    final filesize = json['filesize'];
    final filesizeApprox = json['filesize_approx'];
    final formatId = json['format_id']?.toString();
    return FormatInfo(
      formatId: (formatId == null || formatId.isEmpty) ? 'best' : formatId,
      ext: json['ext']?.toString() ?? '',
      note: json['format_note']?.toString() ?? '',
      filesizeBytes: (filesize is num)
          ? filesize.toInt()
          : (filesizeApprox is num ? filesizeApprox.toInt() : null),
      isApproxSize: filesize is! num && filesizeApprox is num,
      vcodec: json['vcodec']?.toString(),
      acodec: json['acodec']?.toString(),
      height: (height is num) ? height.toInt() : null,
    );
  }

  // Veel extractors laten vcodec/acodec gewoon weg i.p.v. "none" te zetten
  // wanneer het niet bekend is. Onbekend betekenen we als "waarschijnlijk aanwezig",
  // anders vallen te veel sites (niet-YouTube) onterecht buiten de lijst.
  bool get hasAudio =>
      acodec == null || (acodec != 'none' && acodec!.isNotEmpty);
  bool get hasVideo =>
      vcodec == null || (vcodec != 'none' && vcodec!.isNotEmpty);

  String get sizeLabel {
    if (filesizeBytes == null) return 'onbekend';
    final mb = filesizeBytes! / (1024 * 1024);
    final prefix = isApproxSize ? '~' : '';
    if (mb >= 1024) {
      return '$prefix${(mb / 1024).toStringAsFixed(2)} GB';
    }
    return '$prefix${mb.toStringAsFixed(1)} MB';
  }

  String get label {
    // format_note heeft meestal de standaardresolutie ("720p"); height kan
    // bij niet-16:9 video's afwijken (bijv. 734) en verwarrende labels geven.
    final noteMatch = RegExp(r'(\d{3,4})p').firstMatch(note);
    final res = noteMatch != null
        ? '${noteMatch.group(1)}p'
        : (height != null
            ? '${height}p'
            : (note.isEmpty ? formatId : note));
    return '$res  ·  $ext  ·  $sizeLabel';
  }
}

class DownloadedItem {
  final String path;
  final bool isPlaylist;
  final OutputFormat format;

  DownloadedItem({
    required this.path,
    required this.isPlaylist,
    required this.format,
  });

  String get fileName => path.split(RegExp(r'[\\/]')).last;

  Map<String, dynamic> toJson() => {
    'path': path,
    'isPlaylist': isPlaylist,
    'format': format.name,
  };

  factory DownloadedItem.fromJson(Map<String, dynamic> json) => DownloadedItem(
    path: json['path'] as String,
    isPlaylist: json['isPlaylist'] as bool? ?? false,
    format: OutputFormat.values.firstWhere(
      (f) => f.name == json['format'],
      orElse: () => OutputFormat.mp4,
    ),
  );
}

enum FileFilter { all, video, audio }

abstract class DownloadEvent {}

class ProgressEvent extends DownloadEvent {
  final double percent;
  ProgressEvent(this.percent);
}

class FileDownloadedEvent extends DownloadEvent {
  final String path;
  FileDownloadedEvent(this.path);
}

class StatusEvent extends DownloadEvent {
  final String message;
  StatusEvent(this.message);
}

class DownloadDoneEvent extends DownloadEvent {
  final bool success;
  final String? error;
  DownloadDoneEvent({required this.success, this.error});
}

class LogEvent extends DownloadEvent {
  final String message;
  LogEvent(this.message);
}
