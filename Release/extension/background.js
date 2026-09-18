const HOST_NAME = "com.downoader.host";

chrome.runtime.onInstalled.addListener(() => {
  chrome.storage.local.get({ format: "mp4" }, () => {});
});

// Directe downloads (vooral playlists) duren soms lang. Ze eerst via de
// popup's eigen native-messaging-verbinding laten lopen betekende dat
// Chrome het host-proces meteen kilde zodra de popup sloot — de download
// stopte dan halverwege. Door de verbinding hier in de service worker te
// openen (i.p.v. in popup.js) blijft de download doorlopen ook als de
// popup dicht is; de service worker blijft actief zolang de native-
// messaging-poort openstaat.
let activeDownload = null;

function publicState(state) {
  return {
    url: state.url,
    isPlaylist: state.isPlaylist,
    progress: state.progress,
    statusLine: state.statusLine,
    done: state.done,
    ok: state.ok,
    error: state.error,
    path: state.path,
    firstPath: state.firstPath,
    paths: state.paths,
  };
}

function broadcast(message) {
  // Zonder open popup is er geen ontvanger — sendMessage verwerpt dan
  // stilletjes een promise; dat negeren we bewust.
  chrome.runtime.sendMessage(message).catch(() => {});
}

function notify(title, message) {
  try {
    chrome.notifications.create({
      type: "basic",
      iconUrl: "icons/icon128.png",
      title,
      message: message || "",
    });
  } catch (_) {}
}

const DOWNLOADED_STORAGE_KEY = "downloadedByUrl";
const MAX_DOWNLOADED_ENTRIES = 300;

// Onthoudt welk bestand bij welke URL hoort, zodat de popup na een reload
// of heropenen kan zien "dit staat al gedownload" i.p.v. blind opnieuw te
// downloaden en om de Afspelen/Open-map-knoppen dan meteen te laten werken.
async function recordDownloaded(url, entry) {
  if (!url) return;
  const stored = await chrome.storage.local.get(DOWNLOADED_STORAGE_KEY);
  const map = stored[DOWNLOADED_STORAGE_KEY] || {};
  map[url] = { ...entry, ts: Date.now() };
  const keys = Object.keys(map);
  if (keys.length > MAX_DOWNLOADED_ENTRIES) {
    keys
      .sort((a, b) => (map[a].ts || 0) - (map[b].ts || 0))
      .slice(0, keys.length - MAX_DOWNLOADED_ENTRIES)
      .forEach((k) => delete map[k]);
  }
  await chrome.storage.local.set({ [DOWNLOADED_STORAGE_KEY]: map });
}

function hasNativeMessaging() {
  return typeof chrome.runtime.connectNative === "function";
}

function startDirectDownload(payload) {
  if (activeDownload && !activeDownload.done) {
    return { started: false, reason: "already-running" };
  }
  if (!hasNativeMessaging()) {
    return { started: false, reason: "native-messaging-unavailable" };
  }

  let port;
  try {
    port = chrome.runtime.connectNative(HOST_NAME);
  } catch (e) {
    return { started: false, reason: e?.message || String(e) };
  }

  const state = {
    port,
    url: payload.url,
    format: payload.format,
    isPlaylist: payload.isPlaylist,
    progress: 0,
    statusLine: "",
    done: false,
    ok: null,
    error: null,
    path: null,
    firstPath: null,
    paths: [],
  };
  activeDownload = state;

  const finishOnce = (ok, error) => {
    if (state.done) return;
    state.done = true;
    state.ok = ok;
    state.error = error || null;
    broadcast({ type: "downloadDone", state: publicState(state) });
    notify(
      ok ? "Download voltooid" : "Download mislukt",
      ok ? state.path || state.url : state.error || "Onbekende fout"
    );
    if (ok && state.path) {
      recordDownloaded(state.url, {
        path: state.path,
        format: state.format,
        isPlaylist: state.isPlaylist,
        firstPath: state.firstPath,
        paths: state.paths,
      });
    }
    try {
      port.disconnect();
    } catch (_) {}
  };

  port.onMessage.addListener((msg) => {
    if (!msg) return;
    if (typeof msg.progress === "number") state.progress = msg.progress;
    if (msg.line) state.statusLine = msg.line;
    if (msg.path) {
      state.path = msg.path;
      if (!state.firstPath) state.firstPath = msg.path;
      if (!state.paths.includes(msg.path)) state.paths.push(msg.path);
    }
    if (msg.done) {
      finishOnce(msg.ok !== false, msg.ok === false ? msg.error : null);
      return;
    }
    broadcast({ type: "downloadUpdate", state: publicState(state) });
  });

  port.onDisconnect.addListener(() => {
    finishOnce(false, chrome.runtime.lastError?.message || "Verbinding verbroken.");
  });

  port.postMessage({
    cmd: "download",
    url: payload.url,
    format: payload.format,
    formatId: payload.formatId,
    isPlaylist: payload.isPlaylist,
    outputDir: payload.outputDir,
  });

  return { started: true };
}

// Vraagt de host om te bevestigen dat een eerder gedownload bestand nog
// bestaat; als het weg is (verwijderd/verplaatst) wissen we de historie
// zodat de popup niet blijft beweren dat het er nog staat.
function checkFileExists(path) {
  return new Promise((resolve) => {
    if (!hasNativeMessaging()) {
      resolve(null);
      return;
    }
    let port;
    try {
      port = chrome.runtime.connectNative(HOST_NAME);
    } catch (_) {
      resolve(null);
      return;
    }
    let settled = false;
    const done = (value) => {
      if (settled) return;
      settled = true;
      try {
        port.disconnect();
      } catch (_) {}
      resolve(value);
    };
    port.onMessage.addListener((msg) => {
      if (msg && typeof msg.exists === "boolean") done(msg.exists);
    });
    port.onDisconnect.addListener(() => done(null));
    port.postMessage({ cmd: "checkFile", path });
  });
}

async function checkDownloaded(url) {
  if (!url) return { downloaded: false };
  const stored = await chrome.storage.local.get(DOWNLOADED_STORAGE_KEY);
  const map = stored[DOWNLOADED_STORAGE_KEY] || {};
  const entry = map[url];
  if (!entry) return { downloaded: false };

  const exists = await checkFileExists(entry.path);
  if (exists === false) {
    delete map[url];
    await chrome.storage.local.set({ [DOWNLOADED_STORAGE_KEY]: map });
    return { downloaded: false };
  }
  // exists === null betekent "kon niet checken" (host niet bereikbaar) —
  // dan gaan we op de historie af i.p.v. de gebruiker blind te laten
  // denken dat er niets staat.
  return { downloaded: true, ...entry };
}

chrome.runtime.onMessage.addListener((msg, _sender, sendResponse) => {
  if (msg?.type === "getHostName") {
    sendResponse({ hostName: HOST_NAME });
    return false;
  }
  if (msg?.type === "startDirectDownload") {
    sendResponse(startDirectDownload(msg.payload || {}));
    return false;
  }
  if (msg?.type === "getDownloadState") {
    sendResponse(
      activeDownload
        ? { active: !activeDownload.done, state: publicState(activeDownload) }
        : { active: false }
    );
    return false;
  }
  if (msg?.type === "checkDownloaded") {
    checkDownloaded(msg.url).then(sendResponse);
    return true; // async sendResponse
  }
  return false;
});
