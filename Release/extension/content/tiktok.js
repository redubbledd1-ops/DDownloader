// Detecteert de canonieke TikTok-video-URL op de huidige pagina.
// Op de For You-feed staat die vaak niet in de adresbalk — we zoeken hem
// in de DOM (spelende/zichtbare video) of in embedded page-data.
(function () {
  const VIDEO_PATH = /\/@([^/?#]+)\/video\/(\d+)/i;

  function canonicalize(href) {
    if (!href) return null;
    try {
      const u = new URL(href, location.href);
      const m = u.pathname.match(VIDEO_PATH);
      if (!m) return null;
      return (
        "https://www.tiktok.com/@" +
        decodeURIComponent(m[1]) +
        "/video/" +
        m[2]
      );
    } catch (_) {
      return null;
    }
  }

  function fromLocation() {
    return canonicalize(location.href);
  }

  function fromCanonicalLink() {
    const el = document.querySelector('link[rel="canonical"]');
    return canonicalize(el && el.href);
  }

  function fromUniversalData() {
    const el = document.querySelector("#__UNIVERSAL_DATA_FOR_REHYDRATION__");
    if (!el || !el.textContent) return null;
    try {
      const data = JSON.parse(el.textContent);
      const scope = data.__DEFAULT_SCOPE__ || {};
      const detail =
        scope["webapp.video-detail"] &&
        scope["webapp.video-detail"].itemInfo &&
        scope["webapp.video-detail"].itemInfo.itemStruct;
      if (detail && detail.id && detail.author && detail.author.uniqueId) {
        return (
          "https://www.tiktok.com/@" +
          detail.author.uniqueId +
          "/video/" +
          detail.id
        );
      }
    } catch (_) {}
    return null;
  }

  function visibilityScore(el) {
    const r = el.getBoundingClientRect();
    const vh = window.innerHeight || 1;
    const vw = window.innerWidth || 1;
    const visibleH = Math.max(0, Math.min(r.bottom, vh) - Math.max(r.top, 0));
    const visibleW = Math.max(0, Math.min(r.right, vw) - Math.max(r.left, 0));
    const area = visibleH * visibleW;
    if (area <= 0) return 0;
    const cy = (r.top + r.bottom) / 2;
    const centerDist = Math.abs(cy - vh / 2) / vh;
    return area * (1 - Math.min(centerDist, 1));
  }

  function linkNear(el) {
    let node = el;
    for (let i = 0; i < 14 && node; i++) {
      if (node.nodeType === 1) {
        if (node.matches && node.matches('a[href*="/video/"]')) {
          const u = canonicalize(node.href);
          if (u) return u;
        }
        const a =
          node.querySelector && node.querySelector('a[href*="/video/"]');
        if (a) {
          const u = canonicalize(a.href);
          if (u) return u;
        }
      }
      node = node.parentElement;
    }
    return null;
  }

  function fromVideos() {
    const videos = Array.from(document.querySelectorAll("video"));
    if (!videos.length) return null;

    const ranked = videos
      .map((v) => ({
        v,
        playing: !v.paused && !v.ended && v.readyState > 2,
        score: visibilityScore(v),
      }))
      .filter((x) => x.score > 0)
      .sort((a, b) => {
        if (a.playing !== b.playing) return a.playing ? -1 : 1;
        return b.score - a.score;
      });

    for (const item of ranked) {
      const u = linkNear(item.v);
      if (u) return u;
    }
    return null;
  }

  function fromVisibleItems() {
    const selectors = [
      '[data-e2e="recommend-list-item-container"]',
      '[data-e2e="feed-video"]',
      '[data-e2e="user-post-item"]',
      "article",
    ];
    const candidates = Array.from(
      document.querySelectorAll(selectors.join(","))
    );
    let best = null;
    let bestScore = 0;
    for (const el of candidates) {
      const score = visibilityScore(el);
      if (score <= bestScore) continue;
      const a = el.querySelector('a[href*="/video/"]');
      const u = canonicalize(a && a.href);
      if (u) {
        best = u;
        bestScore = score;
      }
    }
    return best;
  }

  function detect() {
    return (
      fromLocation() ||
      fromCanonicalLink() ||
      fromUniversalData() ||
      fromVideos() ||
      fromVisibleItems()
    );
  }

  // Voor one-shot inject via chrome.scripting (tab open vóór extentie).
  globalThis.__downoaderDetectTikTok = detect;

  chrome.runtime.onMessage.addListener((msg, _sender, sendResponse) => {
    if (msg && msg.type === "getDownloadUrl") {
      const url = detect();
      sendResponse({ url: url || null, site: "tiktok" });
    }
  });
})();
