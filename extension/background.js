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
    progress: state.progress,
    statusLine: state.statusLine,
    done: state.done,
    ok: state.ok,
    error: state.error,
    path: state.path,
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

function startDirectDownload(payload) {
  if (activeDownload && !activeDownload.done) {
    return { started: false, reason: "already-running" };
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
    progress: 0,
    statusLine: "",
    done: false,
    ok: null,
    error: null,
    path: null,
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
    try {
      port.disconnect();
    } catch (_) {}
  };

  port.onMessage.addListener((msg) => {
    if (!msg) return;
    if (typeof msg.progress === "number") state.progress = msg.progress;
    if (msg.line) state.statusLine = msg.line;
    if (msg.path) state.path = msg.path;
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
  return false;
});
