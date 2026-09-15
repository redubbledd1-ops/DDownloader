const HOST_NAME = "com.downoader.host";

chrome.runtime.onInstalled.addListener(() => {
  chrome.storage.local.get({ format: "mp4" }, () => {});
});

// Popup praat rechtstreeks met connectNative; background houdt alleen
// de host-naam beschikbaar voor andere scripts.
chrome.runtime.onMessage.addListener((msg, _sender, sendResponse) => {
  if (msg?.type === "getHostName") {
    sendResponse({ hostName: HOST_NAME });
    return false;
  }
});
