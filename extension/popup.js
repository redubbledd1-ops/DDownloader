const HOST_NAME = "com.downoader.host";

const urlEl = document.getElementById("url");
const formatEl = document.getElementById("format");
const playlistEl = document.getElementById("playlistMode");
const downloadDirEl = document.getElementById("downloadDir");
const qualityEl = document.getElementById("quality");
const qualityField = document.getElementById("qualityField");
const qualityRow = document.getElementById("qualityRow");
const preferredQualityRow = document.getElementById("preferredQualityRow");
const refreshBtn = document.getElementById("refresh");
const debugToggleBtn = document.getElementById("debugToggle");
const debugPanelEl = document.getElementById("debugPanel");
const sendBtn = document.getElementById("sendToApp");
const downloadBtn = document.getElementById("downloadHere");
const autoDownloadEl = document.getElementById("autoDownload");
const openFolderBtn = document.getElementById("openFolderBtn");
const playFileBtn = document.getElementById("playFileBtn");
const downloadedActionsEl = document.getElementById("downloadedActions");
const playlistGroupEl = document.getElementById("playlistGroup");
const playlistSpinnerEl = document.getElementById("playlistSpinner");
const playlistFirstNameEl = document.getElementById("playlistFirstName");
const playlistToggleBtn = document.getElementById("playlistToggle");
const playlistCountEl = document.getElementById("playlistCount");
const playlistRestEl = document.getElementById("playlistRest");
const preferredQualityEl = document.getElementById("preferredQuality");
const githubLinkEl = document.getElementById("githubLink");
const audioOnlyEl = document.getElementById("audioOnly");
const directDownloadEnabledEl = document.getElementById("directDownloadEnabled");
const cookiesBrowserEl = document.getElementById("cookiesBrowser");
const settingsStatusEl = document.getElementById("settingsStatus");
const settingsResetBtn = document.getElementById("settingsReset");
const downloadDirRow = document.getElementById("downloadDirRow");
const cookiesBrowserRow = document.getElementById("cookiesBrowserRow");
const autoDownloadRow = document.getElementById("autoDownloadRow");
const directDownloadRow = document.getElementById("directDownloadRow");
const statusEl = document.getElementById("status");
const progressEl = document.getElementById("progress");
const debugLogEl = document.getElementById("debugLog");
const debugRedetectBtn = document.getElementById("debugRedetect");
const debugCopyBtn = document.getElementById("debugCopy");
const debugClearBtn = document.getElementById("debugClear");

const debugLines = [];

function debugTs() {
  return new Date().toISOString().slice(11, 23);
}

function debugLog(message, detail) {
  let line = `[${debugTs()}] ${message}`;
  if (detail !== undefined) {
    try {
      const extra =
        typeof detail === "string" ? detail : JSON.stringify(detail, null, 2);
      line += "\n" + extra;
    } catch (_) {
      line += "\n" + String(detail);
    }
  }
  debugLines.push(line);
  if (debugLines.length > 200) debugLines.splice(0, debugLines.length - 200);
  if (debugLogEl) {
    debugLogEl.textContent = debugLines.join("\n\n");
    debugLogEl.scrollTop = debugLogEl.scrollHeight;
  }
}

function debugClear() {
  debugLines.length = 0;
  if (debugLogEl) debugLogEl.textContent = "";
}

/** @type {Array<{formatId:string,label:string,ext:string,hasAudio:boolean,filesize?:number}>} */
let formats = [];
let busy = false;
let lastDownloadedPath = null;
let hostReady = false;
let isAndroid = false;
let settingsLoaded = false;
let saveTimer = null;
let saveInFlight = false;
let saveQueued = false;
let pendingSettingsChange = false;

// De app-instellingen staan in de shared_preferences.json van de Windows-app
// en gaan via de native host heen en weer. Die host is alleen niet altijd
// bereikbaar: Chrome/Firefox op Android kennen geen native messaging, en op
// Windows kan de host (nog) niet geregistreerd zijn. Voorheen bleef het
// instellingenblok dan permanent uitgeschakeld -- setBusy(true) werd in dat
// pad nooit meer teruggedraaid -- en negeerde scheduleSaveSettings elke
// wijziging: wel zichtbaar, niet in te stellen. Daarom schrijven we nu altijd
// eerst naar deze lokale spiegel en duwen we die naar de host zodra het kan.
const SETTINGS_STORAGE_KEY = "appSettings";
const SETTINGS_DIRTY_KEY = "appSettingsDirty";

const PLAYLIST_MODES = ["ask", "playlist", "single"];
const COOKIES_BROWSERS = ["none", "chrome", "edge", "firefox", "brave"];
const VIDEO_QUALITIES = [
  "ask",
  "max",
  "p2160",
  "p1440",
  "p1080",
  "p720",
  "p480",
  "p360",
  "p240",
  "p144",
];

const DEFAULT_SETTINGS = {
  downloadDir: "",
  format: "mp4",
  playlistMode: "ask",
  autoDownloadOnClick: false,
  preferredVideoQuality: "p1080",
  cookiesBrowser: "none",
};

function setStatus(text, kind = "") {
  statusEl.hidden = !text;
  statusEl.textContent = text || "";
  statusEl.className = "status" + (kind ? ` ${kind}` : "");
  if (text) debugLog(`status[${kind || "info"}]: ${text}`);
}

// Chrome/Edge geeft dit soort teksten als de native host niet geregistreerd
// is (host ontbreekt of yt-dlp/de Windows-app is nooit geïnstalleerd).
function isHostMissingError(e) {
  const m = ((e && e.message) || String(e)).toLowerCase();
  return (
    m.includes("native messaging host") ||
    m.includes("native application") ||
    m.includes("no such native") ||
    m.includes("host niet bereikbaar") ||
    m.includes("verbinding verbroken") ||
    m.includes("access denied") ||
    m.includes("not found")
  );
}

function showGithubLink(show) {
  githubLinkEl.hidden = !show;
}

// Puur een extentie-UI-voorkeur (niet gedeeld met de app), dus lokale
// chrome.storage i.p.v. de native-host settings.
function applyDirectDownloadEnabled(enabled) {
  downloadBtn.hidden = !enabled;
}

async function loadDirectDownloadEnabled() {
  return new Promise((resolve) => {
    chrome.storage.local.get({ directDownloadEnabled: true }, (res) => {
      resolve(res.directDownloadEnabled !== false);
    });
  });
}

function saveDirectDownloadEnabled(enabled) {
  chrome.storage.local.set({ directDownloadEnabled: enabled });
}

// Eigen regel onder het instellingenblok: het gewone statusveld hoort bij de
// download en werd anders om en om overschreven.
function setSettingsStatus(text, kind = "") {
  if (!settingsStatusEl) return;
  settingsStatusEl.hidden = !text;
  settingsStatusEl.textContent = text || "";
  settingsStatusEl.className = "settings-status" + (kind ? ` ${kind}` : "");
  if (text) debugLog(`settings[${kind || "info"}]: ${text}`);
}

function pickOneOf(value, allowed, fallback) {
  return allowed.includes(value) ? value : fallback;
}

// Een vaste vorm voor alles wat we opslaan, versturen of terugkrijgen, zodat
// een half ingevulde host-respons of een oude lokale kopie nooit onbekende
// waarden in de selects kan zetten (een select valt dan terug op leeg).
function normalizeSettings(settings) {
  const s = settings || {};
  return {
    downloadDir: typeof s.downloadDir === "string" ? s.downloadDir : "",
    format: s.format === "mp3" ? "mp3" : "mp4",
    playlistMode: pickOneOf(s.playlistMode, PLAYLIST_MODES, "ask"),
    autoDownloadOnClick: Boolean(s.autoDownloadOnClick),
    preferredVideoQuality: pickOneOf(
      s.preferredVideoQuality,
      VIDEO_QUALITIES,
      DEFAULT_SETTINGS.preferredVideoQuality
    ),
    cookiesBrowser: pickOneOf(s.cookiesBrowser, COOKIES_BROWSERS, "none"),
  };
}

function loadLocalSettings() {
  return new Promise((resolve) => {
    chrome.storage.local.get(
      { [SETTINGS_STORAGE_KEY]: null, [SETTINGS_DIRTY_KEY]: false },
      (res) => {
        const raw = res[SETTINGS_STORAGE_KEY];
        resolve({
          settings: raw ? normalizeSettings(raw) : null,
          dirty: res[SETTINGS_DIRTY_KEY] === true,
        });
      }
    );
  });
}

function saveLocalSettings(settings, dirty) {
  return new Promise((resolve) => {
    chrome.storage.local.set(
      {
        [SETTINGS_STORAGE_KEY]: normalizeSettings(settings),
        [SETTINGS_DIRTY_KEY]: Boolean(dirty),
      },
      () => resolve()
    );
  });
}

// Alleen de download-acties blokkeren. De velden onder "App-instellingen"
// bewust niet: die horen altijd bewerkbaar te zijn, ook tijdens een download
// en ook als de host/app onbereikbaar is. Anders bleef het hele blok voorgoed
// uitgeschakeld zodra een ping mislukte.
function setBusy(value) {
  busy = value;
  const hasUrl = Boolean(urlEl.value.trim());
  refreshBtn.disabled = value;
  sendBtn.disabled = value || !hasUrl;
  downloadBtn.disabled = value || !hasUrl;
  qualityEl.disabled = value || !formats.length;
  urlEl.disabled = value;
}

function fileNameOf(path) {
  return path.split(/[\\/]/).pop() || path;
}

function showDownloadedActions(path) {
  if (!path) return;
  lastDownloadedPath = path;
  openFolderBtn.textContent = "📁 " + fileNameOf(path);
  downloadedActionsEl.hidden = false;
}

function hideDownloadedActions() {
  lastDownloadedPath = null;
  downloadedActionsEl.hidden = true;
}

let playlistRestExpanded = false;

function openPathVia(cmd, path) {
  if (!path) return;
  sendNative({ cmd, path }).catch((e) => {
    setStatus(e.message || String(e), "error");
  });
}

function renderPlaylistRest(paths) {
  playlistRestEl.innerHTML = "";
  for (const path of paths) {
    const li = document.createElement("li");
    const name = document.createElement("span");
    name.className = "playlist-rest-name";
    name.textContent = fileNameOf(path);
    const playBtn = document.createElement("button");
    playBtn.type = "button";
    playBtn.className = "ghost";
    playBtn.textContent = "▶";
    playBtn.title = "Afspelen";
    playBtn.addEventListener("click", () => openPathVia("openFile", path));
    const folderBtn = document.createElement("button");
    folderBtn.type = "button";
    folderBtn.className = "ghost";
    folderBtn.textContent = "📁";
    folderBtn.title = "Map openen";
    folderBtn.addEventListener("click", () => openPathVia("openFolder", path));
    li.append(name, playBtn, folderBtn);
    playlistRestEl.appendChild(li);
  }
}

function showPlaylistGroup(state) {
  const paths = state.paths || [];
  const firstPath = state.firstPath || paths[0];
  if (!firstPath) return;
  playlistGroupEl.hidden = false;
  playlistSpinnerEl.hidden = Boolean(state.done);
  playlistFirstNameEl.textContent = fileNameOf(firstPath);
  playlistCountEl.textContent =
    paths.length === 1 ? "1 nummer" : `${paths.length} nummers`;
  renderPlaylistRest(paths.slice(1));
  playlistRestEl.hidden = !playlistRestExpanded;
  playlistToggleBtn.textContent = playlistRestExpanded ? "▴" : "▾";
  playlistToggleBtn.title = playlistRestExpanded
    ? "Playlist inklappen"
    : "Playlist uitklappen";
}

function hidePlaylistGroup() {
  playlistGroupEl.hidden = true;
  playlistRestExpanded = false;
}

playlistToggleBtn.addEventListener("click", () => {
  playlistRestExpanded = !playlistRestExpanded;
  playlistRestEl.hidden = !playlistRestExpanded;
  playlistToggleBtn.textContent = playlistRestExpanded ? "▴" : "▾";
  playlistToggleBtn.title = playlistRestExpanded
    ? "Playlist inklappen"
    : "Playlist uitklappen";
});

function formatSize(bytes) {
  if (bytes == null) return "onbekend";
  const mb = bytes / (1024 * 1024);
  if (mb >= 1024) return `${(mb / 1024).toFixed(2)} GB`;
  return `${mb.toFixed(1)} MB`;
}

// Opties:
//   baseline - de waarden zoals de velden er stonden voordat we de host
//              bevroegen; wijkt een veld daarvan af, dan heeft de gebruiker
//              het intussen zelf aangepast en laten we het met rust.
//   sent     - de patch die we zojuist naar de host stuurden.
// De host echoot bij elke opslag de genormaliseerde instellingen terug en
// laat een lege downloadDir bewust ongemoeid. Klakkeloos terugschrijven zette
// het pad tijdens het typen steeds terug naar de oude waarde -- het veld leek
// daardoor niet te bewerken.
function applySettings(settings, options) {
  if (!settings) return;
  const s = normalizeSettings(settings);
  const { baseline, sent } = options || {};
  const active = document.activeElement;
  const busyWith = (el, key, current) =>
    el === active || (baseline && baseline[key] !== current);

  const skipDir =
    busyWith(downloadDirEl, "downloadDir", downloadDirEl.value.trim()) ||
    // Leeg verstuurd betekent: de gebruiker is het pad aan het herschrijven.
    // De oude map terugzetten maakt het veld onbruikbaar.
    Boolean(sent && !sent.downloadDir);
  if (!skipDir) downloadDirEl.value = s.downloadDir;

  if (!busyWith(formatEl, "format", formatEl.value)) formatEl.value = s.format;
  if (!busyWith(playlistEl, "playlistMode", playlistEl.value)) {
    playlistEl.value = s.playlistMode;
  }
  if (!busyWith(autoDownloadEl, "autoDownloadOnClick", autoDownloadEl.checked)) {
    autoDownloadEl.checked = s.autoDownloadOnClick;
  }
  if (
    !busyWith(
      preferredQualityEl,
      "preferredVideoQuality",
      preferredQualityEl.value
    )
  ) {
    preferredQualityEl.value = s.preferredVideoQuality;
  }
  if (
    cookiesBrowserEl &&
    !busyWith(cookiesBrowserEl, "cookiesBrowser", cookiesBrowserEl.value)
  ) {
    cookiesBrowserEl.value = s.cookiesBrowser;
  }
  updateFormatUi();
}

function fillQualities(list) {
  formats = list || [];
  qualityEl.innerHTML = "";
  const empty = document.createElement("option");
  empty.value = "";
  empty.textContent = formats.length
    ? "Beste / later in app kiezen"
    : "Geen formats (optioneel)";
  qualityEl.appendChild(empty);
  for (const f of formats) {
    const opt = document.createElement("option");
    opt.value = f.formatId;
    opt.textContent = `${f.label} · ${f.ext} · ${formatSize(f.filesize)}${
      f.hasAudio ? "" : " · +audio"
    }`;
    qualityEl.appendChild(opt);
  }
  qualityEl.disabled = busy || !formats.length;
}

function updateFormatUi() {
  const isMp3 = formatEl.value === "mp3";
  // [hidden] + CSS !important: anders wint .row { display:flex } van het
  // native hidden-gedrag en blijft de kwaliteitsrij zichtbaar bij MP3.
  if (qualityRow) qualityRow.hidden = isMp3;
  if (qualityField) qualityField.hidden = isMp3;
  if (preferredQualityRow) preferredQualityRow.hidden = isMp3;
  if (refreshBtn) refreshBtn.hidden = isMp3;
  audioOnlyEl.checked = isMp3;
}

function chosenFormatId() {
  if (formatEl.value === "mp3") return undefined;
  const chosen = formats.find((f) => f.formatId === qualityEl.value);
  if (!chosen) return undefined;
  return chosen.hasAudio
    ? chosen.formatId
    : `${chosen.formatId}+bestaudio/best`;
}

function hasNativeMessaging() {
  return typeof chrome.runtime.connectNative === "function";
}

/**
 * @param {object} message
 * @param {(msg: object) => void} [onMessage]
 * @returns {Promise<object>}
 */
function sendNative(message, onMessage) {
  return new Promise((resolve, reject) => {
    if (!hasNativeMessaging()) {
      reject(
        new Error(
          "Native messaging niet beschikbaar (Firefox Android: gebruik Naar App)."
        )
      );
      return;
    }
    let port;
    try {
      port = chrome.runtime.connectNative(HOST_NAME);
    } catch (e) {
      reject(
        new Error(
          "Native host niet bereikbaar. Run scripts/install-native-host.ps1."
        )
      );
      return;
    }

    let settled = false;
    const finish = (fn, value) => {
      if (settled) return;
      settled = true;
      try {
        port.disconnect();
      } catch (_) {}
      // Een eerdere mislukte ping kan de "app niet gevonden"-banner
      // hebben getoond; die bleef daarna voor altijd staan, ook nadat
      // latere aanroepen (bv. een handmatige download) prima werkten.
      // Elke geslaagde aanroep ruimt 'm daarom op.
      if (fn === resolve) showGithubLink(false);
      fn(value);
    };

    port.onMessage.addListener((msg) => {
      if (onMessage) onMessage(msg);
      if (msg && msg.done) {
        if (msg.ok === false) {
          finish(reject, new Error(msg.error || "Mislukt"));
        } else {
          finish(resolve, msg);
        }
        return;
      }
      if (
        message.cmd !== "download" &&
        msg &&
        (msg.ok === true || msg.ok === false)
      ) {
        if (msg.ok === false) {
          finish(reject, new Error(msg.error || "Fout"));
        } else {
          finish(resolve, msg);
        }
      }
    });

    port.onDisconnect.addListener(() => {
      const err = chrome.runtime.lastError?.message;
      if (!settled) {
        finish(
          reject,
          new Error(
            err ||
              "Verbinding verbroken. Is de native host geïnstalleerd?"
          )
        );
      }
    });

    port.postMessage(message);
  });
}

function isTikTokUrl(url) {
  try {
    return /(^|\.)tiktok\.com$/i.test(new URL(url).hostname);
  } catch (_) {
    return false;
  }
}

function isTikTokVideoUrl(url) {
  return (
    /\/@[^/?#]+\/(?:video|photo)\/\d+/i.test(url || "") ||
    /\/embed\/(?:video|photo)\/\d+/i.test(url || "")
  );
}

/** Feed/home-URL’s zijn geen downloadbare video — blokkeer vóór yt-dlp. */
function tiktokFeedBlockReason(url) {
  if (!isTikTokUrl(url)) return null;
  if (isTikTokVideoUrl(url)) return null;
  return "Geen TikTok-video gevonden (alleen feed-URL). Vernieuw de TikTok-tab, speel een video af, open de extentie opnieuw.";
}

// TikTok For You: tab-URL is vaak alleen tiktok.com/ — content script
// reconstrueert de canonieke /@user/video/id-link van de zichtbare video.
async function resolveTikTokDownloadUrl(tab) {
  if (!tab?.id) {
    debugLog("TikTok resolve: geen tab.id");
    return { url: null, debug: null };
  }

  const ask = async (label) => {
    debugLog(`TikTok ask (${label}): tabs.sendMessage…`);
    try {
      const res = await chrome.tabs.sendMessage(tab.id, {
        type: "getDownloadUrl",
        debug: true,
      });
      debugLog(`TikTok ask (${label}): antwoord`, res);
      return res || null;
    } catch (e) {
      debugLog(`TikTok ask (${label}): MISLUKT`, {
        message: (e && e.message) || String(e),
      });
      return null;
    }
  };

  let res = await ask("eerste poging");
  if (res?.url) return { url: res.url, debug: res.debug || null };

  if (!chrome.scripting?.executeScript) {
    debugLog("TikTok resolve: chrome.scripting ontbreekt — stop");
    return { url: null, debug: res?.debug || null };
  }

  try {
    debugLog("TikTok resolve: inject content/tiktok.js…");
    await chrome.scripting.executeScript({
      target: { tabId: tab.id },
      files: ["content/tiktok.js"],
    });
    debugLog("TikTok resolve: inject OK");
  } catch (e) {
    debugLog("TikTok resolve: inject MISLUKT", {
      message: (e && e.message) || String(e),
    });
  }

  res = await ask("na inject");
  if (res?.url) return { url: res.url, debug: res.debug || null };

  try {
    debugLog("TikTok resolve: executeScript func __downoaderDetectTikTokDebug…");
    const [{ result }] = await chrome.scripting.executeScript({
      target: { tabId: tab.id },
      func: () =>
        typeof globalThis.__downoaderDetectTikTokDebug === "function"
          ? globalThis.__downoaderDetectTikTokDebug()
          : typeof globalThis.__downoaderDetectTikTok === "function"
            ? { url: globalThis.__downoaderDetectTikTok(), debug: null }
            : { url: null, debug: { error: "geen detect-functie op pagina" } },
    });
    debugLog("TikTok resolve: func resultaat", result);
    if (result?.url) return { url: result.url, debug: result.debug || null };
    return { url: null, debug: result?.debug || null };
  } catch (e) {
    debugLog("TikTok resolve: func MISLUKT", {
      message: (e && e.message) || String(e),
    });
    return { url: null, debug: null };
  }
}

async function loadActiveTabUrl() {
  debugLog("=== loadActiveTabUrl ===");
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  debugLog("Actieve tab", {
    id: tab?.id,
    url: tab?.url,
    title: tab?.title,
    status: tab?.status,
  });
  if (!tab?.url || !/^https?:/i.test(tab.url)) {
    debugLog("Geen bruikbare http(s) tab-URL");
    return;
  }

  let url = tab.url;
  if (isTikTokUrl(tab.url)) {
    debugLog("TikTok-host herkend — detectie starten");
    const resolved = await resolveTikTokDownloadUrl(tab);
    if (resolved.url) {
      url = resolved.url;
      debugLog("TikTok-video URL gekozen", url);
    } else {
      debugLog("TikTok-detectie gaf geen video-URL — tab-URL blijft staan");
    }
  } else {
    debugLog("Geen TikTok-tab — tab-URL gebruiken");
  }
  urlEl.value = url;
  debugLog("URL-veld gezet", urlEl.value);
}

function currentSettingsPatch() {
  return normalizeSettings({
    downloadDir: downloadDirEl.value.trim(),
    format: formatEl.value,
    playlistMode: playlistEl.value,
    autoDownloadOnClick: autoDownloadEl.checked,
    preferredVideoQuality: preferredQualityEl.value,
    cookiesBrowser: cookiesBrowserEl ? cookiesBrowserEl.value : "none",
  });
}

// Toont meteen de laatst bekende waarden, ook zonder host. Daarna is de host
// (= de app) leidend, behalve als er nog niet-doorgezette wijzigingen
// klaarstaan: die winnen, anders draait de app ze stilletjes terug.
async function loadSettings() {
  const local = await loadLocalSettings();
  // Zonder lokale kopie expliciet de standaardwaarden zetten: de selects
  // zouden anders op hun eerste <option> blijven staan (bv. kwaliteit
  // "Altijd vragen" i.p.v. de 1080p die de app als standaard hanteert).
  applySettings(local.settings || DEFAULT_SETTINGS);
  settingsLoaded = true;

  if (!hostReady) {
    if (local.dirty) {
      setSettingsStatus(
        "Lokaal opgeslagen. Gaat naar de app zodra die bereikbaar is."
      );
    }
    return;
  }

  if (local.dirty && local.settings) {
    if (await pushSettingsToHost(local.settings)) return;
  }

  try {
    const res = await sendNative({ cmd: "getSettings" });
    applySettings(res.settings, {
      baseline: local.settings || DEFAULT_SETTINGS,
    });
    await saveLocalSettings(res.settings, false);
    setSettingsStatus("");
  } catch (e) {
    debugLog("getSettings mislukt", (e && e.message) || String(e));
    setSettingsStatus(
      "Kon de app-instellingen niet lezen; lokale waarden getoond.",
      "error"
    );
  }
}

// Enige plek die naar de host schrijft. De host legt het vast in dezelfde
// shared_preferences.json als de app en duwt de nieuwe waarden via de inbox
// naar een draaiende app -- zo veranderen extentie en app altijd samen.
async function pushSettingsToHost(settings) {
  try {
    const res = await sendNative({ cmd: "setSettings", settings });
    const saved = res && res.settings ? res.settings : settings;
    applySettings(saved, { baseline: settings, sent: settings });
    await saveLocalSettings(saved, false);
    setSettingsStatus(
      settings.downloadDir
        ? "Opgeslagen - ook in de DDownloader-app."
        : "Opgeslagen. Downloadmap is leeg, dus de app houdt de huidige map aan.",
      "ok"
    );
    return true;
  } catch (e) {
    await saveLocalSettings(settings, true);
    setSettingsStatus(
      `Lokaal opgeslagen, app niet bijgewerkt (${
        (e && e.message) || String(e)
      }). Bij de volgende keer openen proberen we het opnieuw.`,
      "error"
    );
    return false;
  }
}

function scheduleSaveSettings() {
  if (!settingsLoaded) return;
  pendingSettingsChange = true;
  clearTimeout(saveTimer);
  saveTimer = setTimeout(() => {
    autoSaveSettings().catch(() => {});
  }, 350);
}

async function autoSaveSettings() {
  if (!settingsLoaded) return;
  if (saveInFlight) {
    // Niet de timer opnieuw starten (dat kon tijdens typen eindeloos
    // uitstellen); een keer natrappen zodra de lopende save klaar is.
    saveQueued = true;
    return;
  }
  saveInFlight = true;
  clearTimeout(saveTimer);
  try {
    const patch = currentSettingsPatch();
    // Altijd eerst lokaal vastleggen: valt de host weg, dan is de keuze van
    // de gebruiker niet verdwenen.
    await saveLocalSettings(patch, true);
    pendingSettingsChange = false;
    if (!hostReady) {
      setSettingsStatus(
        "Lokaal opgeslagen. Gaat naar de app zodra die bereikbaar is."
      );
      return;
    }
    await pushSettingsToHost(patch);
  } finally {
    saveInFlight = false;
    if (saveQueued) {
      saveQueued = false;
      scheduleSaveSettings();
    }
  }
}

async function resetSettings() {
  applySettings(DEFAULT_SETTINGS);
  clearTimeout(saveTimer);
  pendingSettingsChange = true;
  await autoSaveSettings();
}

// Op Android is er geen native messaging, dus reizen de instellingen mee in
// de deeplink; de app slaat ze daar op. Alleen waarden die op een telefoon
// betekenis hebben: een Windows-downloadmap of --cookies-from-browser zouden
// de app daar juist kapot zetten.
function androidAppLink(url, format) {
  const u = new URL("downoader://download");
  u.searchParams.set("url", url);
  if (format) u.searchParams.set("format", format);
  const s = currentSettingsPatch();
  u.searchParams.set("playlistMode", s.playlistMode);
  u.searchParams.set("preferredVideoQuality", s.preferredVideoQuality);
  return u.href;
}

async function openInAndroidApp(url, format) {
  const href = androidAppLink(url, format);
  try {
    if (chrome.tabs?.create) {
      await chrome.tabs.create({ url: href });
      return true;
    }
  } catch (_) {}
  try {
    window.open(href, "_blank");
    return true;
  } catch (_) {}
  return false;
}

async function refreshFormats() {
  const url = urlEl.value.trim();
  debugLog("refreshFormats", { url });
  if (!url) {
    setStatus("Geen URL.", "error");
    return;
  }
  const blocked = tiktokFeedBlockReason(url);
  if (blocked) {
    setStatus(blocked, "error");
    return;
  }
  setBusy(true);
  setStatus("Kwaliteiten ophalen…");
  try {
    const res = await sendNative({ cmd: "formats", url });
    fillQualities(res.formats || []);
    setStatus(
      formats.length ? `${formats.length} kwaliteiten.` : "Geen formats.",
      formats.length ? "ok" : "error"
    );
  } catch (e) {
    fillQualities([]);
    setStatus(e.message || String(e), "error");
  } finally {
    setBusy(false);
  }
}

async function sendToApp() {
  const url = urlEl.value.trim();
  debugLog("sendToApp", { url });
  if (!url) {
    setStatus("Geen URL.", "error");
    return;
  }
  const blocked = tiktokFeedBlockReason(url);
  if (blocked) {
    setStatus(blocked, "error");
    return;
  }
  if (isAndroid || !hasNativeMessaging()) {
    setBusy(true);
    try {
      const opened = await openInAndroidApp(url, formatEl.value);
      setStatus(
        opened
          ? "DDownloader-app geopend met deze URL."
          : "Kon de Android-app niet openen. Installeer DDownloader.",
        opened ? "ok" : "error"
      );
    } finally {
      setBusy(false);
    }
    return;
  }
  setBusy(true);
  progressEl.hidden = true;
  setStatus("Doorsturen naar Windows-app…");
  try {
    const shared = currentSettingsPatch();
    const res = await sendNative({
      cmd: "sendToApp",
      url,
      format: formatEl.value,
      formatId: chosenFormatId(),
      downloadDir: shared.downloadDir,
      playlistMode: shared.playlistMode,
      preferredVideoQuality: shared.preferredVideoQuality,
      cookiesBrowser: shared.cookiesBrowser,
    });
    setStatus(
      res.launched
        ? "Naar app gestuurd (app draait of is gestart)."
        : "In wachtrij gezet. Open de Windows-app één keer, daarna opnieuw.",
      res.launched ? "ok" : "error"
    );
  } catch (e) {
    setStatus(e.message || String(e), "error");
  } finally {
    setBusy(false);
  }
}

// De download draait in de background service worker (niet hier in de
// popup) zodat hij doorloopt als deze popup sluit — zie background.js.
// Voortgang komt binnen via chrome.runtime.onMessage; hieronder passen we
// dat toe op de UI, ongeacht of de download net gestart is of al liep
// toen deze popup werd geopend.
let downloadListenerAttached = false;

function attachDownloadListener() {
  if (downloadListenerAttached) return;
  downloadListenerAttached = true;
  chrome.runtime.onMessage.addListener((msg) => {
    if (msg?.type === "downloadUpdate" || msg?.type === "downloadDone") {
      applyDownloadState(msg.state);
    }
  });
}

function applyDownloadState(state) {
  if (!state) return;
  progressEl.hidden = false;
  progressEl.value = state.progress || 0;
  if (state.statusLine) {
    setStatus(
      typeof state.progress === "number" && !state.done
        ? `Downloaden… ${state.progress.toFixed(1)}%`
        : state.statusLine
    );
  }
  if (state.isPlaylist && (state.paths || []).length) {
    showPlaylistGroup(state);
  }
  if (state.done) {
    setBusy(false);
    if (state.ok) {
      progressEl.value = 100;
      progressEl.hidden = true;
      setStatus(state.path ? `Klaar: ${fileNameOf(state.path)}` : "Download voltooid.", "ok");
      if (state.isPlaylist && (state.paths || []).length) {
        showPlaylistGroup(state);
      } else if (state.path) {
        showDownloadedActions(state.path);
      } else {
        // Pad soms pas later bekend — probeer via checkDownloaded.
        const url = urlEl.value.trim();
        if (url) {
          chrome.runtime
            .sendMessage({ type: "checkDownloaded", url })
            .then((existing) => {
              if (!existing?.downloaded) return;
              if (existing.isPlaylist && (existing.paths || []).length) {
                showPlaylistGroup({ ...existing, done: true });
              } else if (existing.path) {
                showDownloadedActions(existing.path);
              }
            })
            .catch(() => {});
        }
      }
    } else {
      debugLog("downloadDone FAIL", state);
      setStatus(state.error || "Download mislukt", "error");
    }
  }
}

async function downloadHere({ auto = false } = {}) {
  const url = urlEl.value.trim();
  debugLog("downloadHere", { url, auto });
  if (!url) {
    setStatus("Geen URL op deze tab.", "error");
    return;
  }
  if (!/^https?:/i.test(url)) {
    setStatus("Alleen http(s)-URL’s kunnen gedownload worden.", "error");
    return;
  }
  const blocked = tiktokFeedBlockReason(url);
  if (blocked) {
    setStatus(blocked, "error");
    return;
  }
  if (isAndroid || !hasNativeMessaging()) {
    await sendToApp();
    return;
  }
  attachDownloadListener();
  setBusy(true);
  hideDownloadedActions();
  hidePlaylistGroup();
  progressEl.hidden = false;
  progressEl.value = 0;
  setStatus(
    auto
      ? "Icoon-klik: download gestart met app-instellingen…"
      : "Direct downloaden…"
  );
  // Gebruik altijd de exe-settings (zojuist geladen / in de velden).
  const format = formatEl.value || "mp4";
  const playlistMode = playlistEl.value || "ask";
  const formatId = auto ? undefined : chosenFormatId();
  let res;
  try {
    debugLog("startDirectDownload → background", {
      url,
      format,
      formatId,
      playlistMode,
    });
    res = await chrome.runtime.sendMessage({
      type: "startDirectDownload",
      payload: {
        url,
        format,
        formatId,
        isPlaylist: playlistMode === "playlist",
        outputDir: downloadDirEl.value.trim() || undefined,
      },
    });
    debugLog("startDirectDownload antwoord", res);
  } catch (e) {
    debugLog("startDirectDownload exception", {
      message: (e && e.message) || String(e),
    });
    setBusy(false);
    setStatus(e.message || String(e), "error");
    return;
  }
  if (!res || !res.started) {
    setBusy(false);
    const reason =
      res && res.reason === "already-running"
        ? "Er loopt al een download."
        : (res && res.reason) || "Kon download niet starten.";
    setStatus(reason, "error");
    return;
  }
  // Niet wachten op voltooiing: die komt via de listener hierboven binnen,
  // ook als deze popup inmiddels gesloten en heropend is.
}

formatEl.addEventListener("change", () => {
  updateFormatUi();
  scheduleSaveSettings();
});
audioOnlyEl.addEventListener("change", () => {
  formatEl.value = audioOnlyEl.checked ? "mp3" : "mp4";
  updateFormatUi();
  scheduleSaveSettings();
});
directDownloadEnabledEl.addEventListener("change", () => {
  applyDirectDownloadEnabled(directDownloadEnabledEl.checked);
  saveDirectDownloadEnabled(directDownloadEnabledEl.checked);
});
playlistEl.addEventListener("change", scheduleSaveSettings);
preferredQualityEl.addEventListener("change", scheduleSaveSettings);
autoDownloadEl.addEventListener("change", scheduleSaveSettings);
cookiesBrowserEl?.addEventListener("change", scheduleSaveSettings);
downloadDirEl.addEventListener("input", scheduleSaveSettings);
downloadDirEl.addEventListener("change", scheduleSaveSettings);
// Het pad is het enige vrije tekstveld: bij verlaten meteen wegschrijven in
// plaats van te wachten op de debounce, die bij het sluiten van de popup
// verdwijnt.
downloadDirEl.addEventListener("blur", () => {
  if (!pendingSettingsChange) return;
  autoSaveSettings().catch(() => {});
});
settingsResetBtn?.addEventListener("click", () => {
  resetSettings().catch(() => {});
});
// Popup dicht = pending debounce weg. De lokale kopie leggen we nog vast; de
// host krijgt hem bij de volgende opening via de dirty-vlag.
window.addEventListener("pagehide", () => {
  if (!settingsLoaded || !pendingSettingsChange) return;
  clearTimeout(saveTimer);
  saveLocalSettings(currentSettingsPatch(), true);
});
refreshBtn.addEventListener("click", refreshFormats);
sendBtn.addEventListener("click", sendToApp);
downloadBtn.addEventListener("click", () => downloadHere({ auto: false }));
openFolderBtn.addEventListener("click", async () => {
  if (!lastDownloadedPath) return;
  try {
    await sendNative({ cmd: "openFolder", path: lastDownloadedPath });
  } catch (e) {
    setStatus(e.message || String(e), "error");
  }
});
playFileBtn.addEventListener("click", async () => {
  if (!lastDownloadedPath) return;
  try {
    await sendNative({ cmd: "openFile", path: lastDownloadedPath });
  } catch (e) {
    setStatus(e.message || String(e), "error");
  }
});
urlEl.addEventListener("input", () => {
  if (!busy) {
    sendBtn.disabled = !urlEl.value.trim();
    downloadBtn.disabled = !urlEl.value.trim();
  }
});

debugToggleBtn?.addEventListener("click", () => {
  const show = debugPanelEl.hidden;
  debugPanelEl.hidden = !show;
  debugToggleBtn.classList.toggle("active", show);
});

debugClearBtn?.addEventListener("click", () => {
  debugClear();
  debugLog("Log geleegd");
});

debugCopyBtn?.addEventListener("click", async () => {
  const text = debugLogEl?.textContent || "";
  try {
    await navigator.clipboard.writeText(text);
    setStatus("Debug-log gekopieerd.", "ok");
  } catch (e) {
    setStatus("Kopiëren mislukt: " + ((e && e.message) || String(e)), "error");
  }
});

debugRedetectBtn?.addEventListener("click", async () => {
  debugLog("=== handmatig opnieuw detecteren ===");
  setBusy(true);
  try {
    await loadActiveTabUrl();
    const url = urlEl.value.trim();
    if (isTikTokUrl(url) && !isTikTokVideoUrl(url)) {
      setStatus(
        "TikTok-feed: nog geen video-URL. Zie debug-log hieronder.",
        "error"
      );
    } else if (isTikTokVideoUrl(url)) {
      setStatus("TikTok-video gedetecteerd.", "ok");
    } else {
      setStatus("URL vernieuwd.", "ok");
    }
  } catch (e) {
    debugLog("Opnieuw detecteren mislukt", {
      message: (e && e.message) || String(e),
    });
    setStatus((e && e.message) || String(e), "error");
  } finally {
    setBusy(false);
  }
});

(async () => {
  debugLog("Popup open", {
    extensionVersion: chrome.runtime.getManifest?.()?.version,
  });
  await loadActiveTabUrl();
  try {
    const info = await chrome.runtime.getPlatformInfo();
    isAndroid = info?.os === "android";
  } catch (_) {
    isAndroid = false;
  }
  if (isAndroid) {
    // Het instellingenblok blijft staan en blijft bewerkbaar: het wordt
    // lokaal bewaard en gaat via de downoader://-link mee naar de app. Alleen
    // de opties die native messaging of een Windows-pad nodig hebben
    // verbergen we, die zouden daar toch niets doen.
    if (downloadDirRow) downloadDirRow.hidden = true;
    if (cookiesBrowserRow) cookiesBrowserRow.hidden = true;
    if (autoDownloadRow) autoDownloadRow.hidden = true;
    if (directDownloadRow) directDownloadRow.hidden = true;
    downloadBtn.hidden = true;
    sendBtn.textContent = "Naar App";
  }
  const directDownloadEnabled = await loadDirectDownloadEnabled();
  directDownloadEnabledEl.checked = directDownloadEnabled;
  applyDirectDownloadEnabled(!isAndroid && directDownloadEnabled);
  // Lokale kopie eerst tonen: ook als de host straks niet opneemt staan hier
  // de waarden die de gebruiker kent -- en kan hij ze meteen wijzigen.
  await loadSettings();
  setBusy(true);
  showGithubLink(false);
  try {
    if (isAndroid || !hasNativeMessaging()) {
      setBusy(false);
      setSettingsStatus(
        isAndroid
          ? "Instellingen gelden voor de extentie en gaan mee naar de app bij Naar App."
          : "Geen native messaging in deze browser - instellingen worden lokaal bewaard."
      );
      if (!urlEl.value.trim()) {
        setStatus("Geen downloadbare URL op deze tab.", "error");
      } else if (
        isTikTokUrl(urlEl.value) &&
        !isTikTokVideoUrl(urlEl.value)
      ) {
        setStatus(
          "TikTok-feed: scroll naar een video of open de video-pagina, daarna opnieuw proberen.",
          "error"
        );
      } else {
        setStatus("Klaar. Tik Naar App om in de DDownloader-app te openen.", "ok");
      }
      return;
    }
    // Een enkele mislukte/trage eerste ping (bv. door een antivirus-scan
    // op het net gestarte host-proces, of een korte cold-start-vertraging)
    // liet dit voorheen meteen "app niet gevonden" tonen. Eén retry na
    // een korte pauze vangt dat soort transiente hikjes op zonder een
    // echt kapotte installatie te maskeren (die faalt dan gewoon weer).
    let ping = null;
    try {
      ping = await sendNative({ cmd: "ping" });
    } catch (firstError) {
      if (!isHostMissingError(firstError)) throw firstError;
      await new Promise((r) => setTimeout(r, 400));
      ping = await sendNative({ cmd: "ping" });
    }
    debugLog("Native host ping", ping);
    hostReady = true;
    // Tweede ronde, nu mét host: pending wijzigingen doorduwen naar de app,
    // anders de app-waarden overnemen.
    await loadSettings();

    const hostVer = ping?.version ? `host v${ping.version}` : "host";
    const hostPathHint = ping?.hostPath
      ? String(ping.hostPath).includes("Program Files")
        ? " (Program Files — mogelijk oud)"
        : " (Desktop)"
      : "";
    const extVer = chrome.runtime.getManifest?.()?.version || "?";

    // Een download loopt in de background worker door na het sluiten van
    // de popup (zie background.js) — bij heropenen tonen we die
    // voortgang in plaats van een tweede download te starten.
    const dl = await chrome.runtime.sendMessage({ type: "getDownloadState" });
    if (dl?.active) {
      attachDownloadListener();
      setBusy(true);
      applyDownloadState(dl.state);
      return;
    }

    setBusy(false);

    // Al eerder via deze extentie gedownload? Dan niet blind opnieuw
    // downloaden (vooral vervelend bij icoon-klik-auto-download) — en
    // de Afspelen/Open-map-knoppen werken meteen weer, ook na een reload
    // van de pagina of het heropenen van deze popup.
    const existing = await chrome.runtime.sendMessage({
      type: "checkDownloaded",
      url: urlEl.value.trim(),
    });
    if (existing?.downloaded) {
      if (existing.isPlaylist && (existing.paths || []).length) {
        showPlaylistGroup({ ...existing, done: true });
      } else {
        showDownloadedActions(existing.path);
      }
      setStatus(`Al gedownload: ${existing.path}`, "ok");
      return;
    }

    // Icoon geklikt → popup opent. Alleen meteen downloaden als de
    // gebruiker dat expliciet heeft aangezet (staat standaard uit) EN
    // "Direct Downloaden" niet is uitgeschakeld.
    if (autoDownloadEl.checked && directDownloadEnabled && urlEl.value.trim()) {
      await downloadHere({ auto: true });
    } else if (!urlEl.value.trim()) {
      setStatus("Verbonden. Geen downloadbare URL op deze tab.", "error");
    } else if (
      isTikTokUrl(urlEl.value) &&
      !isTikTokVideoUrl(urlEl.value)
    ) {
      setStatus(
        "TikTok-feed: scroll naar een video of open de video-pagina, daarna opnieuw proberen.",
        "error"
      );
    } else {
      setStatus(
        isTikTokVideoUrl(urlEl.value)
          ? `Verbonden · extentie v${extVer} · ${hostVer}${hostPathHint}. TikTok-video gedetecteerd.`
          : `Verbonden · extentie v${extVer} · ${hostVer}${hostPathHint}.`,
        "ok"
      );
    }
  } catch (e) {
    if (isHostMissingError(e)) {
      // Onderliggende Chrome-foutmelding meesturen (i.p.v. alleen de
      // vriendelijke tekst) zodat een volgende mislukking meteen te
      // herleiden is i.p.v. opnieuw te moeten reproduceren/uitzoeken.
      const detail = e && e.message ? ` (${e.message})` : "";
      setStatus(
        `DDownloader-app/native host niet gevonden op dit apparaat.${detail}`,
        "error"
      );
      showGithubLink(true);
      setSettingsStatus(
        "App niet bereikbaar - instellingen worden lokaal bewaard en " +
          "doorgezet zodra de app er weer is."
      );
      // Zonder host werken de download-acties niet - die knoppen blijven
      // uitgeschakeld. De instellingen blijven wél bewerkbaar.
    } else {
      setStatus(e.message || String(e), "error");
      setBusy(false);
    }
  }
})();
