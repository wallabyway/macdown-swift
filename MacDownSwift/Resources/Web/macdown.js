// MacDown preview runtime. Loaded once per page; the editor pushes new HTML via MacDown.update().
//
// Updates are incremental: top-level blocks whose Markdown output is unchanged keep their existing
// DOM nodes (so highlighted code, typeset math and diagrams — including Pele's intro animation —
// are not redone on every keystroke). Only new or changed blocks are post-processed.
(function () {
  'use strict';

  var cfg = window.MacDownConfig || {};
  var SOURCEPOS = 'data-sourcepos';
  var peleMounts = new Map(); // element -> Mounted

  // ---------------------------------------------------------------- diagrams

  function diagramBlocks(root) {
    var out = [];
    var codes = root.querySelectorAll ? root.querySelectorAll('pre > code.language-mermaid') : [];
    codes.forEach(function (code) { out.push(code); });
    return out;
  }

  function replaceWithContainer(code, className) {
    var pre = code.parentElement;
    var div = document.createElement('div');
    div.className = className;
    var pos = pre.getAttribute(SOURCEPOS);
    if (pos) div.setAttribute(SOURCEPOS, pos);
    div.setAttribute('data-diagram-source', code.textContent);
    if (pre.__mdKey !== undefined) div.__mdKey = pre.__mdKey; // keep identity for incremental updates
    pre.replaceWith(div);
    return div;
  }

  function peleOptions(animate) {
    var opts = { icons: window.pele.builtinIcons, zoom: false, animate: animate };
    if (typeof cfg.diagramPadding === 'number') opts.padding = cfg.diagramPadding; // space inside the diagram's card
    if (cfg.peleLook) opts.look = cfg.peleLook;
    return opts;
  }

  /// Redraw every diagram from scratch with intro + loop, regardless of the Motion setting.
  function replayPele() {
    if (!window.pele) return 0;
    var n = 0;
    Array.from(peleMounts.entries()).forEach(function (entry) {
      var el = entry[0], m = entry[1];
      if (!el.isConnected) return;
      var src = el.getAttribute('data-diagram-source') || m.source;
      try { m.destroy(); } catch (e) {}
      el.replaceChildren();
      void el.offsetWidth; // flush so the new SVG's animations start at 0
      try { peleMounts.set(el, window.pele.mount(el, src, peleOptions(true))); n++; }
      catch (err) { showError(el, err); }
    });
    return n;
  }

  function renderPele(root) {
    if (!window.pele) return;
    diagramBlocks(root).forEach(function (code) {
      var src = code.textContent;
      var div = replaceWithContainer(code, 'pele-diagram');
      var opts = peleOptions(cfg.peleAnimate);
      try {
        peleMounts.set(div, window.pele.mount(div, src, opts));
      } catch (err) {
        showError(div, err);
      }
    });
  }

  function showError(div, err) {
    div.innerHTML = '<pre class="diagram-error"></pre>';
    div.firstChild.textContent = String((err && err.message) || err);
  }

  function destroyDetachedMounts() {
    peleMounts.forEach(function (m, el) {
      if (!el.isConnected) { try { m.destroy(); } catch (e) {} peleMounts.delete(el); }
    });
  }

  // ---------------------------------------------------------------- page look + icons

  /// Give the page the look's variables (colours, fonts, radius) so prose matches the diagrams.
  function applyPageLook() {
    if (!cfg.pageLook || !window.pele || !window.pele.lookCss) return;
    var css = window.pele.lookCss(cfg.peleLook || 'elevated', ':root');
    var style = document.getElementById('md-page-look') || document.createElement('style');
    style.id = 'md-page-look';
    // Only the variable block; the rest of the sheet targets diagram internals.
    style.textContent = css.split('}')[0] + '}';
    document.head.appendChild(style);
  }

  var ICON_RE = /:((?:lucide-|fa-)?[a-z0-9]+(?:-[a-z0-9]+)*):/g;
  var OK_ICONS = /^(check|circle-check|square-check|tick|check-circle|check-square)$/;
  var BAD_ICONS = /^(x|circle-x|square-x|ban|xmark|times|close)$/;

  function iconSVG(name) {
    if (!window.pele || !window.pele.builtinIcons) return null;
    var key = name.replace(/^lucide-/, '');
    var body = window.pele.builtinIcons(key);
    if (!body) return null;
    var cls = 'md-icon' + (OK_ICONS.test(key) ? ' md-icon-ok' : BAD_ICONS.test(key) ? ' md-icon-bad' : '');
    return '<svg class="' + cls + '" viewBox="0 0 24 24" width="1.15em" height="1.15em" fill="none" stroke="currentColor"' +
      ' stroke-width="2" stroke-linecap="round" stroke-linejoin="round" role="img" aria-label="' + key + '">' + body + '</svg>';
  }

  /// Replace :name: shortcodes in prose (not code) with inline Lucide SVGs.
  function replaceIcons(elements) {
    if (!cfg.icons) return;
    elements.forEach(function (root) {
      var walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
        acceptNode: function (n) {
          if (!n.nodeValue || n.nodeValue.indexOf(':') < 0) return NodeFilter.FILTER_REJECT;
          for (var p = n.parentNode; p && p !== root.parentNode; p = p.parentNode) {
            if (p.nodeType === 1 && /^(PRE|CODE|SCRIPT|STYLE|TEXTAREA|svg)$/i.test(p.nodeName)) return NodeFilter.FILTER_REJECT;
            if (p.classList && (p.classList.contains('pele-diagram') || p.nodeName === 'MJX-CONTAINER')) return NodeFilter.FILTER_REJECT;
          }
          return NodeFilter.FILTER_ACCEPT;
        }
      });
      var targets = [];
      while (walker.nextNode()) targets.push(walker.currentNode);
      targets.forEach(function (textNode) {
        var text = textNode.nodeValue, html = '', last = 0, hit = false, m;
        ICON_RE.lastIndex = 0;
        while ((m = ICON_RE.exec(text))) {
          var svg = iconSVG(m[1]);
          if (!svg) continue;
          hit = true;
          html += escapeText(text.slice(last, m.index)) + svg;
          last = m.index + m[0].length;
        }
        if (!hit) return;
        html += escapeText(text.slice(last));
        var tpl = document.createElement('template');
        tpl.innerHTML = html;
        textNode.replaceWith(tpl.content);
      });
    });
  }

  function escapeText(s) {
    return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  }

  // ---------------------------------------------------------------- code + math

  function highlightCode(root) {
    if (!window.Prism || !root.querySelectorAll) return;
    root.querySelectorAll('pre > code[class*="language-"]').forEach(function (c) {
      if (cfg.diagrams && c.classList.contains('language-mermaid')) return;
      if (cfg.lineNumbers) c.parentElement.classList.add('line-numbers');
      window.Prism.highlightElement(c);
    });
  }

  function typesetMath(nodes) {
    if (!cfg.math || !window.MathJax || !window.MathJax.typesetPromise || nodes.length === 0) return Promise.resolve();
    return window.MathJax.typesetPromise(nodes).catch(function () {});
  }

  /// Post-process freshly inserted top-level nodes.
  function processNodes(nodes) {
    var elements = nodes.filter(function (n) { return n.nodeType === 1; });
    var wrapper = { querySelectorAll: function (sel) {
      var out = [];
      elements.forEach(function (el) {
        if (el.matches && el.matches(sel)) out.push(el);
        el.querySelectorAll(sel).forEach(function (x) { out.push(x); });
      });
      return out;
    } };
    var jobs = [];
    if (cfg.diagrams === 'pele') renderPele(wrapper);
    highlightCode(wrapper);
    replaceIcons(elements.filter(function (el) { return el.isConnected; }));
    // Diagram containers replaced <pre>s that were top-level; re-collect the live nodes for MathJax.
    jobs.push(typesetMath(elements.filter(function (el) { return el.isConnected; })));
    return Promise.all(jobs);
  }

  // ---------------------------------------------------------------- incremental update

  var POS_ATTR_RE = / data-sourcepos="[^"]*"/g;

  function keyOf(node) {
    if (node.nodeType === 1) return node.outerHTML.replace(POS_ATTR_RE, '');
    if (node.nodeType === 3) return '#text:' + node.textContent;
    return '#other';
  }

  /// Copy data-sourcepos values from a freshly parsed node onto the kept (processed) node.
  function syncPositions(kept, fresh) {
    if (kept.nodeType !== 1) return;
    var a = [kept].concat(Array.prototype.slice.call(kept.querySelectorAll('[' + SOURCEPOS + ']')));
    var b = [fresh].concat(Array.prototype.slice.call(fresh.querySelectorAll('[' + SOURCEPOS + ']')));
    // Diagram containers carry the <pre>'s position; nested lookups line up because block order is kept.
    for (var i = 0; i < Math.min(a.length, b.length); i++) {
      var v = b[i].getAttribute(SOURCEPOS);
      if (v !== null && a[i].getAttribute(SOURCEPOS) !== v) a[i].setAttribute(SOURCEPOS, v);
    }
  }

  function patchBody(html) {
    var tpl = document.createElement('template');
    tpl.innerHTML = html;
    var freshNodes = Array.prototype.slice.call(tpl.content.childNodes);

    // Index existing nodes by the key of the raw HTML they were created from.
    var pool = new Map();
    Array.prototype.forEach.call(document.body.childNodes, function (n) {
      var k = n.__mdKey;
      if (k === undefined) return;
      if (!pool.has(k)) pool.set(k, []);
      pool.get(k).push(n);
    });

    var finalNodes = [];
    var created = [];
    freshNodes.forEach(function (n) {
      var k = keyOf(n);
      var list = pool.get(k);
      if (list && list.length) {
        var kept = list.shift();
        syncPositions(kept, n);
        finalNodes.push(kept);
      } else {
        n.__mdKey = k;
        finalNodes.push(n);
        created.push(n);
      }
    });

    // Remove nodes that are no longer used, then insert/reorder with minimal moves.
    var keep = new Set(finalNodes);
    Array.prototype.slice.call(document.body.childNodes).forEach(function (n) {
      if (!keep.has(n)) n.remove();
    });
    var cursor = document.body.firstChild;
    finalNodes.forEach(function (n) {
      if (n === cursor) { cursor = cursor.nextSibling; return; }
      document.body.insertBefore(n, cursor);
    });
    destroyDetachedMounts();
    return created;
  }

  function sourcePos(el) {
    var m = /^(\d+):\d+-(\d+):\d+$/.exec(el.getAttribute(SOURCEPOS) || '');
    return m ? { start: +m[1], end: +m[2] } : null;
  }

  var MacDown = {
    lastLine: null,

    update: function (html) {
      var y = window.scrollY;
      var created = patchBody(html);
      var self = this;
      processNodes(created).then(function () {
        if (self.lastLine !== null) self.scrollToLine(self.lastLine);
      });
      if (this.lastLine !== null) this.scrollToLine(this.lastLine); else window.scrollTo(0, y);
    },

    /// `line` is a 1-based, possibly fractional source line; -1 means "scroll to bottom".
    scrollToLine: function (line) {
      this.lastLine = line;
      var maxY = Math.max(0, document.documentElement.scrollHeight - window.innerHeight);
      if (line < 0) { window.scrollTo(0, maxY); return; }
      if (line <= 1) { window.scrollTo(0, 0); return; }

      var prev = null, next = null;
      var nodes = document.body.querySelectorAll('[' + SOURCEPOS + ']');
      for (var i = 0; i < nodes.length; i++) {
        var el = nodes[i];
        var pos = sourcePos(el);
        if (!pos || el.getClientRects().length === 0) continue;
        if (pos.start <= line) { prev = { el: el, start: pos.start, end: pos.end }; }
        else { next = { el: el, start: pos.start, end: pos.end }; break; }
      }

      var sy = window.scrollY, y = 0;
      if (prev && line < prev.end + 1) {
        var r = prev.el.getBoundingClientRect();
        y = r.top + sy + ((line - prev.start) / (prev.end - prev.start + 1)) * r.height;
      } else if (prev && next) {
        var a = prev.el.getBoundingClientRect().bottom + sy;
        var b = next.el.getBoundingClientRect().top + sy;
        var gap = Math.max(1, next.start - (prev.end + 1));
        y = a + ((line - (prev.end + 1)) / gap) * (b - a);
      } else if (prev) {
        y = prev.el.getBoundingClientRect().bottom + sy;
      }
      window.scrollTo(0, Math.min(maxY, Math.max(0, y)));
    },

    disableSync: function () { this.lastLine = null; },

    replayDiagrams: function () { return replayPele(); },

    bodyHTML: function () { return document.body.innerHTML; },

    /// Extra CSS generated at runtime (the page look's variables), for export.
    pageCSS: function () { var s = document.getElementById('md-page-look'); return s ? s.textContent : ''; }
  };

  window.MacDown = MacDown;

  applyPageLook();

  function boot() {
    var nodes = Array.prototype.slice.call(document.body.childNodes);
    nodes.forEach(function (n) { n.__mdKey = keyOf(n); });
    var start = function () {
      processNodes(nodes).then(function () {
        if (MacDown.lastLine !== null) MacDown.scrollToLine(MacDown.lastLine);
      });
    };
    // Pele measures label text; wait (briefly) for the look's web fonts so the intro plays once.
    if (cfg.diagrams === 'pele' && cfg.peleLook && document.fonts && document.fonts.load) {
      var families = ['Roboto', 'Roboto Mono', 'Inter', 'Space Grotesk', 'IBM Plex Sans', 'IBM Plex Mono',
        'Fraunces', 'JetBrains Mono', 'Nunito', 'Fredoka', 'Orbitron'];
      var loads = [];
      families.forEach(function (f) {
        loads.push(document.fonts.load('400 16px "' + f + '"'), document.fonts.load('700 16px "' + f + '"'));
      });
      Promise.race([Promise.allSettled(loads), new Promise(function (r) { setTimeout(r, 1500); })]).then(start);
    } else {
      start();
    }
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot);
  else boot();
})();
