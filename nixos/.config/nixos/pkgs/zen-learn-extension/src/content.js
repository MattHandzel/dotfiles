// Learn This — Content Script
// Page context extraction, inline learn panel, quick capture popup

let panelElement = null;
let capturePopup = null;
let ttsPlayer = null;
let ttsAudio = null;
let ttsAnimFrame = null;
let ttsCurrentText = "";
let ttsHighlightRanges = []; // saved Range objects for the original selection
let ttsHighlightOverlay = null; // the highlight element on the page

// ─── Message Listener ───────────────────────────────────────────────

browser.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message.type === "GET_PAGE_CONTEXT") {
    sendResponse({ context: extractPageContext() });
    return;
  }
  if (message.type === "SHOW_PANEL") {
    showPanel(message);
    return;
  }
  if (message.type === "SHOW_CAPTURE_POPUP") {
    showCapturePopup(message);
    return;
  }
  if (message.type === "SHOW_TTS_PLAYER") {
    // Capture the live selection ranges before they disappear
    const sel = window.getSelection();
    const ranges = [];
    if (sel && sel.rangeCount > 0) {
      for (let i = 0; i < sel.rangeCount; i++) {
        ranges.push(sel.getRangeAt(i).cloneRange());
      }
    }
    showTTSPlayer(message.text, ranges);
    return;
  }
  if (message.type === "TTS_AUDIO_READY") {
    ttsOnAudioReady(message.audioDataUrl);
    return;
  }
  if (message.type === "TTS_ERROR") {
    ttsOnError(message.error);
    return;
  }
});

// ─── Page Context Extraction ────────────────────────────────────────

function extractPageContext() {
  const meta = {};
  meta.title = document.title;
  meta.url = window.location.href;
  meta.domain = window.location.hostname;

  const authorMeta = document.querySelector(
    'meta[name="author"], meta[property="article:author"], [rel="author"]'
  );
  if (authorMeta) meta.author = authorMeta.content || authorMeta.textContent || "";

  const dateMeta = document.querySelector(
    'meta[property="article:published_time"], meta[name="date"], time[datetime]'
  );
  if (dateMeta) meta.date = dateMeta.content || dateMeta.getAttribute("datetime") || "";

  const descMeta = document.querySelector(
    'meta[name="description"], meta[property="og:description"]'
  );
  if (descMeta) meta.description = descMeta.content || "";

  // Get article text — try multiple strategies
  const selectors = [
    "article", '[role="article"]', '[role="main"]', "main",
    ".post-content", ".article-content", ".article-body", ".entry-content",
    ".story-body", ".post-body", "#article-body", "#content", ".content",
    ".markdown-body", ".s-prose",
  ];

  let bestContent = "";
  for (const sel of selectors) {
    const el = document.querySelector(sel);
    if (el) {
      const text = el.innerText.trim();
      if (text.length > bestContent.length) bestContent = text;
    }
  }

  if (bestContent.length < 500) {
    const clone = document.body.cloneNode(true);
    for (const sel of ["nav", "header", "footer", "aside", ".sidebar", ".menu",
                        ".navigation", ".comments", ".related", "#comments",
                        "script", "style", "noscript", "[role='navigation']",
                        "[role='banner']", "[role='contentinfo']"]) {
      clone.querySelectorAll(sel).forEach((el) => el.remove());
    }
    bestContent = clone.innerText.trim();
  }

  // Surrounding context near selection
  let selectionContext = "";
  const sel = window.getSelection();
  if (sel && sel.rangeCount > 0) {
    const range = sel.getRangeAt(0);
    let container = range.commonAncestorContainer;
    while (container && container !== document.body) {
      const tag = container.tagName ? container.tagName.toLowerCase() : "";
      if (["section", "article", "div", "blockquote", "li", "td", "p"].includes(tag)) {
        const parent = container.parentElement;
        if (parent) {
          const siblings = Array.from(parent.children);
          const idx = siblings.indexOf(container);
          const start = Math.max(0, idx - 2);
          const end = Math.min(siblings.length, idx + 3);
          selectionContext = siblings
            .slice(start, end)
            .map((el) => el.innerText.trim())
            .filter(Boolean)
            .join("\n\n");
        }
        break;
      }
      container = container.parentElement;
    }
  }

  // Build context — generous for Claude
  const maxArticle = 12000;
  let articleText = bestContent;
  if (articleText.length > maxArticle) {
    const keepStart = Math.floor(maxArticle * 0.7);
    const keepEnd = Math.floor(maxArticle * 0.3);
    articleText =
      articleText.substring(0, keepStart) +
      "\n\n[...middle section omitted for length...]\n\n" +
      articleText.substring(articleText.length - keepEnd);
  }

  let context = `Title: ${meta.title}\nURL: ${meta.url}\nSite: ${meta.domain}`;
  if (meta.author) context += `\nAuthor: ${meta.author}`;
  if (meta.date) context += `\nPublished: ${meta.date}`;
  if (meta.description) context += `\nDescription: ${meta.description}`;
  if (selectionContext) {
    context += `\n\n--- Surrounding context (paragraphs near the selection) ---\n${selectionContext}`;
  }
  context += `\n\n--- Full article text ---\n${articleText}`;

  return context;
}

// ─── Quick Capture Popup ────────────────────────────────────────────

function showCapturePopup(message) {
  removeCapturePopup();

  const selection =
    message?.selection || window.getSelection()?.toString()?.trim() || "";
  const pageTitle = message?.pageTitle || document.title;
  const pageUrl = message?.pageUrl || window.location.href;
  const autoLearn = message?.autoLearn || false;
  const autoReadingList = message?.autoReadingList || false;

  capturePopup = document.createElement("div");
  capturePopup.id = "learn-capture-popup";
  capturePopup.className = "lc-popup";

  capturePopup.innerHTML = `
    <div class="lc-header">
      <span class="lc-title">Quick Capture</span>
      <div class="lc-controls">
        <button class="lc-btn lc-btn-close" id="lc-close">\u00d7</button>
      </div>
    </div>
    <div class="lc-body">
      <div class="lc-field">
        <label>Selected text</label>
        <div class="lc-selection">${escapeHtml(selection) || '<em>No text selected</em>'}</div>
      </div>
      <div class="lc-field">
        <label>Your thoughts / notes</label>
        <textarea id="lc-thoughts" rows="3" placeholder="What's interesting about this? Why does it matter?"></textarea>
      </div>
      <div class="lc-field">
        <label>Tags <span class="lc-hint">(comma-separated)</span></label>
        <input type="text" id="lc-tags" value="${autoLearn ? 'learn' : autoReadingList ? 'reading-list' : ''}" placeholder="e.g. ai, research, learn">
        <div class="lc-tag-suggestions" id="lc-suggestions"></div>
      </div>
      <div class="lc-field lc-row">
        <div class="lc-field-half">
          <label>Source</label>
          <input type="text" id="lc-source" value="${escapeHtml(pageUrl)}">
        </div>
        <div class="lc-field-half">
          <label>Alias</label>
          <input type="text" id="lc-alias" value="" placeholder="${escapeHtml(pageTitle.substring(0, 60))}">
        </div>
      </div>
      <div class="lc-actions">
        <button class="lc-btn lc-btn-secondary" id="lc-capture-only">Capture</button>
        <button class="lc-btn lc-btn-reading-list" id="lc-capture-reading-list">+ Reading List</button>
        <button class="lc-btn lc-btn-primary" id="lc-capture-learn">Capture + #learn</button>
      </div>
      <div class="lc-status" id="lc-status"></div>
    </div>
  `;

  document.body.appendChild(capturePopup);

  // Focus thoughts field
  setTimeout(() => {
    const thoughts = document.getElementById("lc-thoughts");
    if (thoughts) thoughts.focus();
  }, 50);

  // Close button
  document.getElementById("lc-close").addEventListener("click", removeCapturePopup);

  // Escape to close
  const escHandler = (e) => {
    if (e.key === "Escape") {
      removeCapturePopup();
      document.removeEventListener("keydown", escHandler);
    }
  };
  document.addEventListener("keydown", escHandler);

  // Capture buttons
  document.getElementById("lc-capture-only").addEventListener("click", () => {
    submitCaptureFromPopup(selection, false);
  });
  document.getElementById("lc-capture-learn").addEventListener("click", () => {
    submitCaptureFromPopup(selection, true);
  });
  document.getElementById("lc-capture-reading-list").addEventListener("click", () => {
    submitCaptureFromPopup(selection, false, true);
  });

  // Ctrl+Enter to submit with #learn
  capturePopup.addEventListener("keydown", (e) => {
    if (e.key === "Enter" && (e.ctrlKey || e.metaKey)) {
      e.preventDefault();
      submitCaptureFromPopup(selection, true);
    }
  });

  // Fetch tag suggestions
  fetchTagSuggestions(selection);

  // Make draggable
  const header = capturePopup.querySelector(".lc-header");
  let isDragging = false;
  let offsetX, offsetY;
  header.addEventListener("mousedown", (e) => {
    if (e.target.tagName === "BUTTON") return;
    isDragging = true;
    offsetX = e.clientX - capturePopup.getBoundingClientRect().left;
    offsetY = e.clientY - capturePopup.getBoundingClientRect().top;
  });
  document.addEventListener("mousemove", (e) => {
    if (!isDragging) return;
    capturePopup.style.right = "auto";
    capturePopup.style.left = e.clientX - offsetX + "px";
    capturePopup.style.top = e.clientY - offsetY + "px";
  });
  document.addEventListener("mouseup", () => (isDragging = false));
}

async function fetchTagSuggestions(content) {
  if (!content) return;
  try {
    const result = await browser.runtime.sendMessage({
      type: "GET_TAG_SUGGESTIONS",
      content: content,
    });
    const suggestionsDiv = document.getElementById("lc-suggestions");
    if (suggestionsDiv && result?.tags?.length) {
      suggestionsDiv.innerHTML = result.tags
        .map(
          (tag) =>
            `<span class="lc-tag-chip" data-tag="${escapeHtml(tag)}">${escapeHtml(tag)}</span>`
        )
        .join("");
      // Click to add tag
      suggestionsDiv.querySelectorAll(".lc-tag-chip").forEach((chip) => {
        chip.addEventListener("click", () => {
          const input = document.getElementById("lc-tags");
          const current = input.value
            .split(",")
            .map((t) => t.trim())
            .filter(Boolean);
          const tag = chip.dataset.tag;
          if (!current.includes(tag)) {
            current.push(tag);
            input.value = current.join(", ");
          }
          chip.classList.add("lc-tag-used");
        });
      });
    }
  } catch {
    // No suggestions available
  }
}

async function submitCaptureFromPopup(selection, addLearn, addReadingList) {
  const thoughts = document.getElementById("lc-thoughts")?.value || "";
  const tagsInput = document.getElementById("lc-tags")?.value || "";
  const source = document.getElementById("lc-source")?.value || "";
  const alias = document.getElementById("lc-alias")?.value || "";
  const status = document.getElementById("lc-status");

  let tags = tagsInput
    .split(",")
    .map((t) => t.trim())
    .filter(Boolean);
  if (addLearn && !tags.includes("learn")) tags.push("learn");
  if (addReadingList && !tags.includes("reading-list")) tags.push("reading-list");

  const content = thoughts
    ? `${thoughts}\n\n> ${selection}`
    : selection;

  if (status) {
    status.textContent = "Saving...";
    status.className = "lc-status lc-status-loading";
  }

  try {
    const result = await browser.runtime.sendMessage({
      type: "SUBMIT_CAPTURE",
      data: {
        content: content,
        clipboard: selection,
        sources: source,
        tags: tags.join(","),
        context: `Reading: ${document.title}`,
        modalities: "text,clipboard",
        alias: alias || document.title.substring(0, 80),
      },
    });

    if (result?.success) {
      if (status) {
        const msg = addLearn
          ? "Captured! Cards will be generated."
          : addReadingList
            ? "Added to reading list!"
            : "Captured!";
        status.textContent = msg;
        status.className = "lc-status lc-status-success";
      }
      setTimeout(removeCapturePopup, 1200);
    } else {
      if (status) {
        status.textContent = `Error: ${result?.error || "Failed to save"}`;
        status.className = "lc-status lc-status-error";
      }
    }
  } catch (err) {
    if (status) {
      status.textContent = `Error: ${err.message}`;
      status.className = "lc-status lc-status-error";
    }
  }
}

function removeCapturePopup() {
  if (capturePopup) {
    capturePopup.remove();
    capturePopup = null;
  }
}

// ─── Learn Result Panel ─────────────────────────────────────────────

function showPanel(message) {
  removePanel();

  panelElement = document.createElement("div");
  panelElement.id = "learn-this-panel";
  panelElement.className = "learn-this-panel";

  const header = document.createElement("div");
  header.className = "learn-this-header";

  const title = document.createElement("span");
  title.className = "learn-this-title";
  title.textContent = message.title || "Learn This";

  const controls = document.createElement("div");
  controls.className = "learn-this-controls";

  if (message.promptForClaude) {
    const claudeBtn = document.createElement("button");
    claudeBtn.className = "learn-this-btn learn-this-btn-claude";
    claudeBtn.textContent = "Continue in Claude";
    claudeBtn.addEventListener("click", () => {
      const encoded = encodeURIComponent(message.promptForClaude);
      window.open(`https://claude.ai/new?q=${encoded}`, "_blank");
    });
    controls.appendChild(claudeBtn);
  }

  const closeBtn = document.createElement("button");
  closeBtn.className = "learn-this-btn learn-this-btn-close";
  closeBtn.textContent = "\u00d7";
  closeBtn.addEventListener("click", removePanel);
  controls.appendChild(closeBtn);

  header.appendChild(title);
  header.appendChild(controls);
  panelElement.appendChild(header);

  if (message.selection) {
    const quote = document.createElement("div");
    quote.className = "learn-this-quote";
    quote.textContent = `"${message.selection}"`;
    panelElement.appendChild(quote);
  }

  const content = document.createElement("div");
  content.className = "learn-this-content";

  if (message.loading) {
    content.innerHTML =
      '<div class="learn-this-loading"><div class="learn-this-spinner"></div>Thinking...</div>';
  } else if (message.content) {
    content.innerHTML = renderMarkdown(message.content);
  }

  panelElement.appendChild(content);

  // Draggable
  let isDragging = false;
  let offsetX, offsetY;
  header.addEventListener("mousedown", (e) => {
    if (e.target.tagName === "BUTTON") return;
    isDragging = true;
    offsetX = e.clientX - panelElement.getBoundingClientRect().left;
    offsetY = e.clientY - panelElement.getBoundingClientRect().top;
    panelElement.style.transition = "none";
  });
  document.addEventListener("mousemove", (e) => {
    if (!isDragging) return;
    panelElement.style.right = "auto";
    panelElement.style.left = e.clientX - offsetX + "px";
    panelElement.style.top = e.clientY - offsetY + "px";
  });
  document.addEventListener("mouseup", () => {
    isDragging = false;
    if (panelElement) panelElement.style.transition = "";
  });

  const escHandler = (e) => {
    if (e.key === "Escape") {
      removePanel();
      document.removeEventListener("keydown", escHandler);
    }
  };
  document.addEventListener("keydown", escHandler);

  document.body.appendChild(panelElement);
}

function removePanel() {
  if (panelElement) {
    panelElement.remove();
    panelElement = null;
  }
}

// ─── TTS Player ────────────────────────────────────────────────────

const TTS_SPEEDS = [0.8, 1.0, 1.1, 1.25, 1.4];
let ttsSpeedIndex = 1; // default 1.0x

function showTTSPlayer(text, selectionRanges) {
  removeTTSPlayer();
  ttsCurrentText = text;
  ttsHighlightRanges = selectionRanges || [];

  ttsPlayer = document.createElement("div");
  ttsPlayer.className = "lt-tts-player lt-tts-state-loading";

  const svgSpeaker = `<svg viewBox="0 0 24 24"><path d="M3 9v6h4l5 5V4L7 9H3zm13.5 3c0-1.77-1.02-3.29-2.5-4.03v8.05c1.48-.73 2.5-2.25 2.5-4.02zM14 3.23v2.06c2.89.86 5 3.54 5 6.71s-2.11 5.85-5 6.71v2.06c4.01-.91 7-4.49 7-8.77s-2.99-7.86-7-8.77z"/></svg>`;
  const svgPlay = `<svg viewBox="0 0 24 24"><path d="M8 5v14l11-7z"/></svg>`;
  const svgPause = `<svg viewBox="0 0 24 24"><path d="M6 19h4V5H6v14zm8-14v14h4V5h-4z"/></svg>`;
  const svgDownload = `<svg viewBox="0 0 24 24"><path d="M19 9h-4V3H9v6H5l7 7 7-7zM5 18v2h14v-2H5z"/></svg>`;
  const svgHighlight = `<svg viewBox="0 0 24 24"><path d="M9 21c0 .55.45 1 1 1h4c.55 0 1-.45 1-1v-1H9v1zm3-19C8.14 2 5 5.14 5 9c0 2.38 1.19 4.47 3 5.74V17c0 .55.45 1 1 1h6c.55 0 1-.45 1-1v-2.26c1.81-1.27 3-3.36 3-5.74 0-3.86-3.14-7-7-7z"/></svg>`;

  ttsPlayer.innerHTML = `
    <div class="lt-tts-header">
      <div class="lt-tts-header-left">
        <span class="lt-tts-icon">${svgSpeaker}</span>
        <span class="lt-tts-title">Read Aloud</span>
      </div>
      <div class="lt-tts-header-btns">
        <button class="lt-tts-header-btn lt-tts-minimize-btn" title="Minimize">─</button>
        <button class="lt-tts-header-btn lt-tts-close-btn" title="Close">✕</button>
      </div>
    </div>
    <div class="lt-tts-mini-controls">
      <button class="lt-tts-mini-play">${svgPlay}</button>
      <div class="lt-tts-mini-progress"><div class="lt-tts-mini-progress-fill"></div></div>
      <span class="lt-tts-mini-time">0:00</span>
    </div>
    <div class="lt-tts-body">
      <div class="lt-tts-preview">${escapeHtml(text)}</div>
      <div class="lt-tts-loading">
        <div class="lt-tts-loading-bars">
          <div class="lt-tts-loading-bar"></div>
          <div class="lt-tts-loading-bar"></div>
          <div class="lt-tts-loading-bar"></div>
          <div class="lt-tts-loading-bar"></div>
          <div class="lt-tts-loading-bar"></div>
        </div>
        <span class="lt-tts-loading-text">Generating audio</span>
      </div>
      <div class="lt-tts-error">
        <span class="lt-tts-error-msg"></span>
        <button class="lt-tts-retry-btn">Retry</button>
      </div>
      <div class="lt-tts-transport">
        <button class="lt-tts-skip-btn lt-tts-skip-back" title="Back 10s">
          <svg viewBox="0 0 24 24"><path d="M11.99 5V1l-5 5 5 5V7c3.31 0 6 2.69 6 6s-2.69 6-6 6-6-2.69-6-6h-2c0 4.42 3.58 8 8 8s8-3.58 8-8-3.58-8-8-8z"/></svg>
        </button>
        <button class="lt-tts-play-btn" disabled>${svgPlay}</button>
        <button class="lt-tts-skip-btn lt-tts-skip-fwd" title="Forward 10s">
          <svg viewBox="0 0 24 24"><path d="M12.01 5V1l5 5-5 5V7c-3.31 0-6 2.69-6 6s2.69 6 6 6 6-2.69 6-6h2c0 4.42-3.58 8-8 8s-8-3.58-8-8 3.58-8 8-8z"/></svg>
        </button>
      </div>
      <div class="lt-tts-progress-row">
        <span class="lt-tts-time lt-tts-time-left">0:00</span>
        <div class="lt-tts-scrubber-wrap">
          <div class="lt-tts-scrubber-track">
            <div class="lt-tts-scrubber-fill">
              <div class="lt-tts-scrubber-thumb"></div>
            </div>
          </div>
        </div>
        <span class="lt-tts-time lt-tts-time-right">0:00</span>
      </div>
      <div class="lt-tts-footer">
        <button class="lt-tts-speed-btn">1.0x</button>
        <button class="lt-tts-highlight-btn" title="Toggle read-along highlight">${svgHighlight}</button>
        <button class="lt-tts-download-btn">${svgDownload} Save</button>
      </div>
    </div>
  `;

  document.body.appendChild(ttsPlayer);
  ttsBindEvents();
}

let ttsHighlightEnabled = false;

function ttsBindEvents() {
  if (!ttsPlayer) return;

  // Load highlight preference from storage
  browser.storage.local.get({ ttsHighlight: true }).then((s) => {
    ttsHighlightEnabled = s.ttsHighlight;
    const btn = ttsPlayer?.querySelector(".lt-tts-highlight-btn");
    if (btn) btn.classList.toggle("lt-tts-highlight-active", ttsHighlightEnabled);
  });

  // Close
  ttsPlayer.querySelector(".lt-tts-close-btn").addEventListener("click", removeTTSPlayer);

  // Minimize / expand
  ttsPlayer.querySelector(".lt-tts-minimize-btn").addEventListener("click", () => {
    ttsPlayer.classList.toggle("lt-tts-minimized");
    const btn = ttsPlayer.querySelector(".lt-tts-minimize-btn");
    btn.textContent = ttsPlayer.classList.contains("lt-tts-minimized") ? "□" : "─";
  });

  // Main play/pause
  ttsPlayer.querySelector(".lt-tts-play-btn").addEventListener("click", ttsTogglePlayback);

  // Mini play/pause
  ttsPlayer.querySelector(".lt-tts-mini-play").addEventListener("click", ttsTogglePlayback);

  // Skip back/forward
  ttsPlayer.querySelector(".lt-tts-skip-back").addEventListener("click", () => {
    if (ttsAudio) ttsAudio.currentTime = Math.max(0, ttsAudio.currentTime - 10);
  });
  ttsPlayer.querySelector(".lt-tts-skip-fwd").addEventListener("click", () => {
    if (ttsAudio) ttsAudio.currentTime = Math.min(ttsAudio.duration, ttsAudio.currentTime + 10);
  });

  // Speed
  ttsPlayer.querySelector(".lt-tts-speed-btn").addEventListener("click", () => {
    ttsSpeedIndex = (ttsSpeedIndex + 1) % TTS_SPEEDS.length;
    const speed = TTS_SPEEDS[ttsSpeedIndex];
    ttsPlayer.querySelector(".lt-tts-speed-btn").textContent = speed + "x";
    if (ttsAudio) ttsAudio.playbackRate = speed;
  });

  // Highlight toggle
  ttsPlayer.querySelector(".lt-tts-highlight-btn").addEventListener("click", () => {
    ttsHighlightEnabled = !ttsHighlightEnabled;
    browser.storage.local.set({ ttsHighlight: ttsHighlightEnabled });
    const btn = ttsPlayer.querySelector(".lt-tts-highlight-btn");
    btn.classList.toggle("lt-tts-highlight-active", ttsHighlightEnabled);
    if (ttsHighlightEnabled && ttsAudio && !ttsAudio.paused) {
      ttsApplyHighlight();
    } else {
      ttsRemoveHighlight();
    }
  });

  // Scrubber click-to-seek
  const scrubberWrap = ttsPlayer.querySelector(".lt-tts-scrubber-wrap");
  scrubberWrap.addEventListener("click", (e) => {
    if (!ttsAudio || !ttsAudio.duration) return;
    const rect = scrubberWrap.getBoundingClientRect();
    const ratio = Math.max(0, Math.min(1, (e.clientX - rect.left) / rect.width));
    ttsAudio.currentTime = ratio * ttsAudio.duration;
  });

  // Download
  ttsPlayer.querySelector(".lt-tts-download-btn").addEventListener("click", () => {
    if (!ttsAudio?.src) return;
    const a = document.createElement("a");
    a.href = ttsAudio.src;
    a.download = "read-aloud.mp3";
    a.click();
  });

  // Retry
  ttsPlayer.querySelector(".lt-tts-retry-btn").addEventListener("click", () => {
    ttsPlayer.className = "lt-tts-player lt-tts-state-loading";
    browser.runtime.sendMessage({
      type: "REQUEST_TTS",
      text: ttsCurrentText,
    }).then((result) => {
      if (result?.success) {
        ttsOnAudioReady(result.audioDataUrl);
      } else {
        ttsOnError(result?.error || "Unknown error");
      }
    });
  });

  // Keyboard: space to toggle, escape to close
  const keyHandler = (e) => {
    if (!ttsPlayer) {
      document.removeEventListener("keydown", keyHandler);
      return;
    }
    if (e.target.tagName === "INPUT" || e.target.tagName === "TEXTAREA" || e.target.isContentEditable) return;
    if (e.code === "Space" && ttsAudio?.src) {
      e.preventDefault();
      ttsTogglePlayback();
    }
    if (e.key === "Escape") {
      removeTTSPlayer();
      document.removeEventListener("keydown", keyHandler);
    }
  };
  document.addEventListener("keydown", keyHandler);

  // Draggable
  const header = ttsPlayer.querySelector(".lt-tts-header");
  let isDragging = false;
  let offsetX, offsetY;
  header.addEventListener("mousedown", (e) => {
    if (e.target.tagName === "BUTTON") return;
    isDragging = true;
    offsetX = e.clientX - ttsPlayer.getBoundingClientRect().left;
    offsetY = e.clientY - ttsPlayer.getBoundingClientRect().top;
  });
  document.addEventListener("mousemove", (e) => {
    if (!isDragging) return;
    ttsPlayer.style.right = "auto";
    ttsPlayer.style.bottom = "auto";
    ttsPlayer.style.left = (e.clientX - offsetX) + "px";
    ttsPlayer.style.top = (e.clientY - offsetY) + "px";
  });
  document.addEventListener("mouseup", () => (isDragging = false));
}

function ttsTogglePlayback() {
  if (!ttsAudio) return;
  if (ttsAudio.paused) {
    ttsAudio.play();
  } else {
    ttsAudio.pause();
  }
}

function ttsOnAudioReady(audioDataUrl) {
  if (!ttsPlayer) return;

  ttsPlayer.className = "lt-tts-player lt-tts-state-ready";

  if (ttsAudio) {
    ttsAudio.pause();
    ttsAudio = null;
  }
  cancelAnimationFrame(ttsAnimFrame);

  ttsAudio = new Audio(audioDataUrl);
  ttsAudio.playbackRate = TTS_SPEEDS[ttsSpeedIndex];

  const playBtn = ttsPlayer.querySelector(".lt-tts-play-btn");
  playBtn.disabled = false;

  const svgPlay = `<svg viewBox="0 0 24 24"><path d="M8 5v14l11-7z"/></svg>`;
  const svgPause = `<svg viewBox="0 0 24 24"><path d="M6 19h4V5H6v14zm8-14v14h4V5h-4z"/></svg>`;

  ttsAudio.addEventListener("play", () => {
    playBtn.innerHTML = svgPause;
    const miniPlay = ttsPlayer?.querySelector(".lt-tts-mini-play");
    if (miniPlay) miniPlay.innerHTML = svgPause;
    ttsUpdateProgress();
    if (ttsHighlightEnabled) ttsApplyHighlight();
  });

  ttsAudio.addEventListener("pause", () => {
    playBtn.innerHTML = svgPlay;
    const miniPlay = ttsPlayer?.querySelector(".lt-tts-mini-play");
    if (miniPlay) miniPlay.innerHTML = svgPlay;
    cancelAnimationFrame(ttsAnimFrame);
  });

  ttsAudio.addEventListener("ended", () => {
    playBtn.innerHTML = svgPlay;
    const miniPlay = ttsPlayer?.querySelector(".lt-tts-mini-play");
    if (miniPlay) miniPlay.innerHTML = svgPlay;
    cancelAnimationFrame(ttsAnimFrame);
    ttsSetProgress(1, ttsAudio.duration, ttsAudio.duration);
    ttsRemoveHighlight();
  });

  ttsAudio.addEventListener("loadedmetadata", () => {
    const total = ttsPlayer?.querySelector(".lt-tts-time-right");
    if (total) total.textContent = formatTime(ttsAudio.duration);
  });

  // Auto-play
  ttsAudio.play().catch(() => {});
}

function ttsUpdateProgress() {
  if (!ttsAudio || !ttsPlayer) return;
  const current = ttsAudio.currentTime;
  const duration = ttsAudio.duration || 0;
  const ratio = duration ? current / duration : 0;
  ttsSetProgress(ratio, current, duration);
  if (!ttsAudio.paused) {
    ttsAnimFrame = requestAnimationFrame(ttsUpdateProgress);
  }
}

function ttsSetProgress(ratio, current, duration) {
  if (!ttsPlayer) return;
  const pct = (ratio * 100).toFixed(1) + "%";

  const fill = ttsPlayer.querySelector(".lt-tts-scrubber-fill");
  if (fill) fill.style.width = pct;

  const miniFill = ttsPlayer.querySelector(".lt-tts-mini-progress-fill");
  if (miniFill) miniFill.style.width = pct;

  const timeLeft = ttsPlayer.querySelector(".lt-tts-time-left");
  if (timeLeft) timeLeft.textContent = formatTime(current);

  const timeRight = ttsPlayer.querySelector(".lt-tts-time-right");
  if (timeRight) timeRight.textContent = formatTime(duration);

  const miniTime = ttsPlayer.querySelector(".lt-tts-mini-time");
  if (miniTime) miniTime.textContent = formatTime(current);
}

function ttsOnError(error) {
  if (!ttsPlayer) return;
  ttsPlayer.className = "lt-tts-player lt-tts-state-error";
  const msg = ttsPlayer.querySelector(".lt-tts-error-msg");
  if (msg) msg.textContent = error || "Failed to generate audio";
}

function removeTTSPlayer() {
  if (ttsAudio) {
    ttsAudio.pause();
    ttsAudio = null;
  }
  cancelAnimationFrame(ttsAnimFrame);
  ttsRemoveHighlight();
  ttsHighlightRanges = [];
  if (ttsPlayer) {
    ttsPlayer.classList.add("lt-tts-exiting");
    setTimeout(() => {
      ttsPlayer?.remove();
      ttsPlayer = null;
    }, 250);
  }
}

// ─── Read-Along Highlighting ───────────────────────────────────────

function ttsApplyHighlight() {
  ttsRemoveHighlight();
  if (!ttsHighlightRanges.length) return;

  // Wrap each range's contents in a highlight span using CSS custom highlight or
  // a positioned overlay. We use an overlay approach that doesn't modify the DOM
  // (avoids breaking the page).
  ttsHighlightOverlay = document.createElement("div");
  ttsHighlightOverlay.className = "lt-tts-read-highlight-container";

  for (const range of ttsHighlightRanges) {
    const rects = range.getClientRects();
    for (const rect of rects) {
      const mark = document.createElement("div");
      mark.className = "lt-tts-read-highlight";
      mark.style.position = "fixed";
      mark.style.left = rect.left + "px";
      mark.style.top = rect.top + "px";
      mark.style.width = rect.width + "px";
      mark.style.height = rect.height + "px";
      ttsHighlightOverlay.appendChild(mark);
    }
  }

  document.body.appendChild(ttsHighlightOverlay);

  // Scroll the first highlighted rect into view
  const firstRange = ttsHighlightRanges[0];
  const firstRect = firstRange.getBoundingClientRect();
  if (firstRect.top < 0 || firstRect.bottom > window.innerHeight) {
    firstRange.startContainer.parentElement?.scrollIntoView({
      behavior: "smooth",
      block: "center",
    });
    // Reposition overlays after scroll
    setTimeout(ttsRepositionHighlights, 400);
  }

  // Reposition on scroll since overlays are fixed-positioned
  ttsHighlightOverlay._scrollHandler = () => ttsRepositionHighlights();
  window.addEventListener("scroll", ttsHighlightOverlay._scrollHandler, { passive: true });
}

function ttsRepositionHighlights() {
  if (!ttsHighlightOverlay || !ttsHighlightRanges.length) return;
  const marks = ttsHighlightOverlay.querySelectorAll(".lt-tts-read-highlight");
  let markIdx = 0;
  for (const range of ttsHighlightRanges) {
    const rects = range.getClientRects();
    for (const rect of rects) {
      if (markIdx < marks.length) {
        marks[markIdx].style.left = rect.left + "px";
        marks[markIdx].style.top = rect.top + "px";
        marks[markIdx].style.width = rect.width + "px";
        marks[markIdx].style.height = rect.height + "px";
      }
      markIdx++;
    }
  }
}

function ttsRemoveHighlight() {
  if (ttsHighlightOverlay) {
    if (ttsHighlightOverlay._scrollHandler) {
      window.removeEventListener("scroll", ttsHighlightOverlay._scrollHandler);
    }
    ttsHighlightOverlay.remove();
    ttsHighlightOverlay = null;
  }
}

function formatTime(seconds) {
  if (!seconds || !isFinite(seconds)) return "0:00";
  const m = Math.floor(seconds / 60);
  const s = Math.floor(seconds % 60);
  return m + ":" + String(s).padStart(2, "0");
}

// ─── Helpers ────────────────────────────────────────────────────────

function escapeHtml(str) {
  const div = document.createElement("div");
  div.textContent = str;
  return div.innerHTML;
}

function renderMarkdown(text) {
  let html = text
    .replace(/```(\w*)\n([\s\S]*?)```/g, "<pre><code>$2</code></pre>")
    .replace(/`([^`]+)`/g, "<code>$1</code>")
    .replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>")
    .replace(/\*([^*]+)\*/g, "<em>$1</em>")
    .replace(/^### (.+)$/gm, "<h4>$1</h4>")
    .replace(/^## (.+)$/gm, "<h3>$1</h3>")
    .replace(/^# (.+)$/gm, "<h2>$1</h2>")
    .replace(/^- (.+)$/gm, "<li>$1</li>")
    .replace(/^(\d+)\. (.+)$/gm, "<li>$2</li>")
    .replace(/\n\n/g, "</p><p>")
    .replace(/\n/g, "<br>");
  html = html.replace(/(<li>[\s\S]*?<\/li>)/g, (m) => `<ul>${m}</ul>`);
  html = html.replace(/<\/ul>\s*<ul>/g, "");
  return `<p>${html}</p>`;
}
