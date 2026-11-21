// Local wallpaper renderer. Preserve native Codex layout, colors, fonts and controls.
((cssText, artDataUrl, themeConfig) => {
  const SELECTOR_CONTRACT = {"schema":"codex-dream-skin-selectors/1","selectors":[{"key":"shell-main","selector":"main:is(.main-surface, [data-app-shell-main-surface], [class*=\"_MainContentSurface_\"])","tier":"L1","scope":"all","required":true},{"key":"left-panel","selector":"aside.app-shell-left-panel","tier":"L1","scope":"all","required":true},{"key":"header-tint","selector":"header:is(.app-header-tint, [data-app-shell-header-edge-scroll], [data-app-shell-titlebar], [class*=\"_Header_\"])","tier":"L1","scope":"all","required":true},{"key":"main-content-top-fade","selector":":is(.app-shell-main-content-top-fade, [data-app-shell-main-content-top-fade], [class*=\"_MainContentTopFade_\"])","tier":"L2","scope":"all","required":false},{"key":"home-icon","selector":"[data-testid=\"home-icon\"]","tier":"L1","scope":"home","required":true},{"key":"home-route","selector":"[role=\"main\"]:has([data-testid=\"home-icon\"])","tier":"L1","scope":"home","required":true},{"key":"home-route-css","selector":"[role=\"main\"]","tier":"L1","scope":"home","required":true},{"key":"home-banners","selector":".home-banners","tier":"L2","scope":"home","required":false},{"key":"composer-chrome","selector":":is(.composer-surface-chrome, [class*=\"_ComposerLayoutRoot_\"], [data-composer-surface-variant][data-composer-radius-variant])","tier":"L2","scope":"home+thread","required":false},{"key":"composer-toolbar","selector":":is(.composer-surface-chrome [class*=\"_footer_\"], [class*=\"_ComposerLayoutRoot_\"] [class*=\"_ComposerLayoutFooter_\"], [data-composer-surface-variant][data-composer-radius-variant] :is([data-composer-footer-responsive], [class*=\"_ComposerLayoutFooter_\"], [class*=\"_footer_\"]))","tier":"L2","scope":"home+thread","required":false},{"key":"home-utility","selector":":is([class*=\"_homeUtilityBar_\"], [class*=\"_ComposerHomeUtilityBar_\"])","tier":"L2","scope":"home","required":false},{"key":"game-source","selector":"[data-feature=\"game-source\"]","tier":"L2","scope":"home","required":false},{"key":"home-suggestions","selector":".group\\/home-suggestions","tier":"L2","scope":"home","required":false},{"key":"project-selector","selector":".group\\/project-selector","tier":"L2","scope":"home config","required":false},{"key":"markdown","selector":"[class*=\"_markdown\"]","tier":"L2","scope":"thread","required":false},{"key":"thread-surface","selector":".thread-scroll-container","tier":"L2","scope":"thread","required":false},{"key":"message","selector":":is([data-message-author-role], [data-local-conversation-user-anchor], [data-local-conversation-final-assistant])","tier":"L2","scope":"thread","required":false},{"key":"settings-panel","selector":"[data-settings-panel-slug=\"general-settings\"]","tier":"L2","scope":"settings","required":false},{"key":"appearance-radio","selector":"input[name=\"appearance-theme\"]","tier":"L2","scope":"settings","required":false},{"key":"overlay-menu","selector":"[role=\"menu\"]","tier":"L2","scope":"overlay","required":false},{"key":"overlay-dialog","selector":"[role=\"dialog\"]","tier":"L2","scope":"overlay","required":false},{"key":"overlay-popper","selector":"[data-radix-popper-content-wrapper]","tier":"L2","scope":"overlay","required":false}],"stableTestids":["app-shell-header-context-menu-surface","home-icon","theme-preview"]};
  const STATE_KEY = "__CODEX_DREAM_SKIN_STATE__";
  const DISABLED_KEY = "__CODEX_DREAM_SKIN_DISABLED__";
  const STYLE_REGISTRY_KEY = "__CODEX_DREAM_SKIN_STYLE_SHEETS__";
  const STYLE_ID = "codex-dream-skin-style";
  const VIDEO_ID = "codex-dream-skin-video-frame";
  const VIDEO_OVERLAY_ID = "codex-dream-skin-video-overlay";
  const SHELL_ATTR = "data-dream-shell";
  const PART_ATTR = "data-ds-part";
  const ROOT_ATTRS = [
    "data-dream-skin", SHELL_ATTR,
    "data-dream-art-wide", "data-dream-art-safe", "data-dream-task-mode",
    "data-dream-art-safe-area", "data-dream-art-task-mode", "data-dream-art-aspect",
    "data-dream-art-ready",
    "data-dream-video-scope", "data-dream-video-state",
  ];
  const initialRoute = new URLSearchParams(String(location.search || ""))
    .get("initialRoute") || "";
  const pathname = String(location.pathname || "");
  const excludedPetSurface = location.protocol === "app:" && (
    pathname.endsWith("/avatar-overlay-composition-surface.html") ||
    initialRoute === "/avatar-overlay" || initialRoute.startsWith("/avatar-overlay/")
  );
  if (excludedPetSurface) {
    const previous = window[STATE_KEY];
    if (typeof previous?.cleanup === "function") previous.cleanup();
    window[DISABLED_KEY] = true;
    return;
  }
  const VERSION = __DREAM_SKIN_VERSION_JSON__;
  const STYLE_REVISION = __DREAM_SKIN_STYLE_REVISION_JSON__;
  const PAYLOAD_REVISION = __DREAM_SKIN_PAYLOAD_REVISION_JSON__;
  const THEME = themeConfig && typeof themeConfig === "object" ? themeConfig : {};
  const VIDEO = THEME.video && typeof THEME.video === "object" ? THEME.video : null;
  const selectorByKey = new Map(SELECTOR_CONTRACT.selectors.map((entry) => [entry.key, entry]));
  const stableTestidSelector = (testid) => SELECTOR_CONTRACT.stableTestids?.includes(testid)
    ? `[data-testid="${testid}"]` : null;
  const installToken = `${Date.now()}-${Math.random()}`;
  let rootObserver = null;
  let partObserver = null;
  let bodyReadyHandler = null;
  let styleMode = null;
  let styleNode = null;
  let styleSheet = null;
  let videoFrame = null;
  let imageLayer = null;
  let videoOverlay = null;
  let videoVisibilityHandler = null;
  let videoMessageHandler = null;
  let lastVideoTime = null;
  let lastVideoProgressAt = 0;
  let lastVideoRecoveryAt = -Infinity;
  const now = () => typeof performance === "object" && typeof performance.now === "function"
    ? performance.now() : Date.now();
  const metrics = {
    ensureCalls: 0,
    rootPasses: 0,
    routePasses: 0,
    layoutReads: 0,
    attributeWrites: 0,
    styleWrites: 0,
    styleRepairs: 0,
    partPasses: 0,
    partWrites: 0,
    navigationEvents: 0,
    safetyPasses: 0,
    firstEnsureMs: null,
  };

  const previous = window[STATE_KEY];
  if (typeof previous?.cleanup === "function") previous.cleanup();
  window[DISABLED_KEY] = false;

  const existingStyleRegistry = window[STYLE_REGISTRY_KEY];
  const styleRegistry = existingStyleRegistry instanceof Set ? existingStyleRegistry : new Set();
  window[STYLE_REGISTRY_KEY] = styleRegistry;
  const artUrl = (() => {
    const comma = artDataUrl.indexOf(",");
    const mime = /^data:([^;,]+)/.exec(artDataUrl)?.[1] || "image/png";
    const binary = atob(artDataUrl.slice(comma + 1));
    const bytes = new Uint8Array(binary.length);
    for (let index = 0; index < binary.length; index += 1) bytes[index] = binary.charCodeAt(index);
    return URL.createObjectURL(new Blob([bytes], { type: mime }));
  })();

  const setAttribute = (root, name, value) => {
    const normalized = String(value);
    if (root.getAttribute(name) !== normalized) {
      root.setAttribute(name, normalized);
      metrics.attributeWrites += 1;
    }
  };

  const detectShellAppearance = () => {
    const root = document.documentElement;
    if (root?.classList?.contains("electron-dark")) return "dark";
    if (root?.classList?.contains("electron-light")) return "light";
    try { return window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light"; } catch {}
    return "light";
  };

  const resolvedShell = () => {
    if (THEME.appearance === "light" || THEME.appearance === "dark") return THEME.appearance;
    // Follow the native Codex appearance without changing its theme.
    return detectShellAppearance();
  };

  const installStyle = () => {
    try {
      if (!("adoptedStyleSheets" in document) || typeof CSSStyleSheet !== "function") {
        throw new Error("Constructable stylesheets are unavailable");
      }
      const sheet = new CSSStyleSheet();
      if (typeof sheet.replaceSync !== "function") throw new Error("replaceSync is unavailable");
      sheet.replaceSync(cssText);
      const retained = [...document.adoptedStyleSheets]
        .filter((candidate) => !styleRegistry.has(candidate));
      document.adoptedStyleSheets = [...retained, sheet];
      styleRegistry.clear();
      styleRegistry.add(sheet);
      document.getElementById(STYLE_ID)?.remove();
      styleSheet = sheet;
      styleMode = "adopted";
      return;
    } catch {
      styleSheet = null;
    }

    styleNode = document.getElementById(STYLE_ID) || document.createElement("style");
    styleNode.id = STYLE_ID;
    styleNode.textContent = cssText;
    if (!styleNode.parentElement) (document.head || document.documentElement).appendChild(styleNode);
    styleMode = "style";
  };

  const ensureStyle = () => {
    if (styleMode === "adopted" && styleSheet) {
      const current = [...document.adoptedStyleSheets];
      if (!current.includes(styleSheet)) {
        document.adoptedStyleSheets = [...current, styleSheet];
        metrics.styleRepairs += 1;
      }
      return;
    }
    if (styleNode && document.getElementById(STYLE_ID) !== styleNode) {
      document.getElementById(STYLE_ID)?.remove();
      (document.head || document.documentElement).appendChild(styleNode);
      metrics.styleRepairs += 1;
    }
  };

  installStyle();

  const applyRootState = (root) => {
    metrics.rootPasses += 1;
    ensureStyle();
    const shell = resolvedShell();
    setAttribute(root, "data-dream-skin", "active");
    setAttribute(root, SHELL_ATTR, shell);
    return shell;
  };

  const selectorHit = (key) => {
    const selector = selectorByKey.get(key)?.selector;
    if (!selector) return false;
    try { return Boolean(document.querySelector(selector)); } catch { return false; }
  };

  // Codex keeps hidden dialogs and menus mounted (for example 26.1117 has
  // display:none "Chat preview" hover cards and 0x0 native popover menus), so
  // an overlay counts only when one of its nodes is actually visible.
  const selectorVisibleHit = (key) => {
    const selector = selectorByKey.get(key)?.selector;
    if (!selector) return false;
    let nodes;
    try { nodes = document.querySelectorAll(selector); } catch { return false; }
    for (const node of nodes) {
      if (typeof node.checkVisibility === "function" &&
        !node.checkVisibility({ checkVisibilityCSS: true, checkOpacity: true })) continue;
      const rect = node.getBoundingClientRect?.();
      if (rect && (rect.width < 1 || rect.height < 1)) continue;
      return true;
    }
    return false;
  };

  const stableTestidHit = (testid) => {
    const selector = stableTestidSelector(testid);
    if (!selector) return false;
    try { return Boolean(document.querySelector(selector)); } catch { return false; }
  };

  const partNodes = new Set();
  const queryAll = (selector) => {
    if (!selector) return [];
    try { return [...document.querySelectorAll(selector)]; } catch { return []; }
  };
  const selectorNodes = (key) => queryAll(selectorByKey.get(key)?.selector);
  const genericNodes = (selector) => queryAll(selector)
    .filter((node) => node && typeof node.setAttribute === "function");
  const genericInputNodes = () => genericNodes(
    'textarea, [contenteditable="true"], [role="textbox"]',
  ).filter((node) => !node.closest?.('[role="dialog"], [aria-modal="true"]'));
  const resolvedMainNode = () => {
    const exact = selectorNodes("shell-main")[0];
    if (exact) return exact;
    for (const input of genericInputNodes()) {
      const main = input.closest?.('main, [role="main"]');
      if (main && typeof main.setAttribute === "function") return main;
    }
    return genericNodes('main, [role="main"]')
      .find((node) => !node.closest?.('[role="dialog"], [aria-modal="true"]')) ?? null;
  };
  const fallbackMainNodes = () => selectorNodes("shell-main").length
    ? [] : [resolvedMainNode()].filter(Boolean);
  const fallbackSidebarNodes = () => {
    if (selectorNodes("left-panel").length) return [];
    const main = resolvedMainNode();
    const mainParent = main?.parentElement;
    if (!main || !mainParent) return [];
    const candidate = genericNodes('aside, nav[aria-label]')
      .filter((node) => !main.contains?.(node))
      .filter((node) => !node.closest?.('[role="dialog"], [aria-modal="true"]'))
      .find((node) => node.parentElement === mainParent
        || node.parentElement?.parentElement === mainParent
        || node.parentElement === mainParent.parentElement);
    return candidate ? [candidate] : [];
  };
  const fallbackComposerNodes = () => selectorNodes("composer-chrome").length
    ? [] : (() => {
      const main = resolvedMainNode();
      for (const input of genericInputNodes()) {
        if (main && !main.contains?.(input)) continue;
        const layoutRoot = input.closest?.('[class*="_ComposerLayoutRoot_"]');
        if (layoutRoot && (!main || main.contains?.(layoutRoot))) return [layoutRoot];
        const semanticOwner = input.closest?.(
          '.composer-surface-chrome, [data-composer-surface-variant][data-composer-radius-variant], ' +
          '[class*="_ComposerLayoutRoot_"]',
        );
        if (semanticOwner && (!main || main.contains?.(semanticOwner))) return [semanticOwner];
        const ownerSelector =
          '[data-testid*="composer" i], [data-testid*="prompt" i], ' +
          '[class*="composer" i], [class*="prompt" i]';
        const nearest = input.closest?.(ownerSelector);
        if (!nearest || (main && !main.contains?.(nearest))) continue;
        let owner = nearest;
        for (let parent = nearest.parentElement; parent && parent !== main;
          parent = parent.parentElement) {
          if (parent.matches?.(ownerSelector)) owner = parent;
        }
        return [owner];
      }
      return [];
    })();
  const fallbackComposerToolbarNodes = (composerNodes) => {
    if (selectorNodes("composer-toolbar").length || !composerNodes.length) return [];
    return genericNodes(
      '[data-composer-footer-responsive], [class*="_ComposerLayoutFooter_"], [class*="_footer_"]',
    ).filter((node) => composerNodes.some((composer) =>
      composer !== node && composer.contains?.(node)));
  };
  const addPart = (desired, part, nodes) => {
    for (const node of nodes) {
      if (node && typeof node.setAttribute === "function" && !desired.has(node)) {
        desired.set(node, part);
      }
    }
  };
  const resolvedMessageNodes = () => selectorNodes("message").map((node) => {
    if (!node?.hasAttribute?.("data-local-conversation-user-anchor")) return node;
    // Current Codex user anchors span the conversation column. Prefer the
    // adaptive native bubble, while retaining the older anchor as a fallback.
    return node.querySelector?.(
      '[class*="max-w-"][class*="rounded-2xl"][class*="text-start"]',
    ) ?? node;
  });
  const refreshParts = () => {
    metrics.partPasses += 1;
    const desired = new Map();
    addPart(desired, "root", [document.documentElement]);
    addPart(desired, "sidebar", [...selectorNodes("left-panel"), ...fallbackSidebarNodes()]);
    addPart(desired, "header", selectorNodes("header-tint"));
    // Route-specific parts win when a generic shell collapses home and main
    // onto the same element.
    addPart(desired, "home", selectorNodes("home-route"));
    addPart(desired, "main", [...selectorNodes("shell-main"), ...fallbackMainNodes()]);
    addPart(desired, "project-list", selectorNodes("project-selector"));
    addPart(desired, "thread", selectorNodes("thread-surface"));
    addPart(desired, "message", resolvedMessageNodes());
    const composerNodes = [...selectorNodes("composer-chrome"), ...fallbackComposerNodes()];
    addPart(desired, "composer", composerNodes);
    addPart(desired, "composer-toolbar", [
      ...selectorNodes("composer-toolbar"), ...fallbackComposerToolbarNodes(composerNodes),
    ]);
    addPart(desired, "dialog", selectorNodes("overlay-dialog"));
    const homeHero = selectorNodes("game-source")[0] ??
      selectorNodes("home-icon")[0]?.parentElement;
    addPart(desired, "home-hero", homeHero ? [homeHero] : []);

    for (const node of partNodes) {
      if (!desired.has(node)) {
        node.removeAttribute?.(PART_ATTR);
        metrics.partWrites += 1;
      }
    }
    partNodes.clear();
    for (const [node, part] of desired) {
      if (node.getAttribute?.(PART_ATTR) !== part) {
        node.setAttribute(PART_ATTR, part);
        metrics.partWrites += 1;
      }
      partNodes.add(node);
    }
  };

  const removeParts = () => {
    for (const node of partNodes) node.removeAttribute?.(PART_ATTR);
    partNodes.clear();
    for (const node of queryAll(`[${PART_ATTR}]`)) node.removeAttribute?.(PART_ATTR);
  };

  const scopeMatches = (scope, baseState, overlay) => {
    const active = new Set([baseState]);
    if (baseState !== "settings") active.add("all");
    if (overlay) active.add("overlay");
    const tokens = String(scope || "all").toLowerCase().match(/[a-z]+/g) || ["all"];
    return tokens.some((token) => token !== "config" && active.has(token));
  };

  const detectScope = () => {
    const overlay = selectorVisibleHit("overlay-menu") || selectorVisibleHit("overlay-dialog") ||
      selectorVisibleHit("overlay-popper");
    let baseState = "thread";
    if (selectorHit("settings-panel") || selectorHit("appearance-radio") ||
      stableTestidHit("theme-preview")) baseState = "settings";
    else if (selectorHit("home-icon") || selectorHit("home-route")) baseState = "home";
    else if (!selectorHit("shell-main") && !document.querySelector('main, [role="main"]')) baseState = "settings";
    const missingL1 = SELECTOR_CONTRACT.selectors
      .filter((entry) => entry.tier === "L1" && entry.required &&
        scopeMatches(entry.scope, baseState, overlay) && !selectorHit(entry.key))
      .map((entry) => entry.key);
    return {
      state: overlay ? "overlay" : baseState,
      baseState,
      overlay,
      // Settings replaces (or partially replaces) the app shell on macOS and
      // can retain a shell on Windows.  It is therefore always an L0 scope;
      // never treat the absence of the home/thread L1 anchors as a failure.
      level: baseState === "settings" || missingL1.length ? "L0" : "L1",
      missingL1,
    };
  };

  const refreshScope = () => {
    metrics.routePasses += 1;
    const scope = detectScope();
    const state = window[STATE_KEY];
    if (state?.installToken === installToken) state.scope = scope;
    if (VIDEO?.url) setAttribute(document.documentElement, "data-dream-video-scope", scope.baseState);
    return scope;
  };

  const validVideoConfig = () => {
    if (!VIDEO?.url || typeof VIDEO.url !== "string") return null;
    try {
      const parsed = new URL(VIDEO.url);
      if (parsed.protocol !== "http:" || parsed.hostname !== "127.0.0.1" ||
        !/^\/[a-f0-9]{64}\/video\.mp4$/.test(parsed.pathname) || parsed.search || parsed.hash) {
        return null;
      }
      const mediaUrl = parsed.href;
      parsed.pathname = parsed.pathname.replace(/\/video\.mp4$/, "/player.html");
      return { mediaUrl, playerUrl: parsed.href, origin: parsed.origin };
    } catch {
      return null;
    }
  };

  const ensureVideoLayer = () => {
    const config = validVideoConfig();
    if (!config || !document.body || videoFrame) return;
    videoFrame = document.createElement("video");
    videoFrame.id = VIDEO_ID;
    videoFrame.muted = true;
    videoFrame.defaultMuted = true;
    videoFrame.loop = true;
    videoFrame.playsInline = true;
    videoFrame.controls = false;
    videoFrame.preload = "auto";
    videoFrame.setAttribute("aria-hidden", "true");
    videoFrame.setAttribute("tabindex", "-1");
    videoOverlay = document.createElement("div");
    videoOverlay.id = VIDEO_OVERLAY_ID;
    videoOverlay.setAttribute?.("aria-hidden", "true");
    const setVideoState = (value) => {
      const state = window[STATE_KEY];
      if (state?.installToken === installToken && !window[DISABLED_KEY]) {
        setAttribute(document.documentElement, "data-dream-video-state", value);
      }
    };
    setVideoState("loading");
    const videoHandlers = {
      playing: () => setVideoState("playing"),
      pause: () => setVideoState("paused"),
      error: () => setVideoState("error"),
    };
    for (const [event, handler] of Object.entries(videoHandlers)) videoFrame.addEventListener(event, handler);
    document.body.appendChild(videoFrame);
    document.body.appendChild(videoOverlay);
    videoVisibilityHandler = () => {
      if (!videoFrame?.src || window[DISABLED_KEY]) return;
      if (document.hidden) videoFrame.pause();
      else videoFrame.play().catch(() => setVideoState("error"));
    };
    document.addEventListener("visibilitychange", videoVisibilityHandler);
    const state = window[STATE_KEY];
    if (state?.installToken === installToken) {
      state.videoFrame = videoFrame;
      state.videoOverlay = videoOverlay;
      state.videoVisibilityHandler = videoVisibilityHandler;
      state.videoHandlers = videoHandlers;
      state.attachVideoBlob = (url) => {
        if (window[STATE_KEY]?.installToken !== installToken || window[DISABLED_KEY]) return false;
        if (typeof url !== "string" || !url.startsWith("blob:")) throw new Error("Expected local media Blob");
        videoFrame.src = url;
        videoVisibilityHandler();
        return true;
      };
    }
  };

  const ensureImageLayer = () => {
    if (VIDEO || !document.body || imageLayer) return;
    imageLayer = document.createElement("img");
    imageLayer.id = "codex-dream-skin-image";
    imageLayer.setAttribute("aria-hidden", "true");
    imageLayer.setAttribute("alt", "");
    imageLayer.setAttribute("draggable", "false");
    imageLayer.src = artUrl;
    if (Number.isFinite(themeConfig?.imageOpacity)) imageLayer.setAttribute("style", "opacity: " + String(Math.max(0, Math.min(1, themeConfig.imageOpacity))) + ";");
    videoOverlay = document.createElement("div");
    videoOverlay.id = VIDEO_OVERLAY_ID;
    videoOverlay.setAttribute?.("aria-hidden", "true");
    if (Number.isFinite(themeConfig?.imageShade)) videoOverlay.setAttribute("style", "opacity: " + String(Math.max(0, Math.min(1, themeConfig.imageShade))) + ";");
    document.body.appendChild(imageLayer);
    document.body.appendChild(videoOverlay);
    const state = window[STATE_KEY];
    if (state?.installToken === installToken) {
      state.imageLayer = imageLayer;
      state.videoOverlay = videoOverlay;
    }
  };

  const repairMedia = () => {
    if (!document.body || window[DISABLED_KEY]) return;
    ensureVideoLayer();
    ensureImageLayer();
    for (const layer of [imageLayer, videoFrame, videoOverlay]) {
      if (layer && layer.parentElement !== document.body) document.body.appendChild(layer);
    }
    if (imageLayer && imageLayer.src !== artUrl) imageLayer.src = artUrl;
    const state = window[STATE_KEY];
    if (!videoFrame || !state?.videoBlobUrl) return;
    if (videoFrame.src !== state.videoBlobUrl) videoFrame.src = state.videoBlobUrl;
  };

  const recoverPlayback = () => {
    if (!videoFrame?.src || window[DISABLED_KEY]) return;
    const timestamp = now();
    if (document.hidden) {
      lastVideoProgressAt = timestamp;
      lastVideoTime = null;
      return;
    }
    if (lastVideoTime === null || videoFrame.currentTime !== lastVideoTime) {
      lastVideoTime = videoFrame.currentTime;
      lastVideoProgressAt = timestamp;
    }
    const stalled = timestamp - lastVideoProgressAt >= 15000;
    if (!(videoFrame.error || videoFrame.paused || stalled) ||
      timestamp - lastVideoRecoveryAt < 15000) return;
    lastVideoRecoveryAt = timestamp;
    lastVideoProgressAt = timestamp;
    if (videoFrame.error || stalled) videoFrame.load();
    videoFrame.play().catch(() => {});
  };

  const ensure = ({ root: rootPass = true, scope: scopePass = false, parts: partPass = false } = {}) => {
    if (window[DISABLED_KEY]) return;
    const root = document.documentElement;
    if (!root) return;
    metrics.ensureCalls += 1;
    if (rootPass) applyRootState(root);
    if (partPass) refreshParts();
    if (scopePass) refreshScope();
    repairMedia();
  };

  const cleanup = () => {
    const state = window[STATE_KEY];
    if (state?.installToken !== installToken) return false;
    window[DISABLED_KEY] = true;
    const root = document.documentElement;
    for (const name of ROOT_ATTRS) root?.removeAttribute(name);
    for (const attribute of [...(root?.attributes || [])]) {
      if (attribute.name.startsWith("data-dream-")) root.removeAttribute(attribute.name);
    }
    removeParts();
    state?.rootObserver?.disconnect();
    state?.partObserver?.disconnect();
    if (bodyReadyHandler && typeof document.removeEventListener === "function") {
      document.removeEventListener("DOMContentLoaded", bodyReadyHandler);
    }
    if (state?.timer) clearInterval(state.timer);
    if (state?.scheduler?.timeout) clearTimeout(state.scheduler.timeout);
    if (state?.mediaHandler && state?.mediaQuery) {
      try { state.mediaQuery.removeEventListener("change", state.mediaHandler); } catch {}
    }
    if (state?.navigationHandler && state?.navigation) {
      try { state.navigation.removeEventListener("navigate", state.navigationHandler); } catch {}
    }
    if (state?.videoVisibilityHandler) {
      try { document.removeEventListener("visibilitychange", state.videoVisibilityHandler); } catch {}
    }
    if (state?.videoMessageHandler) {
      try { window.removeEventListener("message", state.videoMessageHandler); } catch {}
    }
    if (state?.videoFrame) {
      for (const [event, handler] of Object.entries(state.videoHandlers || {})) {
        state.videoFrame.removeEventListener(event, handler);
      }
      try { state.videoFrame.pause(); } catch {}
      state.videoFrame.removeAttribute?.("src");
      try { state.videoFrame.load(); } catch {}
      state.videoFrame.remove?.();
    }
    delete state.videoUpload;
    if (state.videoBlobUrl) URL.revokeObjectURL(state.videoBlobUrl);
    state.videoBlobUrl = null;
    state.videoBlobKey = null;
    state?.videoOverlay?.remove?.();
    state?.imageLayer?.removeAttribute?.("src");
    state?.imageLayer?.remove?.();
    if (styleSheet) {
      try {
        document.adoptedStyleSheets = [...document.adoptedStyleSheets]
          .filter((candidate) => candidate !== styleSheet);
      } catch {}
      styleRegistry.delete(styleSheet);
    }
    styleNode?.remove();
    if (document.getElementById(STYLE_ID) === styleNode) document.getElementById(STYLE_ID)?.remove();
    if (styleRegistry.size === 0) delete window[STYLE_REGISTRY_KEY];
    if (state?.artUrl) URL.revokeObjectURL(state.artUrl);
    delete window[STATE_KEY];
    return true;
  };

  const scheduler = { timeout: null, root: false, scope: false, parts: false };
  const flushScheduledEnsure = () => {
    if (scheduler.timeout) clearTimeout(scheduler.timeout);
    scheduler.timeout = null;
    const pending = { root: scheduler.root, scope: scheduler.scope, parts: scheduler.parts };
    scheduler.root = false;
    scheduler.scope = false;
    scheduler.parts = false;
    ensure(pending);
  };
  const scheduleEnsure = ({ root = false, scope = false, parts = false } = {}, delay = 64) => {
    scheduler.root ||= root;
    scheduler.scope ||= scope;
    scheduler.parts ||= parts;
    if (scheduler.timeout) return;
    scheduler.timeout = setTimeout(flushScheduledEnsure, delay);
  };
  if (typeof MutationObserver === "function") {
    rootObserver = new MutationObserver(() => scheduleEnsure({ root: true }));
    // SPA route changes are observable as DOM mutations even when Chromium's
    // Navigation API emits no event. Keep verification scope and public parts
    // derived from the same post-mutation tree.
    partObserver = new MutationObserver(() => scheduleEnsure({ scope: true, parts: true }, 80));
  }

  let mediaQuery = null;
  let mediaHandler = null;
  try {
    mediaQuery = window.matchMedia("(prefers-color-scheme: dark)");
    mediaHandler = () => scheduleEnsure({ root: true });
  } catch {}

  const navigationApi = window.navigation && typeof window.navigation.addEventListener === "function"
    ? window.navigation : null;
  const navigationHandler = navigationApi ? () => {
    metrics.navigationEvents += 1;
    scheduleEnsure({ scope: true, parts: true }, 180);
  } : null;

  window[STATE_KEY] = {
    ensure,
    cleanup,
    rootObserver,
    partObserver,
    timer: null,
    scheduler,
    mediaQuery,
    mediaHandler,
    navigation: navigationApi,
    navigationHandler,
    artUrl,
    installToken,
    styleMode,
    styleNode,
    styleSheet,
    styleRevision: STYLE_REVISION,
    scope: null,
    selectorsSchema: SELECTOR_CONTRACT.schema,
    metrics,
    version: VERSION,
    themeId: THEME.id || "custom",
    revision: PAYLOAD_REVISION,
    detectShellAppearance,
    videoFrame: null,
    videoOverlay: null,
    videoVisibilityHandler: null,
    videoMessageHandler: null,
    videoOrigin: null,
  };
  const firstEnsureStartedAt = now();
  ensure({ root: true, parts: true });
  const initialScope = refreshScope();
  metrics.firstEnsureMs = Number((now() - firstEnsureStartedAt).toFixed(3));

  const observeAttributes = (node) => {
    if (!rootObserver || !node) return;
    rootObserver.observe(node, {
      attributes: true,
      attributeFilter: ["class", "data-theme", "data-appearance", "data-color-mode"],
    });
  };
  const observePartTree = (node) => {
    if (!partObserver || !node) return;
    partObserver.observe(node, { childList: true, subtree: true });
  };
  observeAttributes(document.documentElement);
  const observeBody = () => {
    ensureVideoLayer();
    ensureImageLayer();
    observeAttributes(document.body);
    observePartTree(document.body);
  };
  if (document.body) observeBody();
  else if (typeof document.addEventListener === "function") {
    bodyReadyHandler = () => {
      if (!window[DISABLED_KEY]) {
        observeBody();
        scheduleEnsure({ scope: true, parts: true }, 0);
      }
    };
    document.addEventListener("DOMContentLoaded", bodyReadyHandler, { once: true });
  }
  const timer = setInterval(() => {
    metrics.safetyPasses += 1;
    ensure({ root: true });
    recoverPlayback();
  }, 5000);
  window[STATE_KEY].timer = timer;
  if (mediaHandler && mediaQuery && typeof mediaQuery.addEventListener === "function") {
    mediaQuery.addEventListener("change", mediaHandler);
  }
  if (navigationHandler && navigationApi) {
    navigationApi.addEventListener("navigate", navigationHandler);
  }
  return {
    installed: true,
    version: VERSION,
    themeId: THEME.id || "custom",
    revision: PAYLOAD_REVISION,
    shell: resolvedShell(),
    scope: initialScope,
    styleMode,
  };
})(__DREAM_SKIN_CSS_JSON__, __DREAM_SKIN_ART_JSON__, __DREAM_SKIN_THEME_JSON__)
