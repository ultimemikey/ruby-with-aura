(function (global) {
  "use strict";

  var ACTION_ENDPOINT = "/_aura/action";

  var REF_ATTR = "data-aura-ref";
  var PORTAL_ATTR = "data-aura-portal";
  var CLIENT_ATTR = "data-aura-client";
  var ISLAND_ATTR = "data-aura-island";
  var HYDRATE_ATTR = "data-aura-hydrate";
  var HYDRATED_ATTR = "data-aura-hydrated";
  var STATIC_ATTR = "data-aura-static";
  var BIND_ATTR = "data-bind";
  var FLUSH_MARKER = "aflush";
  var SUSPENSE_ATTR = "data-aura-suspense";
  var SUSPENSE_CHUNK_ATTR = "data-aura-suspense-chunk";

  var CLIENT_SELECTOR = "[" + CLIENT_ATTR + '="1"]';
  var ISLAND_SELECTOR = "[" + ISLAND_ATTR + "][" + HYDRATE_ATTR + '="1"]';

  function hasKey(node) {
    return (
      node &&
      node.nodeType === 1 &&
      node.hasAttribute &&
      node.hasAttribute("data-aura-key")
    );
  }

  function keyOf(node) {
    return hasKey(node) ? node.getAttribute("data-aura-key") : null;
  }

  function isStatic(node) {
    return !!(
      node &&
      node.nodeType === 1 &&
      node.hasAttribute &&
      node.hasAttribute(STATIC_ATTR)
    );
  }

  function isFlushMarker(node) {
    return (
      !!node &&
      node.nodeType === 8 &&
      String(node.nodeValue == null ? "" : node.nodeValue).trim() === FLUSH_MARKER
    );
  }

  function patchNode(from, to) {
    if (!from || !to) return;
    if (isStatic(from) || isStatic(to)) return;

    if (isFlushMarker(from) || isFlushMarker(to)) return;

    if (from.nodeType !== to.nodeType) {
      from.parentNode.replaceChild(clone(to, from), from);
      return;
    }

    if (from.nodeType === 3 || from.nodeType === 8) {
      if (from.nodeValue !== to.nodeValue) from.nodeValue = to.nodeValue;
      return;
    }

    if (from.nodeType !== 1) return;

    if (from.tagName !== to.tagName) {
      from.parentNode.replaceChild(clone(to, from), from);
      return;
    }

    syncAttributes(from, to);
    reconcile(from, childrenOf(to));
  }

  function clone(templateNode, referenceNode) {
    var doc =
      (referenceNode && referenceNode.ownerDocument) ||
      (typeof document !== "undefined" ? document : null);
    if (doc && doc.importNode) return doc.importNode(templateNode, true);
    return templateNode.cloneNode(true);
  }

  function syncAttributes(from, to) {
    var i, attr, name;

    for (i = from.attributes.length - 1; i >= 0; i--) {
      name = from.attributes[i].name;
      if (!to.hasAttribute(name)) from.removeAttribute(name);
    }

    for (i = 0; i < to.attributes.length; i++) {
      attr = to.attributes[i];
      if (from.getAttribute(attr.name) !== attr.value) {
        try {
          from.setAttribute(attr.name, attr.value);
        } catch (e) {

        }
      }
    }

    if (from.tagName === "INPUT" || from.tagName === "TEXTAREA") {
      var value = to.getAttribute ? to.getAttribute("value") : null;
      if (value !== null && from.value !== value) {
        from.value = value;
      }
      if (to.hasAttribute && to.hasAttribute("checked")) {
        from.checked = true;
      }
    }
  }

  function childrenOf(node) {
    return Array.prototype.slice.call(node.childNodes);
  }

  function reconcile(container, templateNodes) {
    var oldNodes = childrenOf(container);

    var oldKeyed = Object.create(null);
    var oldUnkeyed = [];
    oldNodes.forEach(function (node) {
      var key = keyOf(node);
      if (key === null) {
        oldUnkeyed.push(node);
      } else if (!(key in oldKeyed)) {
        oldKeyed[key] = node;
      }
    });

    var placed = [];
    var unkeyedIndex = 0;

    templateNodes.forEach(function (template) {
      var key = keyOf(template);
      var node = null;

      if (key !== null && oldKeyed[key]) {
        node = oldKeyed[key];
        delete oldKeyed[key];
        patchNode(node, template);
      } else if (key === null && unkeyedIndex < oldUnkeyed.length) {
        node = oldUnkeyed[unkeyedIndex++];
        patchNode(node, template);
      } else {
        node = clone(template, container);
      }

      placed.push(node);
    });

    for (var i = 0; i < placed.length; i++) {
      var current = container.childNodes[i];
      if (current !== placed[i]) {
        container.insertBefore(placed[i], current || null);
      }
    }

    while (container.childNodes.length > placed.length) {
      container.removeChild(container.lastChild);
    }
  }

  function ref(name) {
    if (typeof document === "undefined" || !document.querySelector) return null;
    var safe = String(name).replace(/["\\]/g, "\\$&");
    return document.querySelector("[" + REF_ATTR + '="' + safe + '"]');
  }

  function collectRefs() {
    var out = Object.create(null);
    if (typeof document === "undefined" || !document.querySelectorAll) return out;
    var els = document.querySelectorAll("[" + REF_ATTR + "]");
    Array.prototype.forEach.call(els, function (el) {
      var n = el.getAttribute && el.getAttribute(REF_ATTR);
      if (n && !(n in out)) out[n] = el;
    });
    return out;
  }

  function readBoundValue(el) {
    if (!el) return undefined;
    var type = (el.type || "").toLowerCase();
    if (type === "checkbox") return !!el.checked;
    if (type === "radio") return el.checked ? el.value : undefined;
    if (el.value !== undefined) return el.value;
    return el.textContent;
  }

  function writeBoundValue(el, value) {
    if (!el) return;
    var type = (el.type || "").toLowerCase();
    var tag = (el.tagName || "").toLowerCase();
    if (type === "checkbox") {
      el.checked = !!value;
      return;
    }
    if (type === "radio") {
      el.checked = String(el.value) === String(value);
      return;
    }
    var str = value === null || value === undefined ? "" : String(value);
    if (tag === "textarea" || el.value !== undefined) {
      el.value = str;
    } else {
      el.textContent = str;
    }
  }

  function auraBind(event, el) {
    var target = el && el.nodeType === 1 ? el : resolveTarget(event);
    if (!target || !target.getAttribute) return Promise.resolve();
    var name = target.getAttribute(BIND_ATTR);
    if (!name) return Promise.resolve();
    var value = readBoundValue(target);
    if (value === undefined) return Promise.resolve();
    return auraCall("__aura_bind", event, { field: name, value: value });
  }

  function optimistic(name, value) {
    if (typeof document === "undefined" || !document.querySelectorAll) return;
    var safe = String(name).replace(/["\\]/g, "\\$&");
    var els = document.querySelectorAll("[" + BIND_ATTR + '="' + safe + '"]');
    Array.prototype.forEach.call(els, function (el) {
      writeBoundValue(el, value);
    });
  }

  var lastState = Object.create(null);

  function parseHeaderJson(response, name) {
    try {
      var raw = response.headers && response.headers.get(name);
      if (!raw) return null;
      return JSON.parse(raw);
    } catch (e) {
      return null;
    }
  }

  function applyServerPatches(response) {
    var diff = parseHeaderJson(response, "x-aura-state");
    if (diff) {
      for (var key in diff) lastState[key] = diff[key];
    }

    var updates = parseHeaderJson(response, "x-aura-optimistic");
    if (updates) {
      for (var field in updates) optimistic(field, updates[field]);
    }

    return diff;
  }

  function isHydrationRoot(el) {
    if (!el || !el.hasAttribute) return false;
    if (el.hasAttribute(CLIENT_ATTR)) return true;
    return el.hasAttribute(ISLAND_ATTR) && el.getAttribute(HYDRATE_ATTR) === "1";
  }

  function bindElement(el) {
    if (!el || !el.addEventListener) return;
    if (el.__auraBound) return;

    var events = [];
    if (el.hasAttribute && el.hasAttribute("oninput")) events.push("input");
    if (el.hasAttribute && el.hasAttribute("onchange")) events.push("change");
    if (events.length === 0) {
      var type = (el.type || "").toLowerCase();
      var tag = (el.tagName || "").toLowerCase();
      if (type === "checkbox" || type === "radio" || tag === "select") {
        events.push("change");
      } else {
        events.push("input");
      }
    }
    events.forEach(function (evt) {
      el.addEventListener(evt, auraBind);
    });
    try {
      el.__auraBound = true;
    } catch (e) {

    }
  }

  function hydrateSubtree(sub) {
    if (!sub || isStatic(sub)) return;
    if (sub.getAttribute && sub.getAttribute(HYDRATED_ATTR) === "1") return;

    if (sub.querySelectorAll) {
      var fields = sub.querySelectorAll("[" + BIND_ATTR + "]");
      Array.prototype.forEach.call(fields, bindElement);
    }
    if (sub.hasAttribute && sub.hasAttribute(BIND_ATTR)) bindElement(sub);

    if (sub.setAttribute) sub.setAttribute(HYDRATED_ATTR, "1");
  }

  function hydrate(root) {
    if (typeof document === "undefined") return;
    var scope = root || document.body || document.documentElement;
    if (!scope) return;

    var candidates = [];
    if (scope.nodeType === 1 && isHydrationRoot(scope)) candidates.push(scope);
    if (scope.querySelectorAll) {
      var found = scope.querySelectorAll(CLIENT_SELECTOR + ", " + ISLAND_SELECTOR);
      Array.prototype.forEach.call(found, function (n) {
        candidates.push(n);
      });
    }
    candidates.forEach(function (sub) {
      if (isStatic(sub)) return;
      hydrateSubtree(sub);
    });
  }

  function resolveContainer(target) {
    if (target && target.nodeType === 1) return target;
    if (typeof document === "undefined") return null;
    if (!target) return document.body || document.documentElement || null;
    if (typeof target === "string") {
      var found = null;
      try {
        found = document.querySelector(target);
      } catch (e) {
        found = null;
      }
      return found || document.body || document.documentElement || null;
    }
    return document.body || null;
  }

  function applyPortals(root) {
    if (typeof document === "undefined") return;
    var scope = root || document;
    if (!scope || !scope.querySelectorAll) return;

    var nodes = scope.querySelectorAll("[" + PORTAL_ATTR + "]");
    Array.prototype.forEach.call(nodes, function (node) {
      var target = node.getAttribute(PORTAL_ATTR) || "body";
      var dest = resolveContainer(target);
      if (dest && node.parentNode && dest !== node.parentNode) {
        dest.appendChild(node);
      }
    });
  }

  function parseFragment(html) {
    if (html == null) return [];
    if (typeof html === "string") {
      if (typeof DOMParser === "undefined") return [];
      var parsed = new DOMParser().parseFromString(html, "text/html");
      if (!parsed || !parsed.body) return [];
      html = childrenOf(parsed.body);
    } else if (html.nodeType && !html.length) {
      html = [html];
    }
    return Array.prototype.filter.call(html, function (node) {
      return !isFlushMarker(node);
    });
  }

  function appendHtml(html, target) {
    var nodes = parseFragment(html);
    var container = resolveContainer(target);
    if (!container || typeof container.appendChild !== "function") return nodes;

    nodes.forEach(function (node) {
      container.appendChild(node);
    });
    applyPortals(container);
    hydrate(container);
    return nodes;
  }

  function findByAttr(attr, value) {
    if (typeof document === "undefined") return null;
    var nodes = document.querySelectorAll("[" + attr + "]");
    for (var i = 0; i < nodes.length; i++) {
      if (nodes[i].getAttribute(attr) === value) return nodes[i];
    }
    return null;
  }

  function suspenseSwap(id) {
    if (typeof document === "undefined") return;
    var key = String(id == null ? "" : id);
    var chunk = findByAttr(SUSPENSE_CHUNK_ATTR, key);
    var boundary = findByAttr(SUSPENSE_ATTR, key);
    if (!chunk || !boundary) return;

    boundary.innerHTML = chunk.innerHTML;
    if (chunk.parentNode) chunk.parentNode.removeChild(chunk);
    applyPortals(boundary);
    hydrate(boundary);
  }

  function applyHtml(html) {
    if (typeof DOMParser === "undefined") return;

    var parsed = new DOMParser().parseFromString(html, "text/html");
    if (!parsed || !parsed.body) return;

    var newTitle = parsed.querySelector("title");
    if (newTitle && typeof document !== "undefined" && document.title !== newTitle.textContent) {
      document.title = newTitle.textContent;
    }

    var lang = parsed.documentElement && parsed.documentElement.getAttribute("lang");
    if (lang && typeof document !== "undefined") {
      document.documentElement.setAttribute("lang", lang);
    }

    if (typeof document !== "undefined" && document.body) {
      reconcile(document.body, childrenOf(parsed.body));

      applyPortals(document.body);
      hydrate(document.body);
    }
  }

  function collectForm(form) {
    var out = {};
    Array.prototype.forEach.call(form.elements, function (el) {
      if (!el.name) return;
      if (el.type === "checkbox") {
        out[el.name] = !!el.checked;
      } else if (el.type === "radio") {
        if (el.checked) out[el.name] = el.value;
      } else if (el.type !== "submit" && el.type !== "button") {
        out[el.name] = el.value;
      }
    });
    return out;
  }

  function resolveTarget(event) {
    if (!event) return null;
    var el = event.currentTarget || event.target || null;
    if (el && el.nodeType === 3) el = el.parentNode;
    return el;
  }

  function buildPayload(handler, event) {
    var payload = { handler: handler, csrf: global.__AURA_CSRF || null };
    var el = resolveTarget(event);
    if (!el || !el.getAttribute) return payload;

    var boundField = el.getAttribute(BIND_ATTR);
    if (boundField) {
      var boundValue = readBoundValue(el);
      payload.field = boundField;
      payload.value = boundValue === undefined ? null : boundValue;
      return payload;
    }

    var form = el.form || (el.closest ? el.closest("form") : null);
    if (form) {
      payload.form = collectForm(form);
      return payload;
    }

    if (el.value !== undefined) payload.value = el.value;
    return payload;
  }

  function isNativeFormSubmit(event) {
    if (!event || event.type !== "submit") return false;
    var form = event.currentTarget || event.target;
    if (!form || !form.getAttribute) return false;
    return form.getAttribute("action") === ACTION_ENDPOINT;
  }

  function auraCall(handler, event, override) {
    var isBind = handler === "__aura_bind";
    if (
      event &&
      typeof event.preventDefault === "function" &&
      !isBind &&
      !isNativeFormSubmit(event)
    ) {
      event.preventDefault();
    }

    var payload = buildPayload(handler, event);
    if (override) {
      if ("field" in override) payload.field = override.field;
      if ("value" in override) payload.value = override.value;
    }

    if (typeof global.fetch !== "function") return Promise.resolve();

    return global
      .fetch(ACTION_ENDPOINT, {
        method: "POST",
        headers: {
          "content-type": "application/json",
          accept: "text/html"
        },
        credentials: "same-origin",
        body: JSON.stringify(payload)
      })
      .then(function (response) {
        var token = response.headers.get("x-csrf-token");
        if (token) global.__AURA_CSRF = token;
        applyServerPatches(response);
        return response.text();
      })
      .then(function (html) {
        applyHtml(html);
        return html;
      });
  }

  var prefetchCache = Object.create(null);

  function isNavigable(link) {
    if (!link || !link.getAttribute) return false;
    if (link.target && link.target !== "_self") return false;
    if (link.hasAttribute("download")) return false;
    if (link.hasAttribute("data-aura-no-nav")) return false;

    var href = link.getAttribute("href");
    if (!href || href.charAt(0) === "#") return false;
    if (/^(mailto:|tel:|javascript:)/i.test(href)) return false;

    var url;
    try {
      url = new URL(link.href, global.location.href);
    } catch (e) {
      return false;
    }
    if (url.origin !== global.location.origin) return false;

    var here = global.location.pathname + global.location.search;
    return url.pathname + url.search !== here;
  }

  function progressBar() {
    var bar = global.document.getElementById("aura-nav-progress");
    if (bar) return bar;

    var style = global.document.getElementById("aura-nav-progress-style");
    if (!style) {
      style = global.document.createElement("style");
      style.id = "aura-nav-progress-style";
      style.textContent =
        "#aura-nav-progress{position:fixed;top:0;left:0;right:0;height:3px;" +
        "background:#4f46e5;z-index:9999;display:none;" +
        "transition:opacity .2s ease}";
      (global.document.head || global.document.body).appendChild(style);
    }

    bar = global.document.createElement("div");
    bar.id = "aura-nav-progress";
    bar.setAttribute("data-aura-nav-progress", "1");
    global.document.body.appendChild(bar);
    return bar;
  }

  function showLoading() {
    if (typeof global.document === "undefined" || !global.document.body) return;

    var ui = global.document.querySelector("[data-aura-loading]");
    if (ui) {
      ui.removeAttribute("hidden");
      ui.setAttribute("data-aura-loading-active", "1");
      return;
    }

    progressBar().style.display = "block";
  }

  function hideLoading() {
    if (typeof global.document === "undefined") return;

    var ui = global.document.querySelector("[data-aura-loading][data-aura-loading-active]");
    if (ui) {
      ui.setAttribute("hidden", "hidden");
      ui.removeAttribute("data-aura-loading-active");
    }

    var bar = global.document.getElementById("aura-nav-progress");
    if (bar) bar.style.display = "none";
  }

  function fragmentOf(url) {
    var idx = String(url).indexOf("#");
    return idx === -1 ? "" : String(url).slice(idx + 1);
  }

  function fetchHtml(url, purpose) {
    var headers = { accept: "text/html" };
    headers[purpose === "prefetch" ? "x-aura-prefetch" : "x-aura-navigate"] = "1";

    var frag = fragmentOf(url);
    if (frag) headers["x-aura-fragment"] = frag;
    return global.fetch(url, { headers: headers, credentials: "same-origin" })
      .then(function (response) { return response.text(); });
  }

  function prefetch(url) {
    if (prefetchCache[url] || typeof global.fetch !== "function") return;
    fetchHtml(url, "prefetch")
      .then(function (html) { prefetchCache[url] = html; })
      .catch(function () {  });
  }

  function navigate(url, options) {
    options = options || {};
    if (typeof global.fetch !== "function") {
      global.location.href = url;
      return Promise.resolve();
    }

    showLoading();

    var request = prefetchCache[url]
      ? Promise.resolve(prefetchCache[url])
      : fetchHtml(url, "navigate");

    return request
      .then(function (html) {
        prefetchCache[url] = html;
        if (options.push !== false && global.history && global.history.pushState) {
          global.history.pushState({ aura: true }, "", url);
        }
        applyHtml(html);
        hideLoading();
        return html;
      })
      .catch(function () {
        hideLoading();
        global.location.href = url;
      });
  }

  function onClick(event) {
    if (event.defaultPrevented) return;
    if (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;

    var link = event.target && event.target.closest ? event.target.closest("a[href]") : null;
    if (!isNavigable(link)) return;

    event.preventDefault();
    navigate(link.href);
  }

  function onHover(event) {
    var link = event.target && event.target.closest ? event.target.closest("a[href]") : null;
    if (isNavigable(link)) prefetch(link.href);
  }

  function connectNavigation() {
    if (typeof global.document === "undefined") return;

    global.document.addEventListener("click", onClick);
    global.document.addEventListener("mouseover", onHover, { passive: true });
    global.addEventListener("popstate", function () {
      navigate(global.location.pathname + global.location.search, { push: false });
    });
  }

  function connectLiveReload() {
    if (typeof global.EventSource !== "function") return;

    try {
      var source = new global.EventSource("/_aura/live_reload");
      source.addEventListener("message", function (event) {
        if (event.data === "reload") global.location.reload();
      });
      source.addEventListener("error", function () {

      });
    } catch (e) {

    }
  }

  global.auraCall = auraCall;

  global.__aura_bind = auraBind;

  var api = {
    call: auraCall,
    bind: auraBind,
    navigate: navigate,
    prefetch: prefetch,
    apply: applyHtml,
    reconcile: reconcile,
    patchNode: patchNode,
    ref: ref,
    optimistic: optimistic,
    hydrate: hydrate,
    portals: applyPortals,
    append: appendHtml,

    html: appendHtml,

    suspense: suspenseSwap,
    processFragment: parseFragment
  };

  Object.defineProperty(api, "refs", {
    enumerable: true,
    get: function () {
      return collectRefs();
    }
  });

  Object.defineProperty(api, "state", {
    enumerable: true,
    get: function () {
      var copy = Object.create(null);
      for (var k in lastState) copy[k] = lastState[k];
      return copy;
    }
  });

  global.__aura = api;

  function start() {
    connectLiveReload();
    connectNavigation();

    if (typeof document !== "undefined" && document.body) {
      applyPortals(document.body);
      hydrate(document.body);
    }
  }

  if (typeof document !== "undefined") {
    if (document.readyState === "loading") {
      document.addEventListener("DOMContentLoaded", start);
    } else {
      start();
    }
  }
})(typeof globalThis !== "undefined" ? globalThis : this);
