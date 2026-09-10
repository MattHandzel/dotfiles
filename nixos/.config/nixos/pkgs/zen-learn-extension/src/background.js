// Learn This — Background Script
// Context menus, quick capture, YouTube capture, routing to Claude.ai or inline panel

const MENU_ITEMS = [
  {
    id: "learn-examples",
    title: "Learn: Give me examples",
    prompt: `I selected this text from an article I'm reading. Give me 3-5 concrete, varied examples of this concept in action. Make the examples specific and from different domains so I can see the pattern.

For each example:
- Describe the situation concretely (not abstractly)
- Show how the concept applies
- Note what's similar and different from the other examples

Selected text: "{selection}"

Article context (use this for relevant background):
{page_context}`,
  },
  {
    id: "learn-abstract",
    title: "Learn: Make it abstract / find the principle",
    prompt: `I selected this text from an article I'm reading. Help me extract the abstract principle or mental model underneath this specific instance. I want to understand the GENERAL pattern, not just this specific case.

1. State the abstract principle in one sentence
2. Explain why this principle works (the mechanism)
3. Give 2 examples from completely different domains where the same principle applies
4. What are the boundary conditions — when does this principle NOT apply?

Selected text: "{selection}"

Article context:
{page_context}`,
  },
  {
    id: "learn-explain",
    title: "Learn: Explain this deeply",
    prompt: `I selected this text from an article I'm reading. I want to deeply understand it — not just what it says, but WHY it's true and HOW it works.

1. Explain the concept as if I understand the basics but not the nuances
2. What's the mechanism — why does this work the way it does?
3. What's the most common misconception about this?
4. How does this connect to related concepts I might already know?
5. What would change if one key assumption were different?

Selected text: "{selection}"

Article context:
{page_context}`,
  },
  {
    id: "learn-connect",
    title: "Learn: Connect to what I know",
    prompt: `I selected this text from an article I'm reading. Help me connect this to concepts I might already know from other fields. I want to build bridges between domains.

1. What existing mental models or frameworks does this relate to?
2. What's an analogy from a completely different field?
3. Does this contradict or refine anything that's commonly believed?
4. If I had to teach this using only concepts from everyday life, how would I explain it?

Selected text: "{selection}"

Article context:
{page_context}`,
  },
  {
    id: "learn-steelman",
    title: "Learn: Steel-man and challenge this",
    prompt: `I selected this text from an article I'm reading. I want to stress-test this claim. Help me think critically about it.

1. What's the strongest version of this argument (steel-man it)?
2. What's the strongest counterargument?
3. What evidence would change my mind about this?
4. What are the hidden assumptions?
5. Under what conditions would the opposite be true?

Selected text: "{selection}"

Article context:
{page_context}`,
  },
  {
    id: "learn-context",
    title: "Learn: Add context (who/what/why)",
    prompt: `I selected this text from an article I'm reading. I need relevant background context to fully understand it. Help me understand the references, people, terms, and ideas mentioned.

For each notable reference in the selection:
1. Who or what is being referenced? Give a brief, concrete identification.
2. Why is this reference relevant here — what's the connection to the argument being made?
3. What prerequisite knowledge would help me understand this better?

Also:
- If there are technical terms or jargon, define them plainly.
- If there are historical events or debates being alluded to, summarize them.
- If there are implicit assumptions the author expects the reader to know, surface them.

Selected text: "{selection}"

Article context:
{page_context}`,
  },
];

// ─── Context Menu Setup ─────────────────────────────────────────────

browser.runtime.onInstalled.addListener(() => {
  // Parent menu
  browser.contextMenus.create({
    id: "learn-this-parent",
    title: "Learn This",
    contexts: ["selection"],
  });

  // Learn actions
  for (const item of MENU_ITEMS) {
    browser.contextMenus.create({
      id: item.id,
      parentId: "learn-this-parent",
      title: item.title.replace("Learn: ", ""),
      contexts: ["selection"],
    });
  }

  browser.contextMenus.create({
    id: "learn-sep-1",
    parentId: "learn-this-parent",
    type: "separator",
    contexts: ["selection"],
  });

  // Capture actions
  browser.contextMenus.create({
    id: "capture-selection",
    parentId: "learn-this-parent",
    title: "Capture this (save to vault)",
    contexts: ["selection"],
  });

  browser.contextMenus.create({
    id: "capture-selection-learn",
    parentId: "learn-this-parent",
    title: "Capture + tag #learn (generate cards)",
    contexts: ["selection"],
  });

  browser.contextMenus.create({
    id: "capture-reading-list",
    parentId: "learn-this-parent",
    title: "Add to Reading List",
    contexts: ["selection"],
  });

  browser.contextMenus.create({
    id: "learn-sep-2",
    parentId: "learn-this-parent",
    type: "separator",
    contexts: ["selection"],
  });

  browser.contextMenus.create({
    id: "tts-read-aloud",
    parentId: "learn-this-parent",
    title: "Read aloud",
    contexts: ["selection"],
  });

  browser.contextMenus.create({
    id: "learn-claude",
    parentId: "learn-this-parent",
    title: "Open in Claude.ai (full conversation)",
    contexts: ["selection"],
  });
});

// ─── Keyboard Shortcut ──────────────────────────────────────────────

browser.commands.onCommand.addListener(async (command) => {
  if (command === "quick-capture") {
    const [tab] = await browser.tabs.query({
      active: true,
      currentWindow: true,
    });
    if (tab) {
      browser.tabs.sendMessage(tab.id, { type: "SHOW_CAPTURE_POPUP" });
    }
  }
});

// ─── Context Menu Click Handler ─────────────────────────────────────

browser.contextMenus.onClicked.addListener(async (info, tab) => {
  const selection = info.selectionText || "";
  if (!selection) return;

  // Get page context from content script
  let pageContext = "";
  try {
    const results = await browser.tabs.sendMessage(tab.id, {
      type: "GET_PAGE_CONTEXT",
    });
    pageContext = results?.context || "";
  } catch {
    pageContext = `Page: ${tab.title}\nURL: ${tab.url}`;
  }

  // ── Capture actions ──
  if (
    info.menuItemId === "capture-selection" ||
    info.menuItemId === "capture-selection-learn" ||
    info.menuItemId === "capture-reading-list"
  ) {
    const addLearnTag = info.menuItemId === "capture-selection-learn";
    const addReadingList = info.menuItemId === "capture-reading-list";
    browser.tabs.sendMessage(tab.id, {
      type: "SHOW_CAPTURE_POPUP",
      selection: selection,
      autoLearn: addLearnTag,
      autoReadingList: addReadingList,
      pageTitle: tab.title,
      pageUrl: tab.url,
    });
    return;
  }

  // ── Read aloud (TTS) ──
  if (info.menuItemId === "tts-read-aloud") {
    browser.tabs.sendMessage(tab.id, {
      type: "SHOW_TTS_PLAYER",
      text: selection,
    });
    generateTTS(selection).then((audioDataUrl) => {
      browser.tabs.sendMessage(tab.id, {
        type: "TTS_AUDIO_READY",
        audioDataUrl,
        text: selection,
      });
    }).catch((err) => {
      browser.tabs.sendMessage(tab.id, {
        type: "TTS_ERROR",
        error: err.message,
      });
    });
    return;
  }

  // ── Open in Claude ──
  if (info.menuItemId === "learn-claude") {
    const menuItem = MENU_ITEMS.find((m) => m.id === "learn-explain");
    const prompt = buildPrompt(menuItem.prompt, selection, pageContext);
    openInClaude(prompt);
    return;
  }

  // ── Learn actions ──
  const menuItem = MENU_ITEMS.find((m) => m.id === info.menuItemId);
  if (!menuItem) return;

  const prompt = buildPrompt(menuItem.prompt, selection, pageContext);

  const settings = await browser.storage.local.get({
    defaultAction: "claude",
    ollamaHost: "",
    ollamaModel: "gemma3:12b-it-qat",
    kmsCapture: true,
  });

  if (settings.defaultAction === "claude" || !settings.ollamaHost) {
    openInClaude(prompt);
  } else {
    const ollamaPrompt = buildPromptForOllama(
      menuItem.prompt,
      selection,
      pageContext
    );
    try {
      browser.tabs.sendMessage(tab.id, {
        type: "SHOW_PANEL",
        loading: true,
        title: menuItem.title,
        selection: selection,
      });

      const response = await callOllama(
        settings.ollamaHost,
        settings.ollamaModel,
        ollamaPrompt
      );

      browser.tabs.sendMessage(tab.id, {
        type: "SHOW_PANEL",
        loading: false,
        title: menuItem.title,
        selection: selection,
        content: response,
        promptForClaude: prompt,
      });
    } catch {
      openInClaude(prompt);
    }
  }

  if (settings.kmsCapture) {
    saveToKMS(selection, menuItem.title, tab.title, tab.url);
  }
});

// ─── Message Handler (from content scripts) ─────────────────────────

browser.runtime.onMessage.addListener(async (message, sender) => {
  if (message.type === "SUBMIT_CAPTURE") {
    return await submitCapture(message.data);
  }
  if (message.type === "GET_TAG_SUGGESTIONS") {
    return await getTagSuggestions(message.content);
  }
  if (message.type === "CAPTURE_YOUTUBE_MOMENT") {
    return await captureYouTubeMoment(message.data, sender.tab);
  }
  if (message.type === "REQUEST_TTS") {
    try {
      const audioDataUrl = await generateTTS(message.text);
      return { success: true, audioDataUrl };
    } catch (err) {
      return { success: false, error: err.message };
    }
  }
});

// ─── TTS Generation ────────────────────────────────────────────────

async function generateTTS(text) {
  const settings = await browser.storage.local.get({
    ttsHost: "http://100.118.206.104:47773",
    ttsVoice: "en_US-lessac-high",
    ttsSpeed: 0.95,
  });

  const payload = JSON.stringify({
    text,
    input_format: "text",
    voice: settings.ttsVoice,
    format: "mp3",
    speed: settings.ttsSpeed,
  });

  // Try fetch first (works when server has CORS headers),
  // fall back to XHR which bypasses CORS preflight in MV2 background pages.
  let blob;
  try {
    const resp = await fetch(`${settings.ttsHost}/speak`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: payload,
      signal: AbortSignal.timeout(120000),
    });
    if (!resp.ok) throw new Error(`TTS server returned ${resp.status}`);
    blob = await resp.blob();
  } catch (fetchErr) {
    blob = await new Promise((resolve, reject) => {
      const xhr = new XMLHttpRequest();
      xhr.open("POST", `${settings.ttsHost}/speak`);
      xhr.setRequestHeader("Content-Type", "application/json");
      xhr.responseType = "blob";
      xhr.timeout = 120000;
      xhr.onload = () => {
        if (xhr.status >= 200 && xhr.status < 300) resolve(xhr.response);
        else reject(new Error(`TTS server returned ${xhr.status}`));
      };
      xhr.onerror = () => reject(new Error("Network error connecting to TTS server"));
      xhr.ontimeout = () => reject(new Error("TTS request timed out"));
      xhr.send(payload);
    });
  }

  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onloadend = () => resolve(reader.result);
    reader.onerror = reject;
    reader.readAsDataURL(blob);
  });
}

// ─── Capture Submission ─────────────────────────────────────────────

async function submitCapture(data) {
  const settings = await browser.storage.local.get({
    kmsHost: "http://localhost:5391",
  });

  const formData = new FormData();
  formData.append("content", data.content || "");
  formData.append("clipboard", data.clipboard || "");
  formData.append("sources", data.sources || "");
  formData.append("tags", data.tags || "");
  formData.append("context", data.context || "");
  formData.append("modalities", data.modalities || "text,clipboard");
  formData.append("alias", data.alias || "");

  try {
    const resp = await fetch(`${settings.kmsHost}/api/capture`, {
      method: "POST",
      body: formData,
      signal: AbortSignal.timeout(10000),
    });

    if (resp.ok) {
      const result = await resp.json();
      // Show brief success notification
      browser.notifications.create({
        type: "basic",
        title: "Captured",
        message: `Saved to vault${data.tags.includes("learn") ? " (will generate cards)" : ""}`,
        iconUrl: "icons/learn-48.svg",
      });
      return { success: true, result };
    } else {
      const err = await resp.text();
      return { success: false, error: err };
    }
  } catch (err) {
    return { success: false, error: err.message };
  }
}

async function getTagSuggestions(content) {
  const settings = await browser.storage.local.get({
    kmsHost: "http://localhost:5391",
  });

  try {
    // Use existing KMS AI suggestions endpoint
    const resp = await fetch(
      `${settings.kmsHost}/api/ai-suggestions/tags?content=${encodeURIComponent(content.substring(0, 1000))}`,
      { signal: AbortSignal.timeout(5000) }
    );
    if (resp.ok) {
      const data = await resp.json();
      return { tags: data.suggestions || data.tags || [] };
    }
  } catch {
    // KMS not available
  }
  return { tags: [] };
}

async function captureYouTubeMoment(data, tab) {
  const settings = await browser.storage.local.get({
    kmsHost: "http://localhost:5391",
  });

  const formData = new FormData();
  formData.append(
    "content",
    data.thoughts
      ? `${data.thoughts}\n\n## Video Moment\n${data.videoTitle} at ${data.timestamp}\n${data.url}`
      : `## Video Moment\n${data.videoTitle} at ${data.timestamp}\n${data.url}`
  );
  formData.append("clipboard", data.transcript || "");
  formData.append("sources", data.url);
  formData.append("tags", data.tags || "learn,video-capture");
  formData.append("context", `Watching: ${data.videoTitle}`);
  formData.append("modalities", "text,clipboard");
  formData.append("alias", `${data.videoTitle} @ ${data.timestamp}`);

  try {
    const resp = await fetch(`${settings.kmsHost}/api/capture`, {
      method: "POST",
      body: formData,
      signal: AbortSignal.timeout(10000),
    });

    if (resp.ok) {
      browser.notifications.create({
        type: "basic",
        title: "Video Moment Captured",
        message: `${data.videoTitle} @ ${data.timestamp}`,
        iconUrl: "icons/learn-48.svg",
      });
      return { success: true };
    }
  } catch (err) {
    return { success: false, error: err.message };
  }
}

// ─── KMS Save (for learn actions) ───────────────────────────────────

async function saveToKMS(selection, action, pageTitle, pageUrl) {
  const settings = await browser.storage.local.get({
    kmsHost: "http://localhost:5391",
  });

  const formData = new FormData();
  formData.append("content", `${action}\n\nSelected: "${selection}"`);
  formData.append("sources", pageUrl);
  formData.append("tags", "learn,browser-capture");
  formData.append("context", `Reading: ${pageTitle}`);
  formData.append("modalities", "text,clipboard");

  try {
    await fetch(`${settings.kmsHost}/api/capture`, {
      method: "POST",
      body: formData,
      signal: AbortSignal.timeout(5000),
    });
  } catch {
    // Silent fail
  }
}

// ─── Helpers ────────────────────────────────────────────────────────

function buildPrompt(template, selection, pageContext) {
  return template
    .replace("{selection}", selection)
    .replace("{page_context}", pageContext);
}

function buildPromptForOllama(template, selection, pageContext) {
  const maxContext = 4000;
  const truncated =
    pageContext.length > maxContext
      ? pageContext.substring(0, maxContext) + "\n[...truncated]"
      : pageContext;
  return template
    .replace("{selection}", selection)
    .replace("{page_context}", truncated);
}

function openInClaude(prompt) {
  const encoded = encodeURIComponent(prompt);
  browser.tabs.create({
    url: `https://claude.ai/new?q=${encoded}`,
  });
}

async function callOllama(host, model, prompt) {
  const resp = await fetch(`${host}/api/generate`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      model,
      prompt,
      stream: false,
      options: { temperature: 0.5, num_predict: 1024 },
    }),
    signal: AbortSignal.timeout(30000),
  });
  const data = await resp.json();
  return data.response || "No response from model.";
}
