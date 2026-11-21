import assert from "node:assert/strict";
import fs from "node:fs/promises";
import path from "node:path";
import vm from "node:vm";

function styleDeclaration() {
  const values = new Map();
  const priorities = new Map();
  return {
    priorities, values,
    getPropertyValue(name) { return values.get(name) || ""; },
    getPropertyPriority(name) { return priorities.get(name) || ""; },
    setProperty(name, value, priority = "") {
      values.set(name, String(value));
      if (priority) priorities.set(name, String(priority));
      else priorities.delete(name);
    },
    removeProperty(name) { values.delete(name); priorities.delete(name); },
    [Symbol.iterator]() { return values.keys(); },
  };
}

function classList(initial) {
  const values = new Set(initial);
  const writes = [];
  return {
    values,
    writes,
    contains(value) { return values.has(value); },
    add(...names) { writes.push(["add", ...names]); names.forEach((name) => values.add(name)); },
    remove(...names) { writes.push(["remove", ...names]); names.forEach((name) => values.delete(name)); },
    toggle(name, enabled) { writes.push(["toggle", name, enabled]); if (enabled) values.add(name); else values.delete(name); },
  };
}

function makeFixture({
  nativeAppearance = "dark", settings = false, settingsPanel = false, adopted = true,
  generic = false, genericComposer = true, genericHome = false, genericSearch = false,
  modernMessages = false, modernComposerLayout = false,
  pathname = "/index.html", initialRoute = "",
} = {}) {
  const attrs = new Map();
  const rootStyle = styleDeclaration();
  const rootClasses = classList([nativeAppearance === "dark" ? "electron-dark" : "electron-light"]);
  const nodes = new Map();
  const domNodes = new Set();
  const selectorNodes = new Map();
  const observers = [];
  const timers = new Map();
  const intervals = new Map();
  const listeners = new Map();
  const revoked = [];
  let nextId = 0;
  let nextBlob = 0;
  const attributesFor = (values) => [...values].map(([name, value]) => ({ name, value }));
  const makeDomNode = (name, parentElement = null, values = new Map(), matchedSelectors = []) => {
    const selectorMatches = new Set(matchedSelectors);
    const node = {
      name,
      parentElement,
      style: styleDeclaration(),
      get attributes() { return attributesFor(values); },
      getAttribute(attribute) { return values.get(attribute) ?? null; },
      hasAttribute(attribute) { return values.has(attribute); },
      setAttribute(attribute, value) { values.set(attribute, String(value)); },
      removeAttribute(attribute) { values.delete(attribute); },
      appendChild(child) { child.parentElement = node; return child; },
      matches(selector) { return selectorMatches.has(selector); },
      closest(selector) {
        let current = node;
        while (current) {
          if (current.matches?.(selector)) return current;
          current = current.parentElement;
        }
        return null;
      },
      contains(candidate) {
        let current = candidate;
        while (current) {
          if (current === node) return true;
          current = current.parentElement;
        }
        return false;
      },
      querySelector(selector) {
        return [...domNodes].find((candidate) =>
          candidate !== node && node.contains(candidate) && candidate.matches?.(selector),
        ) || null;
      },
    };
    domNodes.add(node);
    return node;
  };
  const root = makeDomNode("root", null, attrs);
  root.classList = rootClasses;
  root.style = rootStyle;
  root.appendChild = (node) => {
    node.parentElement = root;
    if (node.id) nodes.set(node.id, node);
    return node;
  };
  const body = makeDomNode("body", root);
  body.appendChild = (node) => {
    node.parentElement = body;
    if (node.id) nodes.set(node.id, node);
    return node;
  };
  const register = (selector, node) => {
    const current = selectorNodes.get(selector) || [];
    current.push(node);
    selectorNodes.set(selector, current);
  };
  const partFixtures = {};
  if (!settings && !settingsPanel && generic) {
    const mainSelector = 'main, [role="main"]';
    const inputSelector = 'textarea, [contenteditable="true"], [role="textbox"]';
    const sidebarSelector = 'aside, nav[aria-label]';
    const composerSelector = '[data-testid*="composer" i], [data-testid*="prompt" i], ' +
      '[class*="composer" i], [class*="prompt" i]';
    const composerLayoutRootSelector = '[class*="_ComposerLayoutRoot_"]';
    const overlaySelector = '[role="dialog"], [aria-modal="true"]';
    partFixtures.shell = makeDomNode("generic-shell", body);
    partFixtures.sidebar = makeDomNode("generic-sidebar", partFixtures.shell, new Map(), [sidebarSelector]);
    partFixtures.main = makeDomNode("generic-main", partFixtures.shell, new Map(), [mainSelector]);
    if (genericComposer) {
      partFixtures.composer = makeDomNode(
        "generic-composer", partFixtures.main, new Map(),
        [modernComposerLayout ? composerLayoutRootSelector : composerSelector],
      );
      const inputParent = modernComposerLayout
        ? (partFixtures.composerFooter = makeDomNode(
          "generic-composer-footer", partFixtures.composer, new Map(), [composerSelector],
        ))
        : partFixtures.composer;
      partFixtures.input = makeDomNode("generic-input", inputParent, new Map(), [inputSelector]);
    }
    partFixtures.unrelatedAside = makeDomNode(
      "generic-content-aside", partFixtures.main, new Map(), [sidebarSelector],
    );
    partFixtures.dialog = makeDomNode("generic-dialog", partFixtures.main, new Map(), [overlaySelector]);
    partFixtures.dialogInput = makeDomNode(
      "generic-dialog-input", partFixtures.dialog, new Map(), [inputSelector],
    );
    if (genericSearch) {
      partFixtures.searchForm = makeDomNode("generic-search-form", partFixtures.main, new Map(), ["form"]);
      partFixtures.searchInput = makeDomNode(
        "generic-search-input", partFixtures.searchForm, new Map(), [inputSelector],
      );
    }
    register(mainSelector, partFixtures.main);
    if (genericSearch) register(inputSelector, partFixtures.searchInput);
    if (genericComposer) register(inputSelector, partFixtures.input);
    register(inputSelector, partFixtures.dialogInput);
    register(sidebarSelector, partFixtures.sidebar);
    register(sidebarSelector, partFixtures.unrelatedAside);
    if (genericHome) {
      partFixtures.homeIcon = makeDomNode("generic-home-icon", partFixtures.main);
      register('[data-testid="home-icon"]', partFixtures.homeIcon);
      register('[role="main"]:has([data-testid="home-icon"])', partFixtures.main);
      register('[role="main"]', partFixtures.main);
    }
  } else if (!settings && !settingsPanel) {
    partFixtures.sidebar = makeDomNode("sidebar", body);
    partFixtures.main = makeDomNode("main", body);
    partFixtures.header = makeDomNode("header", body);
    partFixtures.home = makeDomNode("home", partFixtures.main);
    partFixtures.homeHero = makeDomNode("home-hero", partFixtures.home);
    partFixtures.homeIcon = makeDomNode("home-icon", partFixtures.homeHero);
    partFixtures.projectList = makeDomNode("project-list", partFixtures.home);
    partFixtures.thread = makeDomNode("thread", partFixtures.main);
    partFixtures.legacyMessage = makeDomNode("legacy-message", partFixtures.thread);
    partFixtures.userMessage = makeDomNode(
      "user-message", partFixtures.thread,
      new Map([["data-local-conversation-user-anchor", "true"]]),
    );
    partFixtures.userMessageBubble = makeDomNode(
      "user-message-bubble", partFixtures.userMessage, new Map(),
      ['[class*="max-w-"][class*="rounded-2xl"][class*="text-start"]'],
    );
    partFixtures.assistantMessage = makeDomNode(
      "assistant-message", partFixtures.thread,
      new Map([["data-local-conversation-final-assistant", "true"]]),
    );
    partFixtures.composer = makeDomNode("composer", partFixtures.main);
    partFixtures.composerToolbar = makeDomNode("composer-toolbar", partFixtures.composer);
    register("aside.app-shell-left-panel", partFixtures.sidebar);
    register("main:is(.main-surface, [data-app-shell-main-surface], [class*=\"_MainContentSurface_\"])", partFixtures.main);
    register("header:is(.app-header-tint, [data-app-shell-header-edge-scroll], [data-app-shell-titlebar], [class*=\"_Header_\"])", partFixtures.header);
    register('[data-testid="home-icon"]', partFixtures.homeIcon);
    register('[data-feature="game-source"]', partFixtures.homeHero);
    register('[role="main"]:has([data-testid="home-icon"])', partFixtures.home);
    register('[role="main"]', partFixtures.home);
    register(".group\\/project-selector", partFixtures.projectList);
    register(".thread-scroll-container", partFixtures.thread);
    const messageSelector =
      ':is([data-message-author-role], [data-local-conversation-user-anchor], [data-local-conversation-final-assistant])';
    register(messageSelector, partFixtures.legacyMessage);
    if (modernMessages) {
      register(messageSelector, partFixtures.userMessage);
      register(messageSelector, partFixtures.assistantMessage);
    }
    register(':is(.composer-surface-chrome, [class*="_ComposerLayoutRoot_"], [data-composer-surface-variant][data-composer-radius-variant])', partFixtures.composer);
    register(':is(.composer-surface-chrome [class*="_footer_"], [class*="_ComposerLayoutRoot_"] [class*="_ComposerLayoutFooter_"], [data-composer-surface-variant][data-composer-radius-variant] :is([data-composer-footer-responsive], [class*="_ComposerLayoutFooter_"], [class*="_footer_"]))', partFixtures.composerToolbar);
  }
  const makeStyleNode = () => {
    const node = {
      id: "",
      textContent: "",
      parentElement: null,
      dataset: {},
      remove() { if (node.id) nodes.delete(node.id); node.parentElement = null; },
    };
    return node;
  };
  const makeVideoNode = () => {
    const values = new Map();
    const node = {
      id: "",
      dataset: {},
      parentElement: null,
      paused: false,
      readyState: 4,
      pauseCalls: 0,
      playCalls: 0,
      src: "",
      get attributes() { return attributesFor(values); },
      getAttribute(attribute) { return values.get(attribute) ?? null; },
      setAttribute(attribute, value) { values.set(attribute, String(value)); },
      removeAttribute(attribute) { values.delete(attribute); },
      addEventListener(type, callback) { listeners.set("video:" + type, callback); },
      removeEventListener(type) { listeners.delete("video:" + type); },
      play() { node.paused = false; node.playCalls += 1; return Promise.resolve(); },
      pause() { node.paused = true; node.pauseCalls += 1; },
      remove() { if (node.id) nodes.delete(node.id); node.parentElement = null; },
    };
    return node;
  };
  const makeLayerNode = () => {
    const values = new Map();
    const node = {
      id: "",
      dataset: {},
      parentElement: null,
      get attributes() { return attributesFor(values); },
      getAttribute(attribute) { return values.get(attribute) ?? null; },
      setAttribute(attribute, value) { values.set(attribute, String(value)); },
      removeAttribute(attribute) { values.delete(attribute); },
      remove() { if (node.id) nodes.delete(node.id); node.parentElement = null; },
    };
    return node;
  };
  const makeFrameNode = () => {
    const values = new Map();
    const messages = [];
    const node = {
      id: "",
      dataset: {},
      parentElement: null,
      src: "",
      contentWindow: {
        messages,
        postMessage(message, origin) { messages.push({ message, origin }); },
      },
      get attributes() { return attributesFor(values); },
      getAttribute(attribute) { return values.get(attribute) ?? null; },
      setAttribute(attribute, value) { values.set(attribute, String(value)); },
      removeAttribute(attribute) { values.delete(attribute); },
      remove() { if (node.id) nodes.delete(node.id); node.parentElement = null; },
    };
    return node;
  };
  const document = {
    documentElement: root,
    head: root,
    body,
    hidden: false,
    adoptedStyleSheets: adopted ? [] : undefined,
    createElement(tag) {
      if (tag === "style") return makeStyleNode();
      if (tag === "video") return makeVideoNode();
      if (tag === "img") return Object.assign(makeVideoNode(), { complete: true, naturalWidth: 1280, naturalHeight: 720 });
      if (tag === "iframe") return makeFrameNode();
      if (tag === "div") return makeLayerNode();
      return { tagName: tag };
    },
    getElementById(id) { return nodes.get(id) || null; },
    addEventListener(type, callback) { listeners.set("document:" + type, callback); },
    removeEventListener(type) { listeners.delete("document:" + type); },
    querySelector(selector) {
      if (settingsPanel && selector === '[data-settings-panel-slug="general-settings"]') {
        return makeDomNode("settings:general-settings", body);
      }
      if (settings && (selector.includes("appearance-theme") || selector.includes("theme-preview"))) {
        return makeDomNode(`settings:${selector}`, body);
      }
      return (selectorNodes.get(selector) || [])[0] || null;
    },
    querySelectorAll(selector) {
      if (selector === "[data-ds-part]") {
        return [...domNodes].filter((node) => node.getAttribute?.("data-ds-part") !== null);
      }
      return [...(selectorNodes.get(selector) || [])];
    },
  };
  const navigation = {
    addEventListener(type, callback) { listeners.set(`navigation:${type}`, callback); },
    removeEventListener(type) { listeners.delete(`navigation:${type}`); },
  };
  class MockMutationObserver {
    constructor(callback) { this.callback = callback; this.options = null; this.observations = []; observers.push(this); }
    observe(target, options) { this.target = target; this.options = options; this.observations.push({ target, options }); }
    disconnect() { this.disconnected = true; }
  }
  class MockSheet {
    replaceSync(text) { this.text = text; }
  }
  const window = {
    navigation,
    matchMedia() {
      return {
        matches: nativeAppearance === "dark",
        addEventListener(type, callback) { listeners.set(`media:${type}`, callback); },
        removeEventListener(type) { listeners.delete(`media:${type}`); },
      };
    },
    addEventListener(type, callback) { listeners.set("window:" + type, callback); },
    removeEventListener(type) { listeners.delete("window:" + type); },
  };
  const context = {
    window,
    document,
    location: {
      protocol: "app:",
      pathname,
      search: initialRoute ? `?initialRoute=${encodeURIComponent(initialRoute)}` : "",
    },
    MutationObserver: MockMutationObserver,
    CSSStyleSheet: adopted ? MockSheet : undefined,
    Blob,
    Uint8Array,
    atob,
    URL: class FixtureURL extends URL {
      static createObjectURL() { nextBlob += 1; return `blob:fixture-${nextBlob}`; }
      static revokeObjectURL(value) { revoked.push(value); }
    },
    URLSearchParams,
    performance: { now: () => 1 },
    setTimeout(callback, delay) { const id = ++nextId; timers.set(id, { callback, delay }); return id; },
    clearTimeout(id) { timers.delete(id); },
    setInterval(callback, delay) { const id = ++nextId; intervals.set(id, { callback, delay }); return id; },
    clearInterval(id) { intervals.delete(id); },
    console,
  };
  const payloadFor = (theme = {}, cssText = ".fixture { color: red; }") => {
    const template = fixture.template;
    return template
      .replace("__DREAM_SKIN_CSS_JSON__", JSON.stringify(cssText))
      .replace("__DREAM_SKIN_ART_JSON__", JSON.stringify("data:image/png;base64,AA=="))
      .replace("__DREAM_SKIN_THEME_JSON__", JSON.stringify({ id: "fixture", appearance: "auto", ...theme }))
      .replace("__DREAM_SKIN_VERSION_JSON__", JSON.stringify("test"))
      .replace("__DREAM_SKIN_STYLE_REVISION_JSON__", JSON.stringify("css-rev"))
      .replace("__DREAM_SKIN_PAYLOAD_REVISION_JSON__", JSON.stringify("payload-rev"));
  };
  const flushTimers = (maximumDelay = Infinity) => {
    for (const [id, timer] of [...timers]) {
      if (timer.delay <= maximumDelay) { timers.delete(id); timer.callback(); }
    }
  };
  const addDynamicMessage = () => {
    const messageSelector = [...selectorNodes.keys()].find((selector) =>
      selector.includes("data-message-author-role"),
    ) || '[data-message-author-role]';
    const node = makeDomNode(`message-${(selectorNodes.get(messageSelector) || []).length + 1}`, partFixtures.thread || body);
    register(messageSelector, node);
    return node;
  };
  return {
    addDynamicMessage, attrs, context, document, domNodes, flushTimers, intervals, listeners,
    nodes, observers, partFixtures, payloadFor, revoked, root, rootClasses, rootStyle, timers, window,
  };
}


const fixture = {};
export { makeFixture, fixture };
