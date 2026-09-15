const HOST_NAME = "com.downoader.host";

const urlEl = document.getElementById("url");
const formatEl = document.getElementById("format");
const playlistEl = document.getElementById("playlistMode");
const downloadDirEl = document.getElementById("downloadDir");
const qualityEl = document.getElementById("quality");
const qualityField = document.getElementById("qualityField");
const refreshBtn = document.getElementById("refresh");
const saveBtn = document.getElementById("saveSettings");
const sendBtn = document.getElementById("sendToApp");
const downloadBtn = document.getElementById("downloadHere");
const autoDownloadEl = document.getElementById("autoDownload");
const openFolderBtn = document.getElementById("openFolderBtn");
const playFileBtn = document.getElementById("playFileBtn");
const downloadedActionsEl = document.getElementById("downloadedActions");
const preferredQualityEl = document.getElementById("preferredQuality");
const githubLinkEl = document.getElementById("githubLink");
const audioOnlyEl = document.getElementById("audioOnly");
const directDownloadEnabledEl = document.getElementById("directDownloadEnabled");
const statusEl = document.getElementById("status");
const progressEl = document.getElementById("progress");

/** @type {Array<{formatId:string,label:string,ext:string,hasAudio:boolean,filesize?:number}>} */
let formats = [];
let busy = false;
let lastDownloadedPath = null;

function setStatus(text, kind = "") {
  statusEl.hidden = !text;
  statusEl.textContent = text || "";
  statusEl.className = "status" + (kind ? ` ${kind}` : "");
}

// Chrome/Edge geeft dit soort teksten als de native host niet geregistreerd
// is (host ontbreekt of yt-dlp/de Windows-app is nooit geïnstalleerd).
function isHostMissingError(e) {
  const m = ((e && e.message) || String(e)).toLowerCase();
  return (
    m.includes("native messaging host") ||
    m.includes("host niet bereikbaar") ||
    m.includes("verbinding verbroken")
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

function setBusy(value) {
  busy = value;
  const hasUrl = Boolean(urlEl.value.trim());
  refreshBtn.disabled = value;
  saveBtn.disabled = value;
  sendBtn.disabled = value || !hasUrl;
  downloadBtn.disabled = value || !hasUrl;
  formatEl.disabled = value;
  playlistEl.disabled = value;
  downloadDirEl.disabled = value;
  qualityEl.disabled = value || !formats.length;
  urlEl.disabled = value;
  autoDownloadEl.disabled = value;
  preferredQualityEl.disabled = value;
  audioOnlyEl.disabled = value;
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

function formatSize(bytes) {
  if (bytes == null) return "onbekend";
  const mb = bytes / (1024 * 1024);
  if (mb >= 1024) return `${(mb / 1024).toFixed(2)} GB`;
  return `${mb.toFixed(1)} MB`;
}

function applySettings(settings) {
  if (!settings) return;
  downloadDirEl.value = settings.downloadDir || "";
  formatEl.value = settings.format === "mp3" ? "mp3" : "mp4";
  playlistEl.value = settings.playlistMode || "ask";
  autoDownloadEl.checked = Boolean(settings.autoDownloadOnClick);
  preferredQualityEl.value = settings.preferredVideoQuality || "p1080";
  updateHeaderHint();
  updateFormatUi();
}

function updateHeaderHint() {
  const hintEl = document.querySelector(".header-hint");
  if (!hintEl) return;
  hintEl.textContent = autoDownloadEl.checked
    ? "Icoon = meteen downloaden (app-instellingen)"
    : "Icoon opent dit venster";
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
  qualityField.style.visibility = isMp3 ? "hidden" : "visible";
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

/**
 * @param {object} message
 * @param {(msg: object) => void} [onMessage]
 * @returns {Promise<object>}
 */
function sendNative(message, onMessage) {
  return new Promise((resolve, reject) => {
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

async function loadActiveTabUrl() {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  if (tab?.url && /^https?:/i.test(tab.url)) {
    urlEl.value = tab.url;
  }
}

async function loadSettings() {
  const res = await sendNative({ cmd: "getSettings" });
  applySettings(res.settings);
}

async function saveSettings() {
  setBusy(true);
  setStatus("Instellingen opslaan…");
  try {
    const res = await sendNative({
      cmd: "setSettings",
      settings: {
        downloadDir: downloadDirEl.value.trim(),
        format: formatEl.value,
        playlistMode: playlistEl.value,
        autoDownloadOnClick: autoDownloadEl.checked,
        preferredVideoQuality: preferredQualityEl.value,
      },
    });
    applySettings(res.settings);
    setStatus("Opgeslagen in app-instellingen.", "ok");
  } catch (e) {
    setStatus(e.message || String(e), "error");
  } finally {
    setBusy(false);
  }
}

async function refreshFormats() {
  const url = urlEl.value.trim();
  if (!url) {
    setStatus("Geen URL.", "error");
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
  if (!url) {
    setStatus("Geen URL.", "error");
    return;
  }
  setBusy(true);
  progressEl.hidden = true;
  setStatus("Doorsturen naar Windows-app…");
  try {
    const res = await sendNative({
      cmd: "sendToApp",
      url,
      format: formatEl.value,
      formatId: chosenFormatId(),
      downloadDir: downloadDirEl.value.trim(),
      playlistMode: playlistEl.value,
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

async function downloadHere({ auto = false } = {}) {
  const url = urlEl.value.trim();
  if (!url) {
    setStatus("Geen URL op deze tab.", "error");
    return;
  }
  if (!/^https?:/i.test(url)) {
    setStatus("Alleen http(s)-URL’s kunnen gedownload worden.", "error");
    return;
  }
  setBusy(true);
  hideDownloadedActions();
  progressEl.hidden = false;
  progressEl.value = 0;
  setStatus(
    auto
      ? "Icoon-klik: download gestart met app-instellingen…"
      : "Direct downloaden…"
  );
  try {
    // Gebruik altijd de exe-settings (zojuist geladen / in de velden).
    const format = formatEl.value || "mp4";
    const playlistMode = playlistEl.value || "ask";
    const formatId = auto ? undefined : chosenFormatId();
    const res = await sendNative(
      {
        cmd: "download",
        url,
        format,
        formatId,
        isPlaylist: playlistMode === "playlist",
        outputDir: downloadDirEl.value.trim() || undefined,
      },
      (msg) => {
        if (typeof msg.progress === "number") {
          progressEl.value = msg.progress;
          setStatus(`Downloaden… ${msg.progress.toFixed(1)}%`);
        } else if (msg.line) {
          setStatus(msg.line);
        }
      }
    );
    progressEl.value = 100;
    setStatus(res.path ? `Klaar: ${res.path}` : "Download voltooid.", "ok");
    if (res.path) showDownloadedActions(res.path);
  } catch (e) {
    setStatus(e.message || String(e), "error");
  } finally {
    setBusy(false);
  }
}

formatEl.addEventListener("change", updateFormatUi);
audioOnlyEl.addEventListener("change", () => {
  formatEl.value = audioOnlyEl.checked ? "mp3" : "mp4";
  updateFormatUi();
});
directDownloadEnabledEl.addEventListener("change", () => {
  applyDirectDownloadEnabled(directDownloadEnabledEl.checked);
  saveDirectDownloadEnabled(directDownloadEnabledEl.checked);
});
autoDownloadEl.addEventListener("change", updateHeaderHint);
refreshBtn.addEventListener("click", refreshFormats);
saveBtn.addEventListener("click", saveSettings);
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

(async () => {
  await loadActiveTabUrl();
  const directDownloadEnabled = await loadDirectDownloadEnabled();
  directDownloadEnabledEl.checked = directDownloadEnabled;
  applyDirectDownloadEnabled(directDownloadEnabled);
  updateFormatUi();
  setBusy(true);
  showGithubLink(false);
  try {
    await sendNative({ cmd: "ping" });
    await loadSettings();
    setBusy(false);
    // Icoon geklikt → popup opent. Alleen meteen downloaden als de
    // gebruiker dat expliciet heeft aangezet (staat standaard uit) EN
    // "Direct Downloaden" niet is uitgeschakeld.
    if (autoDownloadEl.checked && directDownloadEnabled && urlEl.value.trim()) {
      await downloadHere({ auto: true });
    } else if (!urlEl.value.trim()) {
      setStatus("Verbonden. Geen downloadbare URL op deze tab.", "error");
    } else {
      setStatus("Verbonden.", "ok");
    }
  } catch (e) {
    if (isHostMissingError(e)) {
      setStatus(
        "Downloader-app/native host niet gevonden op dit apparaat.",
        "error"
      );
      showGithubLink(true);
      // Zonder host werkt niets hier — knoppen uitgeschakeld laten.
    } else {
      setStatus(e.message || String(e), "error");
      setBusy(false);
    }
  }
})();
