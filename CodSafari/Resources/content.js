// Float Video with Cod — adds a small "Float" button over web videos.
// Tapping it asks Safari to play that video in Picture in Picture using the
// standard web Picture-in-Picture API. Nothing is downloaded or sent anywhere.
(() => {
  if (window.__codFloatVideo) return;
  window.__codFloatVideo = true;

  const MIN_WIDTH = 200;
  const MIN_HEIGHT = 110;
  const buttons = new Map(); // video -> host element
  let enabled = true;

  const api = typeof browser !== "undefined" ? browser : typeof chrome !== "undefined" ? chrome : null;

  function supportsPiP(video) {
    return (
      typeof video.requestPictureInPicture === "function" ||
      typeof video.webkitSetPresentationMode === "function"
    );
  }

  function isFloating(video) {
    return (
      document.pictureInPictureElement === video ||
      video.webkitPresentationMode === "picture-in-picture"
    );
  }

  async function toggle(video) {
    try {
      if (isFloating(video)) {
        if (document.exitPictureInPicture) await document.exitPictureInPicture();
        else video.webkitSetPresentationMode("inline");
        return;
      }
      // The user asked for this video explicitly, so a page-level opt-out
      // shouldn't silently swallow the tap.
      if (video.disablePictureInPicture) video.disablePictureInPicture = false;
      if (video.paused) {
        try { await video.play(); } catch (_) { /* autoplay rules; PiP still works paused */ }
      }
      if (typeof video.requestPictureInPicture === "function") {
        await video.requestPictureInPicture();
      } else {
        video.webkitSetPresentationMode("picture-in-picture");
      }
    } catch (error) {
      flash(video, "Can't float this video");
    }
  }

  function makeButton(video) {
    const host = document.createElement("div");
    host.setAttribute("data-cod-float", "");
    host.style.cssText =
      "position:absolute;z-index:2147483647;top:0;left:0;pointer-events:none;";
    const root = host.attachShadow({ mode: "closed" });
    const style = document.createElement("style");
    style.textContent = `
      button {
        pointer-events: auto;
        display: flex; align-items: center; gap: 6px;
        font: 600 13px -apple-system, system-ui, sans-serif;
        color: #fff; background: rgba(0,0,0,.62);
        border: 1px solid rgba(255,255,255,.28); border-radius: 999px;
        padding: 7px 12px; min-height: 32px;
        -webkit-backdrop-filter: blur(12px); backdrop-filter: blur(12px);
      }
      button:active { transform: scale(.96); }
      svg { width: 15px; height: 15px; }
      .note { pointer-events:none; margin-top:6px; font: 500 12px -apple-system, system-ui;
        color:#fff; background:rgba(0,0,0,.62); border-radius:8px; padding:4px 8px; display:none; }
    `;
    const button = document.createElement("button");
    button.type = "button";
    button.setAttribute("aria-label", "Float this video in Picture in Picture");
    button.innerHTML =
      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">' +
      '<rect x="2.5" y="4.5" width="19" height="15" rx="2.5"/>' +
      '<rect x="11.5" y="11" width="8" height="6" rx="1.2" fill="currentColor" stroke="none"/></svg>' +
      "<span>Float</span>";
    const note = document.createElement("div");
    note.className = "note";
    button.addEventListener("click", (event) => {
      event.preventDefault();
      event.stopPropagation();
      toggle(video);
    }, true);
    root.append(style, button, note);
    host.__codNote = note;
    document.documentElement.appendChild(host);
    return host;
  }

  function flash(video, message) {
    const host = buttons.get(video);
    if (!host) return;
    host.__codNote.textContent = message;
    host.__codNote.style.display = "block";
    setTimeout(() => { host.__codNote.style.display = "none"; }, 2200);
  }

  function place(video, host) {
    const rect = video.getBoundingClientRect();
    const visible =
      enabled && rect.width >= MIN_WIDTH && rect.height >= MIN_HEIGHT &&
      rect.bottom > 0 && rect.right > 0 &&
      rect.top < innerHeight && rect.left < innerWidth &&
      !document.fullscreenElement && !video.webkitDisplayingFullscreen;
    host.style.display = visible ? "block" : "none";
    if (!visible) return;
    host.style.transform =
      `translate(${Math.round(rect.left + scrollX + 10)}px, ${Math.round(rect.top + scrollY + 10)}px)`;
  }

  function scan() {
    for (const video of document.querySelectorAll("video")) {
      if (!buttons.has(video) && supportsPiP(video)) buttons.set(video, makeButton(video));
    }
    for (const [video, host] of buttons) {
      if (!video.isConnected) { host.remove(); buttons.delete(video); continue; }
      place(video, host);
    }
  }

  let scheduled = false;
  function schedule() {
    if (scheduled) return;
    scheduled = true;
    requestAnimationFrame(() => { scheduled = false; scan(); });
  }

  if (api && api.storage && api.storage.local) {
    api.storage.local.get({ showButton: true }).then((value) => {
      enabled = value.showButton !== false;
      schedule();
    }).catch(() => {});
    api.storage.onChanged.addListener((changes) => {
      if (changes.showButton) { enabled = changes.showButton.newValue !== false; schedule(); }
    });
  }

  if (api && api.runtime && api.runtime.onMessage) {
    api.runtime.onMessage.addListener((message) => {
      if (!message || message.type !== "cod-float-largest") return;
      const videos = [...document.querySelectorAll("video")].filter(supportsPiP);
      const largest = videos.sort((a, b) => {
        const ra = a.getBoundingClientRect(), rb = b.getBoundingClientRect();
        return rb.width * rb.height - ra.width * ra.height;
      })[0];
      if (largest) toggle(largest);
      return Promise.resolve({ found: Boolean(largest) });
    });
  }

  new MutationObserver(schedule).observe(document.documentElement, { childList: true, subtree: true });
  addEventListener("scroll", schedule, { passive: true });
  addEventListener("resize", schedule);
  document.addEventListener("fullscreenchange", schedule);
  document.addEventListener("webkitpresentationmodechanged", schedule, true);
  setInterval(schedule, 1500); // catch layout changes the observers miss
  schedule();
})();
