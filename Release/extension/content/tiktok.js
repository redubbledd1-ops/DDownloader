// Detecteert de canonieke TikTok-video-URL op de huidige pagina.
// Op de For You-feed staat die niet in de adresbalk en ontbreken /video/-links —
// de video-id zit in de player-wrapper (`xgwrapper-0-{id}`).
(function () {
  const VIDEO_PATH = /\/@([^/?#]+)\/(?:video|photo)\/(\d+)/i;
  const WRAPPER_ID = /xgwrapper-\d+-(\d+)/i;

  function canonicalize(href) {
    if (!href) return null;
    try {
      const u = new URL(href, location.href);
      const m = u.pathname.match(VIDEO_PATH);
      if (!m) return null;
      const kind = /\/photo\//i.test(u.pathname) ? "photo" : "video";
      return (
        "https://www.tiktok.com/@" +
        decodeURIComponent(m[1]) +
        "/" +
        kind +
        "/" +
        m[2]
      );
    } catch (_) {
      return null;
    }
  }

  function buildUrl(author, id, kind) {
    if (!id) return null;
    const type = kind === "photo" ? "photo" : "video";
    if (author) {
      return "https://www.tiktok.com/@" + author + "/" + type + "/" + id;
    }
    return "https://www.tiktok.com/embed/" + type + "/" + id;
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

  function authorFromItem(el) {
    const avatar = el.querySelector('a[data-e2e="video-author-avatar"]');
    if (avatar) {
      const m = (avatar.getAttribute("href") || "").match(/\/@([^/?#]+)/);
      if (m && m[1]) return decodeURIComponent(m[1]);
    }
    const unique = el.querySelector(
      '[data-e2e="video-author-uniqueid"], [data-e2e="browse-username"]'
    );
    if (unique) {
      const text = (unique.textContent || "").trim().replace(/^@/, "");
      if (text) return text;
      const href = unique.getAttribute && unique.getAttribute("href");
      const m = (href || "").match(/\/@([^/?#]+)/);
      if (m && m[1]) return decodeURIComponent(m[1]);
    }
    const links = Array.from(el.querySelectorAll('a[href*="/@"]'));
    for (const a of links) {
      const e2e = a.getAttribute("data-e2e") || "";
      if (e2e === "search-common-link") continue;
      const href = a.getAttribute("href") || "";
      if (/\/tag\//i.test(href) || /\/music\//i.test(href)) continue;
      const m = href.match(/\/@([^/?#]+)/);
      if (m && m[1] && m[1] !== "") return decodeURIComponent(m[1]);
    }
    return null;
  }

  function videoIdFromItem(el) {
    const wrap =
      el.querySelector('[id^="xgwrapper-"]') ||
      (el.id && WRAPPER_ID.test(el.id) ? el : null);
    if (wrap && wrap.id) {
      const m = wrap.id.match(WRAPPER_ID);
      if (m) return m[1];
    }
    const any = el.querySelector('[id*="xgwrapper-"]');
    if (any && any.id) {
      const m = any.id.match(WRAPPER_ID);
      if (m) return m[1];
    }
    return null;
  }

  function tryStep(name, fn, debug) {
    let url = null;
    let error = null;
    let extra = null;
    try {
      const out = fn();
      if (out && typeof out === "object" && "url" in out) {
        url = out.url || null;
        extra = out.extra || null;
      } else {
        url = out || null;
      }
    } catch (e) {
      error = (e && e.message) || String(e);
    }
    const entry = { step: name, ok: Boolean(url), url: url || null };
    if (error) entry.error = error;
    if (extra) entry.extra = extra;
    debug.steps.push(entry);
    return url;
  }

  function pageStats() {
    return {
      href: location.href,
      title: document.title,
      readyState: document.readyState,
      videos: document.querySelectorAll("video").length,
      wrappers: document.querySelectorAll('[id^="xgwrapper-"]').length,
      feedItems: document.querySelectorAll(
        '[data-e2e="recommend-list-item-container"]'
      ).length,
      feedVideos: document.querySelectorAll('[data-e2e="feed-video"]').length,
      videoLinks: document.querySelectorAll(
        'a[href*="/video/"], a[href*="/photo/"]'
      ).length,
      hasUniversal: Boolean(
        document.querySelector("#__UNIVERSAL_DATA_FOR_REHYDRATION__")
      ),
      canonical:
        (document.querySelector('link[rel="canonical"]') || {}).href || null,
    };
  }

  function detectWithDebug() {
    const debug = {
      script: "content/tiktok.js",
      version: 2,
      at: new Date().toISOString(),
      page: pageStats(),
      steps: [],
      picked: null,
    };

    const url =
      tryStep("location", () => canonicalize(location.href), debug) ||
      tryStep(
        "canonical",
        () => {
          const el = document.querySelector('link[rel="canonical"]');
          return canonicalize(el && el.href);
        },
        debug
      ) ||
      tryStep(
        "universalData",
        () => {
          const el = document.querySelector(
            "#__UNIVERSAL_DATA_FOR_REHYDRATION__"
          );
          if (!el || !el.textContent) return null;
          const data = JSON.parse(el.textContent);
          const scope = data.__DEFAULT_SCOPE__ || {};
          const detail =
            scope["webapp.video-detail"] &&
            scope["webapp.video-detail"].itemInfo &&
            scope["webapp.video-detail"].itemInfo.itemStruct;
          if (detail && detail.id && detail.author && detail.author.uniqueId) {
            return buildUrl(detail.author.uniqueId, String(detail.id));
          }
          return {
            url: null,
            extra: {
              hasScope: Boolean(scope),
              scopeKeys: Object.keys(scope).slice(0, 20),
            },
          };
        },
        debug
      ) ||
      tryStep(
        "feedItems",
        () => {
          const items = Array.from(
            document.querySelectorAll(
              '[data-e2e="recommend-list-item-container"], [data-e2e="feed-video"], [id^="one-column-item-"]'
            )
          );
          const ranked = items
            .map((el) => {
              const container =
                el.closest('[data-e2e="recommend-list-item-container"]') ||
                el.closest('[id^="one-column-item-"]') ||
                el;
              const id = videoIdFromItem(container);
              const video = container.querySelector("video");
              const playing = !!(
                video &&
                !video.paused &&
                !video.ended &&
                video.readyState > 2
              );
              return {
                id,
                author: id ? authorFromItem(container) : null,
                playing,
                score: Math.round(visibilityScore(container)),
                wrapId: (
                  container.querySelector('[id^="xgwrapper-"]') || {}
                ).id || null,
              };
            })
            .filter((x) => x.id && x.score > 0)
            .sort((a, b) => {
              if (a.playing !== b.playing) return a.playing ? -1 : 1;
              return b.score - a.score;
            });
          const best = ranked[0] || null;
          return {
            url: best ? buildUrl(best.author, best.id) : null,
            extra: {
              scanned: items.length,
              withId: ranked.length,
              top: ranked.slice(0, 3),
            },
          };
        },
        debug
      ) ||
      tryStep(
        "anyWrapper",
        () => {
          const wraps = Array.from(
            document.querySelectorAll('[id^="xgwrapper-"]')
          );
          let bestUrl = null;
          let bestScore = 0;
          let bestMeta = null;
          for (const wrap of wraps) {
            const m = wrap.id.match(WRAPPER_ID);
            if (!m) continue;
            const score = visibilityScore(wrap);
            if (score <= bestScore) continue;
            const item =
              wrap.closest('[data-e2e="recommend-list-item-container"]') ||
              wrap.closest('[id^="one-column-item-"]') ||
              wrap.parentElement;
            const author = item ? authorFromItem(item) : null;
            bestUrl = buildUrl(author, m[1]);
            bestScore = score;
            bestMeta = {
              wrapId: wrap.id,
              author,
              score: Math.round(score),
            };
          }
          return {
            url: bestUrl,
            extra: { wrappers: wraps.length, best: bestMeta },
          };
        },
        debug
      ) ||
      tryStep(
        "videoLinks",
        () => {
          const links = Array.from(
            document.querySelectorAll(
              'a[href*="/video/"], a[href*="/photo/"]'
            )
          );
          let best = null;
          let bestScore = 0;
          for (const a of links) {
            const u = canonicalize(a.href);
            if (!u) continue;
            const score = visibilityScore(a);
            if (score > bestScore) {
              best = u;
              bestScore = score;
            }
          }
          return {
            url: best,
            extra: { links: links.length, score: Math.round(bestScore) },
          };
        },
        debug
      );

    debug.picked = url || null;
    return { url: url || null, site: "tiktok", debug };
  }

  function detect() {
    return detectWithDebug().url;
  }

  globalThis.__downoaderDetectTikTok = detect;
  globalThis.__downoaderDetectTikTokDebug = detectWithDebug;

  if (!globalThis.__downoaderTikTokMsgBound) {
    globalThis.__downoaderTikTokMsgBound = true;
    chrome.runtime.onMessage.addListener((msg, _sender, sendResponse) => {
      if (msg && msg.type === "getDownloadUrl") {
        if (msg.debug) {
          sendResponse(detectWithDebug());
        } else {
          const url = detect();
          sendResponse({ url: url || null, site: "tiktok" });
        }
      }
    });
  }
})();
