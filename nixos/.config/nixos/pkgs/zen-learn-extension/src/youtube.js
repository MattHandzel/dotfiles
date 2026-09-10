// Learn This — YouTube Content Script
// Captures video moments with timestamp + transcript context

(function () {
  // Add "Capture Moment" button to YouTube player controls
  let buttonInjected = false;

  function getVideoTime() {
    const video = document.querySelector("video");
    if (!video) return null;
    const seconds = Math.floor(video.currentTime);
    const h = Math.floor(seconds / 3600);
    const m = Math.floor((seconds % 3600) / 60);
    const s = seconds % 60;
    if (h > 0) {
      return `${h}:${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}`;
    }
    return `${m}:${String(s).padStart(2, "0")}`;
  }

  function getVideoTimestamp() {
    const video = document.querySelector("video");
    return video ? Math.floor(video.currentTime) : 0;
  }

  function getVideoTitle() {
    const el =
      document.querySelector(
        "h1.ytd-watch-metadata yt-formatted-string"
      ) ||
      document.querySelector("h1.title") ||
      document.querySelector("#title h1");
    return el ? el.textContent.trim() : document.title.replace(" - YouTube", "");
  }

  function getVideoUrl() {
    const url = new URL(window.location.href);
    url.searchParams.set("t", getVideoTimestamp() + "s");
    return url.toString();
  }

  function getTranscriptSnippet() {
    // Try to get transcript segments near current time
    const segments = document.querySelectorAll(
      "ytd-transcript-segment-renderer"
    );
    if (!segments.length) return "";

    const currentTime = getVideoTimestamp();
    const nearbyText = [];

    for (const seg of segments) {
      const timeEl = seg.querySelector(
        ".segment-timestamp"
      );
      const textEl = seg.querySelector(
        ".segment-text"
      );
      if (!timeEl || !textEl) continue;

      // Parse timestamp from "1:23" or "1:23:45"
      const parts = timeEl.textContent.trim().split(":").map(Number);
      let segTime = 0;
      if (parts.length === 3)
        segTime = parts[0] * 3600 + parts[1] * 60 + parts[2];
      else if (parts.length === 2) segTime = parts[0] * 60 + parts[1];

      // Get segments within 30 seconds of current time
      if (Math.abs(segTime - currentTime) < 30) {
        nearbyText.push(textEl.textContent.trim());
      }
    }

    return nearbyText.join(" ");
  }

  function injectCaptureButton() {
    if (buttonInjected) return;
    const controls = document.querySelector(".ytp-right-controls");
    if (!controls) return;

    const btn = document.createElement("button");
    btn.className = "ytp-button learn-yt-capture-btn";
    btn.title = "Capture this moment (Learn This)";
    btn.innerHTML = `<svg viewBox="0 0 24 24" width="24" height="24" fill="white">
      <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-1 15h2v-6h-2v6zm0-8h2V7h-2v2z"/>
    </svg>`;

    btn.addEventListener("click", (e) => {
      e.preventDefault();
      e.stopPropagation();
      captureMoment();
    });

    controls.prepend(btn);
    buttonInjected = true;

    // Add minimal styles
    const style = document.createElement("style");
    style.textContent = `
      .learn-yt-capture-btn {
        cursor: pointer;
        opacity: 0.8;
        transition: opacity 0.2s;
      }
      .learn-yt-capture-btn:hover {
        opacity: 1;
      }
    `;
    document.head.appendChild(style);
  }

  function captureMoment() {
    const data = {
      videoTitle: getVideoTitle(),
      timestamp: getVideoTime(),
      url: getVideoUrl(),
      transcript: getTranscriptSnippet(),
      thoughts: "",
    };

    // Pause video while capturing
    const video = document.querySelector("video");
    const wasPlaying = video && !video.paused;
    if (wasPlaying) video.pause();

    // Show a mini capture form over the video
    showYouTubeCaptureForm(data, () => {
      if (wasPlaying && video) video.play();
    });
  }

  function showYouTubeCaptureForm(data, onClose) {
    // Remove existing
    const existing = document.getElementById("learn-yt-capture");
    if (existing) existing.remove();

    const overlay = document.createElement("div");
    overlay.id = "learn-yt-capture";
    overlay.style.cssText = `
      position: fixed; top: 0; left: 0; width: 100%; height: 100%;
      background: rgba(0,0,0,0.6); z-index: 2147483647;
      display: flex; align-items: center; justify-content: center;
      font-family: -apple-system, sans-serif;
    `;

    overlay.innerHTML = `
      <div style="
        background: #1a1a2e; border-radius: 12px; padding: 20px;
        width: 460px; color: #e0e0e0; border: 1px solid rgba(99,102,241,0.3);
        box-shadow: 0 12px 48px rgba(0,0,0,0.5);
      ">
        <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:14px;">
          <span style="font-weight:700;color:#a0a0ff;font-size:14px;">
            Capture Video Moment
          </span>
          <span style="color:#6366f1;font-size:13px;">
            ${data.videoTitle.substring(0, 40)} @ ${data.timestamp}
          </span>
        </div>
        ${data.transcript ? `<div style="
          background:rgba(99,102,241,0.06);border-left:3px solid #6366f1;
          padding:8px 12px;font-size:12px;color:#b0b0d0;margin-bottom:12px;
          max-height:60px;overflow-y:auto;border-radius:0 6px 6px 0;
        ">${data.transcript.substring(0, 300)}</div>` : ""}
        <textarea id="learn-yt-thoughts" rows="3" placeholder="What's important about this moment? Why capture it?"
          style="
            width:100%;padding:8px 10px;border-radius:6px;box-sizing:border-box;
            border:1px solid rgba(255,255,255,0.1);background:rgba(255,255,255,0.04);
            color:#e0e0e0;font-size:14px;font-family:inherit;resize:vertical;
          "></textarea>
        <div style="display:flex;gap:8px;margin-top:10px;">
          <input type="text" id="learn-yt-tags" value="learn, video-capture"
            placeholder="Tags" style="
              flex:1;padding:8px 10px;border-radius:6px;
              border:1px solid rgba(255,255,255,0.1);background:rgba(255,255,255,0.04);
              color:#e0e0e0;font-size:13px;box-sizing:border-box;
            ">
        </div>
        <div style="display:flex;gap:10px;justify-content:flex-end;margin-top:14px;">
          <button id="learn-yt-cancel" style="
            padding:8px 16px;border-radius:6px;border:none;cursor:pointer;
            background:rgba(255,255,255,0.08);color:#b0b0d0;font-size:13px;font-weight:600;
          ">Cancel</button>
          <button id="learn-yt-save" style="
            padding:8px 16px;border-radius:6px;border:none;cursor:pointer;
            background:#6366f1;color:white;font-size:13px;font-weight:600;
          ">Capture Moment</button>
        </div>
        <div id="learn-yt-status" style="text-align:center;font-size:12px;margin-top:6px;min-height:16px;"></div>
      </div>
    `;

    document.body.appendChild(overlay);

    // Focus textarea
    setTimeout(() => document.getElementById("learn-yt-thoughts")?.focus(), 50);

    // Cancel
    document.getElementById("learn-yt-cancel").addEventListener("click", () => {
      overlay.remove();
      onClose();
    });

    // Escape
    const escHandler = (e) => {
      if (e.key === "Escape") {
        overlay.remove();
        onClose();
        document.removeEventListener("keydown", escHandler);
      }
    };
    document.addEventListener("keydown", escHandler);

    // Save
    document.getElementById("learn-yt-save").addEventListener("click", async () => {
      const thoughts = document.getElementById("learn-yt-thoughts")?.value || "";
      const tags = document.getElementById("learn-yt-tags")?.value || "learn, video-capture";
      const status = document.getElementById("learn-yt-status");

      data.thoughts = thoughts;
      data.tags = tags;

      if (status) {
        status.textContent = "Saving...";
        status.style.color = "#888";
      }

      try {
        const result = await browser.runtime.sendMessage({
          type: "CAPTURE_YOUTUBE_MOMENT",
          data: data,
        });

        if (result?.success) {
          if (status) {
            status.textContent = "Captured!";
            status.style.color = "#4ade80";
          }
          setTimeout(() => {
            overlay.remove();
            onClose();
          }, 800);
        } else {
          if (status) {
            status.textContent = `Error: ${result?.error || "Failed"}`;
            status.style.color = "#f87171";
          }
        }
      } catch (err) {
        if (status) {
          status.textContent = `Error: ${err.message}`;
          status.style.color = "#f87171";
        }
      }
    });

    // Ctrl+Enter
    overlay.addEventListener("keydown", (e) => {
      if (e.key === "Enter" && (e.ctrlKey || e.metaKey)) {
        e.preventDefault();
        document.getElementById("learn-yt-save")?.click();
      }
    });
  }

  // Inject button when player is ready
  const observer = new MutationObserver(() => {
    if (document.querySelector(".ytp-right-controls") && !buttonInjected) {
      injectCaptureButton();
    }
  });
  observer.observe(document.body, { childList: true, subtree: true });

  // Also try immediately
  if (document.readyState === "complete") {
    setTimeout(injectCaptureButton, 1000);
  } else {
    window.addEventListener("load", () => setTimeout(injectCaptureButton, 1000));
  }

  // Re-inject on navigation (YouTube is SPA)
  let lastUrl = location.href;
  new MutationObserver(() => {
    if (location.href !== lastUrl) {
      lastUrl = location.href;
      buttonInjected = false;
      setTimeout(injectCaptureButton, 1500);
    }
  }).observe(document.body, { childList: true, subtree: true });
})();
