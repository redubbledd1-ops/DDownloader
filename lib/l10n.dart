import 'models.dart';

/// Lichtgewicht vertaal-laag: geen codegen, gewoon een switch per taal.
class L10n {
  final AppLanguage language;
  const L10n(this.language);

  String get settingsTitle => switch (language) {
    AppLanguage.nl => 'Instellingen',
    AppLanguage.en => 'Settings',
    AppLanguage.de => 'Einstellungen',
    AppLanguage.fr => 'Paramètres',
    AppLanguage.es => 'Configuración',
    AppLanguage.pt => 'Configurações',
  };

  String playlistModeTooltip(PlaylistMode mode) => switch (mode) {
    PlaylistMode.playlist => switch (language) {
      AppLanguage.nl => 'Playlist-modus: altijd hele playlist downloaden',
      AppLanguage.en => 'Playlist mode: always download the whole playlist',
      AppLanguage.de => 'Playlist-Modus: immer die ganze Playlist herunterladen',
      AppLanguage.fr => 'Mode playlist : toujours télécharger toute la playlist',
      AppLanguage.es => 'Modo playlist: descargar siempre toda la lista',
      AppLanguage.pt => 'Modo playlist: baixar sempre a playlist inteira',
    },
    PlaylistMode.single => switch (language) {
      AppLanguage.nl => 'Playlist-modus: altijd maar 1 bestand downloaden',
      AppLanguage.en => 'Playlist mode: always download just 1 file',
      AppLanguage.de => 'Playlist-Modus: immer nur 1 Datei herunterladen',
      AppLanguage.fr => 'Mode playlist : toujours télécharger 1 seul fichier',
      AppLanguage.es => 'Modo playlist: descargar siempre solo 1 archivo',
      AppLanguage.pt => 'Modo playlist: baixar sempre apenas 1 arquivo',
    },
    PlaylistMode.ask => switch (language) {
      AppLanguage.nl => 'Playlist-modus: elke keer vragen',
      AppLanguage.en => 'Playlist mode: ask every time',
      AppLanguage.de => 'Playlist-Modus: jedes Mal fragen',
      AppLanguage.fr => 'Mode playlist : demander à chaque fois',
      AppLanguage.es => 'Modo playlist: preguntar cada vez',
      AppLanguage.pt => 'Modo playlist: perguntar sempre',
    },
  };

  String get logsTooltip => switch (language) {
    AppLanguage.nl => 'Logs',
    AppLanguage.en => 'Logs',
    AppLanguage.de => 'Protokolle',
    AppLanguage.fr => 'Journaux',
    AppLanguage.es => 'Registros',
    AppLanguage.pt => 'Registros',
  };

  String get showLogsLabel => switch (language) {
    AppLanguage.nl => 'Logs tonen',
    AppLanguage.en => 'Show logs',
    AppLanguage.de => 'Protokolle anzeigen',
    AppLanguage.fr => 'Afficher les journaux',
    AppLanguage.es => 'Mostrar registros',
    AppLanguage.pt => 'Mostrar registros',
  };

  String get showLogsSubtitle => switch (language) {
    AppLanguage.nl => 'Toont het logpaneel onderaan het hoofdscherm.',
    AppLanguage.en => 'Shows the log panel on the main screen.',
    AppLanguage.de => 'Zeigt das Protokollfeld auf dem Hauptbildschirm.',
    AppLanguage.fr => "Affiche le panneau des journaux sur l'écran principal.",
    AppLanguage.es => 'Muestra el panel de registros en la pantalla principal.',
    AppLanguage.pt => 'Mostra o painel de registros na tela principal.',
  };

  String get saveLogsTooltip => switch (language) {
    AppLanguage.nl => 'Log opslaan als tekstbestand',
    AppLanguage.en => 'Save log as text file',
    AppLanguage.de => 'Protokoll als Textdatei speichern',
    AppLanguage.fr => 'Enregistrer le journal en fichier texte',
    AppLanguage.es => 'Guardar registro como archivo de texto',
    AppLanguage.pt => 'Salvar registro como arquivo de texto',
  };

  String get openDownloadFolderTooltip => switch (language) {
    AppLanguage.nl => 'Open downloadmap',
    AppLanguage.en => 'Open download folder',
    AppLanguage.de => 'Downloadordner öffnen',
    AppLanguage.fr => 'Ouvrir le dossier de téléchargement',
    AppLanguage.es => 'Abrir carpeta de descargas',
    AppLanguage.pt => 'Abrir pasta de downloads',
  };

  String get settingsTooltip => switch (language) {
    AppLanguage.nl => 'Instellingen',
    AppLanguage.en => 'Settings',
    AppLanguage.de => 'Einstellungen',
    AppLanguage.fr => 'Paramètres',
    AppLanguage.es => 'Configuración',
    AppLanguage.pt => 'Configurações',
  };

  String get urlLabel => switch (language) {
    AppLanguage.nl => 'Video of playlist URL',
    AppLanguage.en => 'Video or playlist URL',
    AppLanguage.de => 'Video- oder Playlist-URL',
    AppLanguage.fr => 'URL de vidéo ou de playlist',
    AppLanguage.es => 'URL de vídeo o playlist',
    AppLanguage.pt => 'URL de vídeo ou playlist',
  };

  String get downloadButton => switch (language) {
    AppLanguage.nl => 'Download',
    AppLanguage.en => 'Download',
    AppLanguage.de => 'Herunterladen',
    AppLanguage.fr => 'Télécharger',
    AppLanguage.es => 'Descargar',
    AppLanguage.pt => 'Baixar',
  };

  String get formatLabel => switch (language) {
    AppLanguage.nl => 'Formaat: ',
    AppLanguage.en => 'Format: ',
    AppLanguage.de => 'Format: ',
    AppLanguage.fr => 'Format : ',
    AppLanguage.es => 'Formato: ',
    AppLanguage.pt => 'Formato: ',
  };

  String get mp4QualityLabel => switch (language) {
    AppLanguage.nl => 'MP4-kwaliteit: ',
    AppLanguage.en => 'MP4 quality: ',
    AppLanguage.de => 'MP4-Qualität: ',
    AppLanguage.fr => 'Qualité MP4 : ',
    AppLanguage.es => 'Calidad MP4: ',
    AppLanguage.pt => 'Qualidade MP4: ',
  };

  String qualityLabel(PreferredVideoQuality q) {
    switch (q) {
      case PreferredVideoQuality.ask:
        return switch (language) {
          AppLanguage.nl => 'Altijd vragen',
          AppLanguage.en => 'Always ask',
          AppLanguage.de => 'Immer fragen',
          AppLanguage.fr => 'Toujours demander',
          AppLanguage.es => 'Preguntar siempre',
          AppLanguage.pt => 'Perguntar sempre',
        };
      case PreferredVideoQuality.max:
        return switch (language) {
          AppLanguage.nl => 'Max (beste beschikbaar)',
          AppLanguage.en => 'Max (best available)',
          AppLanguage.de => 'Max (beste verfügbare)',
          AppLanguage.fr => 'Max (meilleure disponible)',
          AppLanguage.es => 'Máx (mejor disponible)',
          AppLanguage.pt => 'Máx (melhor disponível)',
        };
      default:
        return q.label;
    }
  }

  String get qualityAskHint => switch (language) {
    AppLanguage.nl => 'Bij downloaden eerst kwaliteit kiezen.',
    AppLanguage.en => 'Pick quality first when downloading.',
    AppLanguage.de => 'Beim Herunterladen zuerst Qualität wählen.',
    AppLanguage.fr => 'Choisir la qualité avant de télécharger.',
    AppLanguage.es => 'Elegir calidad antes de descargar.',
    AppLanguage.pt => 'Escolher qualidade antes de baixar.',
  };

  String qualityDirectHint(String quality) => switch (language) {
    AppLanguage.nl => 'Direct downloaden (app + extentie) gebruikt $quality.',
    AppLanguage.en => 'Direct download (app + extension) uses $quality.',
    AppLanguage.de => 'Direkter Download (App + Erweiterung) verwendet $quality.',
    AppLanguage.fr => 'Le téléchargement direct (app + extension) utilise $quality.',
    AppLanguage.es => 'La descarga directa (app + extensión) usa $quality.',
    AppLanguage.pt => 'O download direto (app + extensão) usa $quality.',
  };

  String get extAutoDownloadTitle => switch (language) {
    AppLanguage.nl => 'Extentie-icoon downloadt meteen',
    AppLanguage.en => 'Extension icon downloads instantly',
    AppLanguage.de => 'Erweiterungssymbol lädt sofort herunter',
    AppLanguage.fr => 'L\'icône de l\'extension télécharge aussitôt',
    AppLanguage.es => 'El icono de la extensión descarga al instante',
    AppLanguage.pt => 'O ícone da extensão baixa na hora',
  };

  String get extAutoDownloadOnSubtitle => switch (language) {
    AppLanguage.nl => 'Klik op het extentie-icoon start direct een download (app-instellingen).',
    AppLanguage.en => 'Clicking the extension icon starts a download right away (app settings).',
    AppLanguage.de => 'Klick auf das Erweiterungssymbol startet sofort einen Download (App-Einstellungen).',
    AppLanguage.fr => 'Cliquer sur l\'icône de l\'extension lance aussitôt un téléchargement (paramètres de l\'app).',
    AppLanguage.es => 'Al hacer clic en el icono de la extensión se inicia una descarga al instante (ajustes de la app).',
    AppLanguage.pt => 'Clicar no ícone da extensão inicia um download na hora (configurações do app).',
  };

  String get extAutoDownloadOffSubtitle => switch (language) {
    AppLanguage.nl => 'Klik op het extentie-icoon opent eerst het venster.',
    AppLanguage.en => 'Clicking the extension icon opens the window first.',
    AppLanguage.de => 'Klick auf das Erweiterungssymbol öffnet zuerst das Fenster.',
    AppLanguage.fr => 'Cliquer sur l\'icône de l\'extension ouvre d\'abord la fenêtre.',
    AppLanguage.es => 'Al hacer clic en el icono de la extensión primero se abre la ventana.',
    AppLanguage.pt => 'Clicar no ícone da extensão abre a janela primeiro.',
  };

  String get noLogsYet => switch (language) {
    AppLanguage.nl => 'Nog geen logs',
    AppLanguage.en => 'No logs yet',
    AppLanguage.de => 'Noch keine Protokolle',
    AppLanguage.fr => 'Pas encore de journaux',
    AppLanguage.es => 'Aún no hay registros',
    AppLanguage.pt => 'Ainda sem registros',
  };

  String get downloadedFilesHeader => switch (language) {
    AppLanguage.nl => 'Gedownloade bestanden',
    AppLanguage.en => 'Downloaded files',
    AppLanguage.de => 'Heruntergeladene Dateien',
    AppLanguage.fr => 'Fichiers téléchargés',
    AppLanguage.es => 'Archivos descargados',
    AppLanguage.pt => 'Arquivos baixados',
  };

  String get deleteAllTooltip => switch (language) {
    AppLanguage.nl => 'Alle bestanden verwijderen',
    AppLanguage.en => 'Delete all files',
    AppLanguage.de => 'Alle Dateien löschen',
    AppLanguage.fr => 'Supprimer tous les fichiers',
    AppLanguage.es => 'Eliminar todos los archivos',
    AppLanguage.pt => 'Excluir todos os arquivos',
  };

  String get searchHint => switch (language) {
    AppLanguage.nl => 'Zoeken in bestanden...',
    AppLanguage.en => 'Search files...',
    AppLanguage.de => 'Dateien durchsuchen...',
    AppLanguage.fr => 'Rechercher des fichiers...',
    AppLanguage.es => 'Buscar archivos...',
    AppLanguage.pt => 'Buscar arquivos...',
  };

  String get filterAll => switch (language) {
    AppLanguage.nl => 'Alles',
    AppLanguage.en => 'All',
    AppLanguage.de => 'Alle',
    AppLanguage.fr => 'Tout',
    AppLanguage.es => 'Todo',
    AppLanguage.pt => 'Tudo',
  };

  String get filterVideo => switch (language) {
    AppLanguage.nl => 'Video\'s',
    AppLanguage.en => 'Videos',
    AppLanguage.de => 'Videos',
    AppLanguage.fr => 'Vidéos',
    AppLanguage.es => 'Vídeos',
    AppLanguage.pt => 'Vídeos',
  };

  String get filterAudio => switch (language) {
    AppLanguage.nl => 'Audio',
    AppLanguage.en => 'Audio',
    AppLanguage.de => 'Audio',
    AppLanguage.fr => 'Audio',
    AppLanguage.es => 'Audio',
    AppLanguage.pt => 'Áudio',
  };

  String get nothingDownloadedYet => switch (language) {
    AppLanguage.nl => 'Nog niets gedownload',
    AppLanguage.en => 'Nothing downloaded yet',
    AppLanguage.de => 'Noch nichts heruntergeladen',
    AppLanguage.fr => 'Rien de téléchargé pour l\'instant',
    AppLanguage.es => 'Aún no hay descargas',
    AppLanguage.pt => 'Ainda nada baixado',
  };

  String get noResults => switch (language) {
    AppLanguage.nl => 'Geen resultaten',
    AppLanguage.en => 'No results',
    AppLanguage.de => 'Keine Ergebnisse',
    AppLanguage.fr => 'Aucun résultat',
    AppLanguage.es => 'Sin resultados',
    AppLanguage.pt => 'Sem resultados',
  };

  String get openFolderTooltip => switch (language) {
    AppLanguage.nl => 'Open map',
    AppLanguage.en => 'Open folder',
    AppLanguage.de => 'Ordner öffnen',
    AppLanguage.fr => 'Ouvrir le dossier',
    AppLanguage.es => 'Abrir carpeta',
    AppLanguage.pt => 'Abrir pasta',
  };

  String get deleteTooltip => switch (language) {
    AppLanguage.nl => 'Verwijderen',
    AppLanguage.en => 'Delete',
    AppLanguage.de => 'Löschen',
    AppLanguage.fr => 'Supprimer',
    AppLanguage.es => 'Eliminar',
    AppLanguage.pt => 'Excluir',
  };

  String get partOfPlaylist => switch (language) {
    AppLanguage.nl => 'Onderdeel van een playlist-download',
    AppLanguage.en => 'Part of a playlist download',
    AppLanguage.de => 'Teil eines Playlist-Downloads',
    AppLanguage.fr => 'Fait partie d\'un téléchargement de playlist',
    AppLanguage.es => 'Parte de una descarga de playlist',
    AppLanguage.pt => 'Parte de um download de playlist',
  };

  String get loadingDownloadDir => switch (language) {
    AppLanguage.nl => 'Downloadmap laden...',
    AppLanguage.en => 'Loading download folder...',
    AppLanguage.de => 'Downloadordner wird geladen...',
    AppLanguage.fr => 'Chargement du dossier de téléchargement...',
    AppLanguage.es => 'Cargando carpeta de descargas...',
    AppLanguage.pt => 'Carregando pasta de downloads...',
  };

  String get changeButton => switch (language) {
    AppLanguage.nl => 'Wijzig...',
    AppLanguage.en => 'Change...',
    AppLanguage.de => 'Ändern...',
    AppLanguage.fr => 'Changer...',
    AppLanguage.es => 'Cambiar...',
    AppLanguage.pt => 'Alterar...',
  };

  String get playlistDetectedTitle => switch (language) {
    AppLanguage.nl => 'Playlist gedetecteerd',
    AppLanguage.en => 'Playlist detected',
    AppLanguage.de => 'Playlist erkannt',
    AppLanguage.fr => 'Playlist détectée',
    AppLanguage.es => 'Playlist detectada',
    AppLanguage.pt => 'Playlist detectada',
  };

  String get playlistDetectedContent => switch (language) {
    AppLanguage.nl => 'Deze URL bevat een playlist. Wat wil je downloaden?',
    AppLanguage.en => 'This URL contains a playlist. What do you want to download?',
    AppLanguage.de => 'Diese URL enthält eine Playlist. Was möchtest du herunterladen?',
    AppLanguage.fr => 'Cette URL contient une playlist. Que voulez-vous télécharger ?',
    AppLanguage.es => 'Esta URL contiene una playlist. ¿Qué quieres descargar?',
    AppLanguage.pt => 'Este URL contém uma playlist. O que deseja baixar?',
  };

  String get onlyThisVideo => switch (language) {
    AppLanguage.nl => 'Alleen deze video',
    AppLanguage.en => 'Only this video',
    AppLanguage.de => 'Nur dieses Video',
    AppLanguage.fr => 'Seulement cette vidéo',
    AppLanguage.es => 'Solo este vídeo',
    AppLanguage.pt => 'Somente este vídeo',
  };

  String get wholePlaylist => switch (language) {
    AppLanguage.nl => 'Hele playlist',
    AppLanguage.en => 'Whole playlist',
    AppLanguage.de => 'Ganze Playlist',
    AppLanguage.fr => 'Toute la playlist',
    AppLanguage.es => 'Toda la playlist',
    AppLanguage.pt => 'Playlist inteira',
  };

  String get chooseQualityTitle => switch (language) {
    AppLanguage.nl => 'Kies kwaliteit',
    AppLanguage.en => 'Choose quality',
    AppLanguage.de => 'Qualität wählen',
    AppLanguage.fr => 'Choisir la qualité',
    AppLanguage.es => 'Elegir calidad',
    AppLanguage.pt => 'Escolher qualidade',
  };

  String get videoAndAudio => switch (language) {
    AppLanguage.nl => 'video + audio',
    AppLanguage.en => 'video + audio',
    AppLanguage.de => 'Video + Audio',
    AppLanguage.fr => 'vidéo + audio',
    AppLanguage.es => 'vídeo + audio',
    AppLanguage.pt => 'vídeo + áudio',
  };

  String get videoOnly => switch (language) {
    AppLanguage.nl => 'video only (audio wordt toegevoegd)',
    AppLanguage.en => 'video only (audio will be added)',
    AppLanguage.de => 'nur Video (Audio wird hinzugefügt)',
    AppLanguage.fr => 'vidéo seule (l\'audio sera ajouté)',
    AppLanguage.es => 'solo vídeo (se añadirá audio)',
    AppLanguage.pt => 'somente vídeo (áudio será adicionado)',
  };

  String get cancel => switch (language) {
    AppLanguage.nl => 'Annuleren',
    AppLanguage.en => 'Cancel',
    AppLanguage.de => 'Abbrechen',
    AppLanguage.fr => 'Annuler',
    AppLanguage.es => 'Cancelar',
    AppLanguage.pt => 'Cancelar',
  };

  String get deleteFileTitle => switch (language) {
    AppLanguage.nl => 'Bestand verwijderen?',
    AppLanguage.en => 'Delete file?',
    AppLanguage.de => 'Datei löschen?',
    AppLanguage.fr => 'Supprimer le fichier ?',
    AppLanguage.es => '¿Eliminar archivo?',
    AppLanguage.pt => 'Excluir arquivo?',
  };

  String deleteFileMessage(String name) => switch (language) {
    AppLanguage.nl => 'Weet je zeker dat je "$name" wilt verwijderen? Dit kan niet ongedaan worden gemaakt.',
    AppLanguage.en => 'Are you sure you want to delete "$name"? This cannot be undone.',
    AppLanguage.de => 'Möchtest du "$name" wirklich löschen? Dies kann nicht rückgängig gemacht werden.',
    AppLanguage.fr => 'Voulez-vous vraiment supprimer « $name » ? Cette action est irréversible.',
    AppLanguage.es => '¿Seguro que quieres eliminar "$name"? Esto no se puede deshacer.',
    AppLanguage.pt => 'Tem certeza de que deseja excluir "$name"? Isso não pode ser desfeito.',
  };

  String get deleteAllTitle => switch (language) {
    AppLanguage.nl => 'Alle bestanden verwijderen?',
    AppLanguage.en => 'Delete all files?',
    AppLanguage.de => 'Alle Dateien löschen?',
    AppLanguage.fr => 'Supprimer tous les fichiers ?',
    AppLanguage.es => '¿Eliminar todos los archivos?',
    AppLanguage.pt => 'Excluir todos os arquivos?',
  };

  String deleteAllMessage(int count) => switch (language) {
    AppLanguage.nl => 'Weet je zeker dat je alle $count gedownloade bestanden wilt verwijderen? Dit kan niet ongedaan worden gemaakt.',
    AppLanguage.en => 'Are you sure you want to delete all $count downloaded files? This cannot be undone.',
    AppLanguage.de => 'Möchtest du wirklich alle $count heruntergeladenen Dateien löschen? Dies kann nicht rückgängig gemacht werden.',
    AppLanguage.fr => 'Voulez-vous vraiment supprimer les $count fichiers téléchargés ? Cette action est irréversible.',
    AppLanguage.es => '¿Seguro que quieres eliminar los $count archivos descargados? Esto no se puede deshacer.',
    AppLanguage.pt => 'Tem certeza de que deseja excluir os $count arquivos baixados? Isso não pode ser desfeito.',
  };

  String get deleteConfirmButton => switch (language) {
    AppLanguage.nl => 'Verwijderen',
    AppLanguage.en => 'Delete',
    AppLanguage.de => 'Löschen',
    AppLanguage.fr => 'Supprimer',
    AppLanguage.es => 'Eliminar',
    AppLanguage.pt => 'Excluir',
  };

  String get noLogsToSave => switch (language) {
    AppLanguage.nl => 'Geen logs om op te slaan.',
    AppLanguage.en => 'No logs to save.',
    AppLanguage.de => 'Keine Protokolle zum Speichern.',
    AppLanguage.fr => 'Aucun journal à enregistrer.',
    AppLanguage.es => 'No hay registros para guardar.',
    AppLanguage.pt => 'Sem registros para salvar.',
  };

  String logSaved(String path) => switch (language) {
    AppLanguage.nl => 'Log opgeslagen: $path',
    AppLanguage.en => 'Log saved: $path',
    AppLanguage.de => 'Protokoll gespeichert: $path',
    AppLanguage.fr => 'Journal enregistré : $path',
    AppLanguage.es => 'Registro guardado: $path',
    AppLanguage.pt => 'Registro salvo: $path',
  };

  String errSaveLog(String e) => switch (language) {
    AppLanguage.nl => 'Kon log niet opslaan: $e',
    AppLanguage.en => 'Could not save log: $e',
    AppLanguage.de => 'Protokoll konnte nicht gespeichert werden: $e',
    AppLanguage.fr => 'Impossible d\'enregistrer le journal : $e',
    AppLanguage.es => 'No se pudo guardar el registro: $e',
    AppLanguage.pt => 'Não foi possível salvar o registro: $e',
  };

  String errOpenFile(String e) => switch (language) {
    AppLanguage.nl => 'Kon bestand niet openen: $e',
    AppLanguage.en => 'Could not open file: $e',
    AppLanguage.de => 'Datei konnte nicht geöffnet werden: $e',
    AppLanguage.fr => 'Impossible d\'ouvrir le fichier : $e',
    AppLanguage.es => 'No se pudo abrir el archivo: $e',
    AppLanguage.pt => 'Não foi possível abrir o arquivo: $e',
  };

  String errOpenFolder(String e) => switch (language) {
    AppLanguage.nl => 'Kon map niet openen: $e',
    AppLanguage.en => 'Could not open folder: $e',
    AppLanguage.de => 'Ordner konnte nicht geöffnet werden: $e',
    AppLanguage.fr => 'Impossible d\'ouvrir le dossier : $e',
    AppLanguage.es => 'No se pudo abrir la carpeta: $e',
    AppLanguage.pt => 'Não foi possível abrir a pasta: $e',
  };

  String errCheckUrl(String e) => switch (language) {
    AppLanguage.nl => 'Kon URL niet controleren: $e',
    AppLanguage.en => 'Could not check URL: $e',
    AppLanguage.de => 'URL konnte nicht überprüft werden: $e',
    AppLanguage.fr => 'Impossible de vérifier l\'URL : $e',
    AppLanguage.es => 'No se pudo comprobar la URL: $e',
    AppLanguage.pt => 'Não foi possível verificar a URL: $e',
  };

  String errFetchQualities(String e) => switch (language) {
    AppLanguage.nl => 'Kon kwaliteiten niet ophalen: $e',
    AppLanguage.en => 'Could not fetch qualities: $e',
    AppLanguage.de => 'Qualitäten konnten nicht abgerufen werden: $e',
    AppLanguage.fr => 'Impossible de récupérer les qualités : $e',
    AppLanguage.es => 'No se pudieron obtener las calidades: $e',
    AppLanguage.pt => 'Não foi possível obter as qualidades: $e',
  };

  String get noFormatsFound => switch (language) {
    AppLanguage.nl => 'Geen video-formats gevonden voor deze URL.',
    AppLanguage.en => 'No video formats found for this URL.',
    AppLanguage.de => 'Keine Videoformate für diese URL gefunden.',
    AppLanguage.fr => 'Aucun format vidéo trouvé pour cette URL.',
    AppLanguage.es => 'No se encontraron formatos de vídeo para esta URL.',
    AppLanguage.pt => 'Nenhum formato de vídeo encontrado para este URL.',
  };

  String downloadFailed(String e) => switch (language) {
    AppLanguage.nl => 'Download mislukt: $e',
    AppLanguage.en => 'Download failed: $e',
    AppLanguage.de => 'Download fehlgeschlagen: $e',
    AppLanguage.fr => 'Échec du téléchargement : $e',
    AppLanguage.es => 'Descarga fallida: $e',
    AppLanguage.pt => 'Falha no download: $e',
  };

  String errInstallFfmpeg(String e) => switch (language) {
    AppLanguage.nl => 'Kon ffmpeg niet installeren: $e',
    AppLanguage.en => 'Could not install ffmpeg: $e',
    AppLanguage.de => 'ffmpeg konnte nicht installiert werden: $e',
    AppLanguage.fr => 'Impossible d\'installer ffmpeg : $e',
    AppLanguage.es => 'No se pudo instalar ffmpeg: $e',
    AppLanguage.pt => 'Não foi possível instalar o ffmpeg: $e',
  };

  String errInstallYtDlp(String e) => switch (language) {
    AppLanguage.nl => 'Kon yt-dlp niet installeren: $e',
    AppLanguage.en => 'Could not install yt-dlp: $e',
    AppLanguage.de => 'yt-dlp konnte nicht installiert werden: $e',
    AppLanguage.fr => "Impossible d'installer yt-dlp : $e",
    AppLanguage.es => 'No se pudo instalar yt-dlp: $e',
    AppLanguage.pt => 'Não foi possível instalar o yt-dlp: $e',
  };

  String errDeleteFile(String e) => switch (language) {
    AppLanguage.nl => 'Kon bestand niet verwijderen: $e',
    AppLanguage.en => 'Could not delete file: $e',
    AppLanguage.de => 'Datei konnte nicht gelöscht werden: $e',
    AppLanguage.fr => 'Impossible de supprimer le fichier : $e',
    AppLanguage.es => 'No se pudo eliminar el archivo: $e',
    AppLanguage.pt => 'Não foi possível excluir o arquivo: $e',
  };

  String errDeleteSome(int count) => switch (language) {
    AppLanguage.nl => '$count bestand(en) konden niet verwijderd worden.',
    AppLanguage.en => '$count file(s) could not be deleted.',
    AppLanguage.de => '$count Datei(en) konnten nicht gelöscht werden.',
    AppLanguage.fr => '$count fichier(s) n\'ont pas pu être supprimés.',
    AppLanguage.es => 'No se pudieron eliminar $count archivo(s).',
    AppLanguage.pt => '$count arquivo(s) não puderam ser excluídos.',
  };

  // Settings page

  String get themeSection => switch (language) {
    AppLanguage.nl => 'Thema',
    AppLanguage.en => 'Theme',
    AppLanguage.de => 'Design',
    AppLanguage.fr => 'Thème',
    AppLanguage.es => 'Tema',
    AppLanguage.pt => 'Tema',
  };

  String get darkModeLabel => switch (language) {
    AppLanguage.nl => 'Donkere modus',
    AppLanguage.en => 'Dark mode',
    AppLanguage.de => 'Dunkler Modus',
    AppLanguage.fr => 'Mode sombre',
    AppLanguage.es => 'Modo oscuro',
    AppLanguage.pt => 'Modo escuro',
  };

  String get lightModeLabel => switch (language) {
    AppLanguage.nl => 'Lichte modus',
    AppLanguage.en => 'Light mode',
    AppLanguage.de => 'Heller Modus',
    AppLanguage.fr => 'Mode clair',
    AppLanguage.es => 'Modo claro',
    AppLanguage.pt => 'Modo claro',
  };

  String get languageSection => switch (language) {
    AppLanguage.nl => 'Taal',
    AppLanguage.en => 'Language',
    AppLanguage.de => 'Sprache',
    AppLanguage.fr => 'Langue',
    AppLanguage.es => 'Idioma',
    AppLanguage.pt => 'Idioma',
  };

  String get selectLanguageTitle => switch (language) {
    AppLanguage.nl => 'Kies taal',
    AppLanguage.en => 'Choose language',
    AppLanguage.de => 'Sprache wählen',
    AppLanguage.fr => 'Choisir la langue',
    AppLanguage.es => 'Elegir idioma',
    AppLanguage.pt => 'Escolher idioma',
  };

  String get extensionSection => switch (language) {
    AppLanguage.nl => 'Browserextentie',
    AppLanguage.en => 'Browser extension',
    AppLanguage.de => 'Browsererweiterung',
    AppLanguage.fr => 'Extension du navigateur',
    AppLanguage.es => 'Extensión del navegador',
    AppLanguage.pt => 'Extensão do navegador',
  };

  String get folderSection => switch (language) {
    AppLanguage.nl => 'Downloadmap',
    AppLanguage.en => 'Download folder',
    AppLanguage.de => 'Downloadordner',
    AppLanguage.fr => 'Dossier de téléchargement',
    AppLanguage.es => 'Carpeta de descargas',
    AppLanguage.pt => 'Pasta de downloads',
  };

  String get currentFolderLabel => switch (language) {
    AppLanguage.nl => 'Huidige map',
    AppLanguage.en => 'Current folder',
    AppLanguage.de => 'Aktueller Ordner',
    AppLanguage.fr => 'Dossier actuel',
    AppLanguage.es => 'Carpeta actual',
    AppLanguage.pt => 'Pasta atual',
  };

  String get changeFolderButton => switch (language) {
    AppLanguage.nl => 'Map wijzigen',
    AppLanguage.en => 'Change folder',
    AppLanguage.de => 'Ordner ändern',
    AppLanguage.fr => 'Changer de dossier',
    AppLanguage.es => 'Cambiar carpeta',
    AppLanguage.pt => 'Alterar pasta',
  };

  String get folderHistoryButton => switch (language) {
    AppLanguage.nl => 'Mappen geschiedenis',
    AppLanguage.en => 'Folder history',
    AppLanguage.de => 'Ordnerverlauf',
    AppLanguage.fr => 'Historique des dossiers',
    AppLanguage.es => 'Historial de carpetas',
    AppLanguage.pt => 'Histórico de pastas',
  };

  String get folderHistoryTitle => switch (language) {
    AppLanguage.nl => 'Mappen geschiedenis',
    AppLanguage.en => 'Folder history',
    AppLanguage.de => 'Ordnerverlauf',
    AppLanguage.fr => 'Historique des dossiers',
    AppLanguage.es => 'Historial de carpetas',
    AppLanguage.pt => 'Histórico de pastas',
  };

  String get folderHistoryEmpty => switch (language) {
    AppLanguage.nl => 'Nog geen mappen geschiedenis',
    AppLanguage.en => 'No folder history yet',
    AppLanguage.de => 'Noch kein Ordnerverlauf',
    AppLanguage.fr => 'Pas encore d\'historique de dossiers',
    AppLanguage.es => 'Aún no hay historial de carpetas',
    AppLanguage.pt => 'Ainda sem histórico de pastas',
  };

  String get fileStatusPresent => switch (language) {
    AppLanguage.nl => 'Aanwezig',
    AppLanguage.en => 'Present',
    AppLanguage.de => 'Vorhanden',
    AppLanguage.fr => 'Présent',
    AppLanguage.es => 'Presente',
    AppLanguage.pt => 'Presente',
  };

  String get fileStatusDeleted => switch (language) {
    AppLanguage.nl => 'Verwijderd',
    AppLanguage.en => 'Deleted',
    AppLanguage.de => 'Gelöscht',
    AppLanguage.fr => 'Supprimé',
    AppLanguage.es => 'Eliminado',
    AppLanguage.pt => 'Excluído',
  };

  String get fileStatusMoved => switch (language) {
    AppLanguage.nl => 'Mogelijk verplaatst',
    AppLanguage.en => 'Possibly moved',
    AppLanguage.de => 'Möglicherweise verschoben',
    AppLanguage.fr => 'Peut-être déplacé',
    AppLanguage.es => 'Posiblemente movido',
    AppLanguage.pt => 'Possivelmente movido',
  };

  String filesInFolder(int count) => switch (language) {
    AppLanguage.nl => '$count bestand(en)',
    AppLanguage.en => '$count file(s)',
    AppLanguage.de => '$count Datei(en)',
    AppLanguage.fr => '$count fichier(s)',
    AppLanguage.es => '$count archivo(s)',
    AppLanguage.pt => '$count arquivo(s)',
  };

  String get useThisFolder => switch (language) {
    AppLanguage.nl => 'Gebruik deze map',
    AppLanguage.en => 'Use this folder',
    AppLanguage.de => 'Diesen Ordner verwenden',
    AppLanguage.fr => 'Utiliser ce dossier',
    AppLanguage.es => 'Usar esta carpeta',
    AppLanguage.pt => 'Usar esta pasta',
  };

  String get removeFromHistory => switch (language) {
    AppLanguage.nl => 'Verwijder uit geschiedenis',
    AppLanguage.en => 'Remove from history',
    AppLanguage.de => 'Aus Verlauf entfernen',
    AppLanguage.fr => 'Retirer de l\'historique',
    AppLanguage.es => 'Quitar del historial',
    AppLanguage.pt => 'Remover do histórico',
  };
}
