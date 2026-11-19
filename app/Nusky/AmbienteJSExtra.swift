// app/Nusky/AmbienteJSExtra.swift
import Foundation

/// Recursos padrão de navegador que o `AmbienteJS` ainda não tinha, para sites modernos abrirem e funcionarem.
/// Roda logo depois do `AmbienteJS`, antes de qualquer script da página.
///
/// O que entra aqui e por quê:
/// - `CSS.supports` respondia sempre "não", e `matchMedia` ignorava orientação e resolução. Sites que conferem
///   recursos antes de abrir (como o claude.ai) concluíam que o navegador estava desatualizado.
/// - `ReadableStream`, `TransformStream`, `MessageChannel`, `customElements`, `TreeWalker`, `crypto.subtle.digest`
///   e outros: apps feitos com Next.js e React usam isso para hidratar a página. Sem eles, a hidratação quebra,
///   a página fica só desenhada e os botões não respondem (era o caso do arena.ai).
/// - `fetch().body` passa a ser um stream, que é como os chats leem a resposta.
extension AmbienteJS {
    static let extra = #"""
// Recursos padrão de navegador que o AmbienteJS ainda não tinha. Roda logo depois dele e antes de qualquer
// script da página. Só define o que falta (ou o que estava errado: CSS.supports e matchMedia).
(function (G) {
  'use strict';
  var nada = function () {};
  var pagina = G.__pagina || {};
  var LARG = pagina.largura || 375, ALT = 667;   // a mesma altura que o motor usa nas consultas de mídia
  function def(o, k, v) { if (o[k] === undefined) { try { Object.defineProperty(o, k, { value: v, writable: true, configurable: true, enumerable: false }); } catch (e) { try { o[k] = v; } catch (e2) {} } } }
  function forca(o, k, v) { try { Object.defineProperty(o, k, { value: v, writable: true, configurable: true, enumerable: false }); } catch (e) { try { o[k] = v; } catch (e2) {} } }
  function erroDom(msg, nome) { return typeof G.DOMException === 'function' ? new G.DOMException(msg, nome) : new Error(msg); }
  function depois(f) { G.setTimeout(f, 0); }

  // ---------- janela ----------
  def(G, 'isSecureContext', true);
  def(G, 'crossOriginIsolated', false);
  def(G, 'origin', G.location ? G.location.origin : '');
  def(G, 'name', ''); def(G, 'status', ''); def(G, 'opener', null); def(G, 'length', 0);
  def(G, 'screenX', 0); def(G, 'screenY', 0);

  // ---------- CSS.supports ----------
  // Responde o que o Safari 15.6 responderia. Antes devolvia sempre false, e qualquer site que confere
  // recursos antes de abrir concluía que o navegador estava desatualizado.
  var CSS_AUSENTE = /container-type|container-name|container\s*:|text-wrap|field-sizing|anchor-name|position-anchor|view-transition|animation-timeline|scroll-timeline|timeline-scope|interpolate-size|color-mix\(|light-dark\(|subgrid|masonry|overscroll-behavior|text-box|:popover-open|:modal|@starting-style|@container|@scope|anchor\(/i;
  function topo(t) {
    var prof = 0, partes = [], ini = 0, op = null;
    for (var i = 0; i < t.length; i++) {
      var ch = t.charAt(i);
      if (ch === '(') prof++; else if (ch === ')') prof--;
      else if (prof === 0 && /\s/.test(ch)) {
        var m = /^\s+(and|or)\s+/i.exec(t.slice(i));
        if (m) { op = op || m[1].toLowerCase(); partes.push(t.slice(ini, i)); i += m[0].length - 1; ini = i + 1; }
      }
    }
    partes.push(t.slice(ini));
    return { op: op, partes: partes };
  }
  function declaracao(d) { return d.indexOf(':') > 0 && !CSS_AUSENTE.test(d); }
  function suporta(c) {
    c = c.trim();
    var n = /^not\s+([\s\S]+)$/i.exec(c);
    if (n) return !suporta(n[1]);
    var t = topo(c);
    if (t.partes.length > 1) {
      var r = t.op !== 'or';
      for (var i = 0; i < t.partes.length; i++) { var v = suporta(t.partes[i]); r = t.op === 'or' ? (r || v) : (r && v); }
      return r;
    }
    var s = /^selector\(([\s\S]*)\)$/i.exec(c);
    if (s) return !CSS_AUSENTE.test(s[1]);
    var g = /^\(([\s\S]*)\)$/.exec(c);
    if (g) {
      var dentro = g[1].trim();
      if (/^not\s/i.test(dentro) || dentro.charAt(0) === '(' || topo(dentro).partes.length > 1) return suporta(dentro);
      return declaracao(dentro);
    }
    return declaracao(c);
  }
  var css = G.CSS || (G.CSS = {});
  css.supports = function (a, b) { return arguments.length >= 2 ? declaracao(String(a) + ':' + String(b)) : suporta(String(a)); };
  if (!css.escape) css.escape = function (s) { return String(s).replace(/[^\w-]/g, '\\$&'); };

  // ---------- matchMedia ----------
  // Mesmas respostas do motor (Rust): em pé, toque, 2x, sem redução de movimento, tema do aparelho.
  function comprimento(v) {
    var m = /^(-?[\d.]+)(px|em|rem|vw|vh)?$/.exec(String(v).trim());
    if (!m) return null;
    var n = parseFloat(m[1]);
    return m[2] === 'em' || m[2] === 'rem' ? n * 16 : m[2] === 'vw' ? n * LARG / 100 : m[2] === 'vh' ? n * ALT / 100 : n;
  }
  function resolucao(v) {
    var m = /^([\d.]+)(dppx|dpi|x)$/.exec(String(v).trim());
    return m ? (m[2] === 'dpi' ? parseFloat(m[1]) / 96 : parseFloat(m[1])) : null;
  }
  function razao(v) {
    var m = /^([\d.]+)\s*\/\s*([\d.]+)$/.exec(String(v).trim());
    return m ? parseFloat(m[1]) / parseFloat(m[2]) : (isNaN(parseFloat(v)) ? null : parseFloat(v));
  }
  function faixa(d) {
    var ops = [], opn = [], atual = '';
    for (var i = 0; i < d.length; i++) {
      var c = d.charAt(i);
      if (c === '<' || c === '>' || c === '=') { var op = c; if (c !== '=' && d.charAt(i + 1) === '=') { op += '='; i++; } opn.push(atual.trim()); ops.push(op); atual = ''; }
      else atual += c;
    }
    opn.push(atual.trim());
    if (!ops.length || ops.length > 2 || opn.length !== ops.length + 1) return false;
    function val(s) { return s === 'width' ? LARG : s === 'height' ? ALT : comprimento(s); }
    for (var k = 0; k < ops.length; k++) {
      var a = val(opn[k]), b = val(opn[k + 1]);
      if (a === null || b === null) return false;
      var ok = ops[k] === '<' ? a < b : ops[k] === '<=' ? a <= b : ops[k] === '>' ? a > b : ops[k] === '>=' ? a >= b : Math.abs(a - b) < 0.01;
      if (!ok) return false;
    }
    return true;
  }
  function condicao(d) {
    d = d.trim().toLowerCase();
    var i = d.indexOf(':');
    if (i > 0 && !/[<>=]/.test(d.slice(0, i))) {
      var n = d.slice(0, i).trim(), v = d.slice(i + 1).trim(), x;
      switch (n) {
        case 'min-width': x = comprimento(v); return x !== null && LARG >= x;
        case 'max-width': x = comprimento(v); return x !== null && LARG <= x;
        case 'width': x = comprimento(v); return x !== null && LARG === x;
        case 'min-height': x = comprimento(v); return x !== null && ALT >= x;
        case 'max-height': x = comprimento(v); return x !== null && ALT <= x;
        case 'height': x = comprimento(v); return x !== null && ALT === x;
        case 'orientation': return v === 'portrait';
        case 'hover': case 'any-hover': return v === 'none';
        case 'pointer': case 'any-pointer': return v === 'coarse';
        case 'prefers-color-scheme': return (v === 'dark') === !!pagina.escuro;
        case 'prefers-reduced-motion': case 'prefers-contrast': case 'prefers-reduced-transparency': return v === 'no-preference';
        case 'forced-colors': case 'inverted-colors': return v === 'none';
        case 'display-mode': return v === 'browser';
        case 'update': return v === 'fast';
        case 'scripting': return v === 'enabled';
        case 'min-resolution': x = resolucao(v); return x !== null && 2 >= x;
        case 'max-resolution': x = resolucao(v); return x !== null && 2 <= x;
        case '-webkit-min-device-pixel-ratio': return 2 >= parseFloat(v);
        case '-webkit-max-device-pixel-ratio': return 2 <= parseFloat(v);
        case 'min-aspect-ratio': x = razao(v); return x !== null && LARG / ALT >= x;
        case 'max-aspect-ratio': x = razao(v); return x !== null && LARG / ALT <= x;
        case 'aspect-ratio': x = razao(v); return x !== null && Math.abs(LARG / ALT - x) < 0.01;
        case 'min-color': case 'color': return true;
        default: return false;
      }
    }
    if (d === 'color' || d === 'pointer' || d === 'any-pointer') return true;
    if (d === 'hover' || d === 'any-hover') return false;
    return faixa(d);
  }
  function consulta(q) {
    var neg = false;
    q = q.trim().toLowerCase();
    if (/^not\s/.test(q)) { neg = true; q = q.slice(4).trim(); }
    q = q.replace(/^only\s+/, '');
    if (q === '') return !neg;
    var ok = true, partes = q.split(/\s+and\s+/);
    for (var i = 0; i < partes.length; i++) {
      var p = partes[i].trim(), m = /^\(([\s\S]*)\)$/.exec(p);
      if (m) ok = ok && condicao(m[1]);
      else if (p !== 'screen' && p !== 'all') ok = false;
    }
    return neg ? !ok : ok;
  }
  function avaliaMedia(q) {
    var r = false, prof = 0, ini = 0;
    q = String(q);
    for (var i = 0; i <= q.length; i++) {
      var c = q.charAt(i);
      if (c === '(') prof++; else if (c === ')') prof--;
      else if ((c === ',' && prof === 0) || i === q.length) { if (consulta(q.slice(ini, i))) r = true; ini = i + 1; }
    }
    return r;
  }
  function MediaQueryList(q) {
    this.media = q; this.matches = avaliaMedia(q); this.onchange = null;
  }
  MediaQueryList.prototype.addListener = nada; MediaQueryList.prototype.removeListener = nada;
  MediaQueryList.prototype.addEventListener = nada; MediaQueryList.prototype.removeEventListener = nada;
  MediaQueryList.prototype.dispatchEvent = function () { return true; };
  forca(G, 'MediaQueryList', MediaQueryList);
  forca(G, 'matchMedia', function (q) { return new MediaQueryList(String(q)); });

  // ---------- classes que só existem para "instanceof" ----------
  function forma(nome, teste) {
    var F = function () { throw new TypeError('Illegal constructor'); };
    try { Object.defineProperty(F, 'name', { value: nome }); } catch (e) {}
    Object.defineProperty(F, Symbol.hasInstance, { value: teste });
    def(G, nome, F);
  }
  forma('NodeList', function (v) { return Array.isArray(v); });
  forma('HTMLCollection', function (v) { return Array.isArray(v); });
  forma('DOMTokenList', function (v) { return !!v && typeof v.contains === 'function' && typeof v.toggle === 'function'; });
  forma('CSSStyleDeclaration', function (v) { return !!v && typeof v.getPropertyValue === 'function'; });
  forma('Selection', function (v) { return !!v && typeof v.removeAllRanges === 'function'; });
  if (typeof G.Range !== 'function') {
    var Range = function Range() { return G.document.createRange(); };
    Object.defineProperty(Range, Symbol.hasInstance, { value: function (v) { return !!v && typeof v.setStart === 'function' && typeof v.selectNodeContents === 'function'; } });
    def(G, 'Range', Range);
  }

  // ---------- eventos ----------
  function sub(nome, base, extra) {
    var C = function (tipo, init) {
      base.call(this, tipo, init); init = init || {};
      for (var k in extra) if (this[k] === undefined || init[k] !== undefined) this[k] = init[k] === undefined ? extra[k] : init[k];
    };
    C.prototype = Object.create(base.prototype); C.prototype.constructor = C;
    try { Object.defineProperty(C, 'name', { value: nome }); } catch (e) {}
    return C;
  }
  def(G, 'UIEvent', sub('UIEvent', G.Event, { detail: 0, view: null }));
  def(G, 'WheelEvent', sub('WheelEvent', G.MouseEvent || G.Event, { deltaX: 0, deltaY: 0, deltaZ: 0, deltaMode: 0 }));
  def(G, 'PromiseRejectionEvent', sub('PromiseRejectionEvent', G.Event, { promise: undefined, reason: undefined }));
  function msgEvento(d) {
    var e = typeof G.MessageEvent === 'function' ? new G.MessageEvent('message', { data: d }) : new G.Event('message');
    if (e.data === undefined) e.data = d;
    return e;
  }

  // ---------- geometria ----------
  function DOMRectReadOnly(x, y, w, h) { this.x = +x || 0; this.y = +y || 0; this.width = +w || 0; this.height = +h || 0; }
  Object.defineProperties(DOMRectReadOnly.prototype, {
    top: { get: function () { return Math.min(this.y, this.y + this.height); } },
    left: { get: function () { return Math.min(this.x, this.x + this.width); } },
    right: { get: function () { return Math.max(this.x, this.x + this.width); } },
    bottom: { get: function () { return Math.max(this.y, this.y + this.height); } }
  });
  DOMRectReadOnly.prototype.toJSON = function () { return { x: this.x, y: this.y, width: this.width, height: this.height, top: this.top, right: this.right, bottom: this.bottom, left: this.left }; };
  DOMRectReadOnly.fromRect = function (o) { o = o || {}; return new DOMRectReadOnly(o.x, o.y, o.width, o.height); };
  function DOMRect(x, y, w, h) { DOMRectReadOnly.call(this, x, y, w, h); }
  DOMRect.prototype = Object.create(DOMRectReadOnly.prototype); DOMRect.prototype.constructor = DOMRect;
  DOMRect.fromRect = function (o) { o = o || {}; return new DOMRect(o.x, o.y, o.width, o.height); };
  def(G, 'DOMRectReadOnly', DOMRectReadOnly); def(G, 'DOMRect', DOMRect);

  // ---------- percorrer a árvore ----------
  var NF = { FILTER_ACCEPT: 1, FILTER_REJECT: 2, FILTER_SKIP: 3, SHOW_ALL: 0xFFFFFFFF, SHOW_ELEMENT: 1, SHOW_ATTRIBUTE: 2, SHOW_TEXT: 4, SHOW_CDATA_SECTION: 8,
    SHOW_PROCESSING_INSTRUCTION: 64, SHOW_COMMENT: 128, SHOW_DOCUMENT: 256, SHOW_DOCUMENT_TYPE: 512, SHOW_DOCUMENT_FRAGMENT: 1024 };
  def(G, 'NodeFilter', NF);
  function aceita(tw, n) {
    if (!(tw.whatToShow & (1 << (n.nodeType - 1)))) return 3;
    var f = tw.filter;
    if (!f) return 1;
    return typeof f === 'function' ? f(n) : f.acceptNode(n);
  }
  function seguinte(raiz, n, entrar) {
    if (entrar && n.childNodes && n.childNodes.length) return n.childNodes[0];
    while (n && n !== raiz) { var ir = n.nextSibling; if (ir) return ir; n = n.parentNode; }
    return null;
  }
  function todos(raiz) { var r = [], n = raiz; while ((n = seguinte(raiz, n, true))) r.push(n); return r; }
  function TreeWalker(raiz, mostrar, filtro) { this.root = raiz; this.whatToShow = mostrar === undefined ? 0xFFFFFFFF : mostrar >>> 0; this.filter = filtro || null; this.currentNode = raiz; }
  TreeWalker.prototype.nextNode = function () {
    var n = this.currentNode, entrar = true;
    for (;;) {
      n = seguinte(this.root, n, entrar);
      if (!n) return null;
      var r = aceita(this, n);
      if (r === 1) { this.currentNode = n; return n; }
      entrar = r !== 2;
    }
  };
  TreeWalker.prototype.previousNode = function () {
    var lista = todos(this.root); lista.unshift(this.root);
    for (var i = lista.indexOf(this.currentNode) - 1; i >= 0; i--) if (lista[i] !== this.root && aceita(this, lista[i]) === 1) { this.currentNode = lista[i]; return lista[i]; }
    return null;
  };
  TreeWalker.prototype.parentNode = function () {
    for (var p = this.currentNode.parentNode; p && p !== this.root.parentNode; p = p.parentNode) { if (p !== this.root && aceita(this, p) === 1) { this.currentNode = p; return p; } if (p === this.root) break; }
    return null;
  };
  TreeWalker.prototype.firstChild = function () { var c = this.currentNode.childNodes || []; for (var i = 0; i < c.length; i++) if (aceita(this, c[i]) === 1) { this.currentNode = c[i]; return c[i]; } return null; };
  TreeWalker.prototype.lastChild = function () { var c = this.currentNode.childNodes || []; for (var i = c.length - 1; i >= 0; i--) if (aceita(this, c[i]) === 1) { this.currentNode = c[i]; return c[i]; } return null; };
  TreeWalker.prototype.nextSibling = function () { for (var n = this.currentNode.nextSibling; n; n = n.nextSibling) if (aceita(this, n) === 1) { this.currentNode = n; return n; } return null; };
  TreeWalker.prototype.previousSibling = function () { for (var n = this.currentNode.previousSibling; n; n = n.previousSibling) if (aceita(this, n) === 1) { this.currentNode = n; return n; } return null; };
  def(G, 'TreeWalker', TreeWalker);
  if (G.Document && G.Document.prototype) {
    G.Document.prototype.createTreeWalker = function (r, m, f) { return new TreeWalker(r, m, f); };
    G.Document.prototype.createNodeIterator = function (r, m, f) {
      var tw = new TreeWalker(r, m, f);
      return { root: r, whatToShow: tw.whatToShow, filter: tw.filter, referenceNode: r, nextNode: function () { var n = tw.nextNode(); if (n) this.referenceNode = n; return n; }, previousNode: function () { var n = tw.previousNode(); if (n) this.referenceNode = n; return n; }, detach: nada };
    };
  }

  // ---------- mensagens ----------
  function MessagePort() { this.onmessage = null; this.onmessageerror = null; this.__outra = null; this.__ouvintes = []; this.__fechada = false; }
  MessagePort.prototype.postMessage = function (d) {
    var alvo = this.__outra;
    if (!alvo || this.__fechada) return;
    depois(function () {
      if (alvo.__fechada) return;
      var e = msgEvento(d);
      if (typeof alvo.onmessage === 'function') alvo.onmessage(e);
      alvo.__ouvintes.slice().forEach(function (f) { f.call(alvo, e); });
    });
  };
  MessagePort.prototype.addEventListener = function (t, f) { if (t === 'message' && typeof f === 'function' && this.__ouvintes.indexOf(f) < 0) this.__ouvintes.push(f); };
  MessagePort.prototype.removeEventListener = function (t, f) { var i = this.__ouvintes.indexOf(f); if (i >= 0) this.__ouvintes.splice(i, 1); };
  MessagePort.prototype.start = nada;
  MessagePort.prototype.close = function () { this.__fechada = true; };
  function MessageChannel() { this.port1 = new MessagePort(); this.port2 = new MessagePort(); this.port1.__outra = this.port2; this.port2.__outra = this.port1; }
  def(G, 'MessagePort', MessagePort); def(G, 'MessageChannel', MessageChannel);

  var canais = Object.create(null);
  function BroadcastChannel(nome) { this.name = String(nome); this.onmessage = null; this.__ouvintes = []; this.__fechado = false; (canais[this.name] = canais[this.name] || []).push(this); }
  BroadcastChannel.prototype.postMessage = function (d) {
    var self = this;
    (canais[this.name] || []).forEach(function (c) {
      if (c === self || c.__fechado) return;
      depois(function () { var e = msgEvento(d); if (typeof c.onmessage === 'function') c.onmessage(e); c.__ouvintes.slice().forEach(function (f) { f.call(c, e); }); });
    });
  };
  BroadcastChannel.prototype.addEventListener = MessagePort.prototype.addEventListener;
  BroadcastChannel.prototype.removeEventListener = MessagePort.prototype.removeEventListener;
  BroadcastChannel.prototype.close = function () { this.__fechado = true; var l = canais[this.name] || [], i = l.indexOf(this); if (i >= 0) l.splice(i, 1); };
  def(G, 'BroadcastChannel', BroadcastChannel);

  // ---------- elementos personalizados ----------
  var registro = Object.create(null), espera = Object.create(null);
  def(G, 'customElements', {
    define: function (n, c) {
      n = String(n).toLowerCase();
      if (registro[n]) throw erroDom('The name "' + n + '" has already been used with this registry', 'NotSupportedError');
      registro[n] = c;
      (espera[n] || []).forEach(function (f) { f(c); }); espera[n] = null;
    },
    get: function (n) { return registro[String(n).toLowerCase()]; },
    whenDefined: function (n) { n = String(n).toLowerCase(); return registro[n] ? Promise.resolve(registro[n]) : new Promise(function (ok) { (espera[n] = espera[n] || []).push(ok); }); },
    upgrade: nada
  });

  // ---------- streams ----------
  function ReadableStream(src, estr) {
    var self = this;
    src = src || {};
    this.__fila = []; this.__esperas = []; this.__estado = 'readable'; this.__erro = undefined; this.__trava = null;
    this.__puxando = false; this.__outraVez = false; this.__pronto = false; this.__src = src;
    this.__hwm = estr && estr.highWaterMark !== undefined ? estr.highWaterMark : 1;
    this.__ctl = {
      enqueue: function (c) {
        if (self.__estado !== 'readable') throw new TypeError('Cannot enqueue a chunk into a closed or errored stream');
        if (self.__esperas.length) self.__esperas.shift().ok({ value: c, done: false }); else self.__fila.push(c);
        self.__puxar();
      },
      close: function () { if (self.__estado !== 'readable') return; self.__estado = 'closed'; if (!self.__fila.length) self.__encerrar(); },
      error: function (e) { self.__falhar(e); }
    };
    Object.defineProperty(this.__ctl, 'desiredSize', { get: function () { return self.__estado === 'readable' ? self.__hwm - self.__fila.length : (self.__estado === 'closed' ? 0 : null); } });
    var ini;
    try { ini = src.start ? src.start(this.__ctl) : undefined; } catch (e) { this.__falhar(e); ini = undefined; }
    Promise.resolve(ini).then(function () { self.__pronto = true; self.__puxar(); }, function (e) { self.__falhar(e); });
  }
  ReadableStream.prototype.__encerrar = function () {
    this.__esperas.splice(0).forEach(function (w) { w.ok({ value: undefined, done: true }); });
    if (this.__fechadoOk) this.__fechadoOk();
  };
  ReadableStream.prototype.__falhar = function (e) {
    if (this.__estado === 'errored') return;
    this.__estado = 'errored'; this.__erro = e === undefined ? new TypeError('stream error') : e; this.__fila = [];
    this.__esperas.splice(0).forEach(function (w) { w.no(e); });
    if (this.__fechadoNo) this.__fechadoNo(this.__erro);
  };
  ReadableStream.prototype.__puxar = function () {
    var self = this;
    if (!self.__pronto || self.__estado !== 'readable' || !self.__src.pull) return;
    if (!(self.__esperas.length || self.__fila.length < self.__hwm)) return;
    if (self.__puxando) { self.__outraVez = true; return; }
    self.__puxando = true;
    var r;
    try { r = self.__src.pull(self.__ctl); } catch (e) { self.__puxando = false; self.__falhar(e); return; }
    Promise.resolve(r).then(function () {
      self.__puxando = false;
      if (self.__outraVez) { self.__outraVez = false; self.__puxar(); }
    }, function (e) { self.__puxando = false; self.__falhar(e); });
  };
  ReadableStream.prototype.__ler = function () {
    var self = this;
    if (self.__fila.length) {
      var v = self.__fila.shift();
      if (self.__estado === 'closed' && !self.__fila.length) self.__encerrar(); else self.__puxar();
      return Promise.resolve({ value: v, done: false });
    }
    if (self.__estado === 'closed') return Promise.resolve({ value: undefined, done: true });
    if (self.__estado === 'errored') return Promise.reject(self.__erro);
    return new Promise(function (ok, no) { self.__esperas.push({ ok: ok, no: no }); self.__puxar(); });
  };
  Object.defineProperty(ReadableStream.prototype, 'locked', { get: function () { return !!this.__trava; } });
  ReadableStream.prototype.getReader = function () {
    var s = this;
    if (s.__trava) throw new TypeError('ReadableStream is locked');
    var fechado = new Promise(function (ok, no) { s.__fechadoOk = ok; s.__fechadoNo = no; });
    fechado.then(nada, nada);
    if (s.__estado === 'closed' && !s.__fila.length) s.__fechadoOk();
    if (s.__estado === 'errored') s.__fechadoNo(s.__erro);
    var leitor = {
      closed: fechado,
      read: function () { return s.__ler(); },
      cancel: function (m) { return s.cancel(m); },
      releaseLock: function () { if (s.__trava === leitor) s.__trava = null; }
    };
    s.__trava = leitor;
    return leitor;
  };
  ReadableStream.prototype.cancel = function (m) {
    var s = this;
    if (s.__estado === 'errored') return Promise.reject(s.__erro);
    s.__estado = 'closed'; s.__fila = []; s.__encerrar();
    return Promise.resolve(s.__src.cancel ? s.__src.cancel(m) : undefined).then(function () {});
  };
  ReadableStream.prototype.tee = function () {
    var r = this.getReader(), c1, c2;
    var a = new ReadableStream({ start: function (c) { c1 = c; } }), b = new ReadableStream({ start: function (c) { c2 = c; } });
    (function bomba() {
      r.read().then(function (x) {
        if (x.done) { c1.close(); c2.close(); return; }
        c1.enqueue(x.value); c2.enqueue(x.value); bomba();
      }, function (e) { c1.error(e); c2.error(e); });
    })();
    return [a, b];
  };
  ReadableStream.prototype.pipeTo = function (dest) {
    var w = dest.getWriter(), r = this.getReader();
    return new Promise(function (ok, no) {
      (function passo() {
        r.read().then(function (x) {
          if (x.done) { w.close().then(function () { w.releaseLock(); ok(); }, no); return; }
          w.write(x.value).then(passo, no);
        }, no);
      })();
    });
  };
  ReadableStream.prototype.pipeThrough = function (t) { this.pipeTo(t.writable).then(nada, nada); return t.readable; };
  ReadableStream.prototype[Symbol.asyncIterator] = ReadableStream.prototype.values = function () {
    var r = this.getReader();
    return {
      next: function () { return r.read(); },
      'return': function () { r.releaseLock(); return Promise.resolve({ value: undefined, done: true }); },
      [Symbol.asyncIterator]: function () { return this; }
    };
  };
  ReadableStream.from = function (it) {
    var iter = it[Symbol.asyncIterator] ? it[Symbol.asyncIterator]() : it[Symbol.iterator]();
    return new ReadableStream({ pull: function (c) { return Promise.resolve(iter.next()).then(function (x) { if (x.done) c.close(); else c.enqueue(x.value); }); } });
  };

  function WritableStream(sink) {
    var self = this;
    this.__sink = sink || {}; this.__trava = false; this.__estado = 'writable';
    this.__ctl = { error: function (e) { self.__estado = 'errored'; self.__erroValor = e; }, signal: { aborted: false } };
    this.__cadeia = Promise.resolve().then(function () { return self.__sink.start ? self.__sink.start(self.__ctl) : undefined; });
  }
  Object.defineProperty(WritableStream.prototype, 'locked', { get: function () { return this.__trava; } });
  WritableStream.prototype.getWriter = function () {
    var s = this;
    if (s.__trava) throw new TypeError('WritableStream is locked');
    s.__trava = true;
    var fechado = new Promise(function (ok, no) { s.__ok = ok; s.__no = no; });
    fechado.then(nada, nada);
    var w = {
      ready: Promise.resolve(), desiredSize: 1, closed: fechado,
      write: function (c) { s.__cadeia = s.__cadeia.then(function () { return s.__sink.write ? s.__sink.write(c, s.__ctl) : undefined; }); return s.__cadeia; },
      close: function () { s.__cadeia = s.__cadeia.then(function () { return s.__sink.close ? s.__sink.close() : undefined; }).then(function () { s.__estado = 'closed'; s.__ok(); }); return s.__cadeia; },
      abort: function (m) { s.__estado = 'errored'; s.__no(m); return Promise.resolve(s.__sink.abort ? s.__sink.abort(m) : undefined); },
      releaseLock: function () { s.__trava = false; }
    };
    return w;
  };
  WritableStream.prototype.close = function () { var w = this.getWriter(); return w.close(); };
  WritableStream.prototype.abort = function (m) { this.__estado = 'errored'; return Promise.resolve(this.__sink.abort ? this.__sink.abort(m) : undefined); };

  function TransformStream(tr) {
    tr = tr || {};
    var ctlR;
    this.readable = new ReadableStream({ start: function (c) { ctlR = c; } });
    var ctl = { enqueue: function (c) { ctlR.enqueue(c); }, error: function (e) { ctlR.error(e); }, terminate: function () { ctlR.close(); } };
    Object.defineProperty(ctl, 'desiredSize', { get: function () { return 1; } });
    this.writable = new WritableStream({
      start: function () { return tr.start ? tr.start(ctl) : undefined; },
      write: function (c) { return tr.transform ? tr.transform(c, ctl) : ctl.enqueue(c); },
      close: function () { return Promise.resolve(tr.flush ? tr.flush(ctl) : undefined).then(function () { ctlR.close(); }); },
      abort: function (e) { ctlR.error(e); }
    });
  }
  def(G, 'ReadableStream', ReadableStream); def(G, 'WritableStream', WritableStream); def(G, 'TransformStream', TransformStream);

  function TextDecoderStream(enc) {
    var d = new G.TextDecoder(enc || 'utf-8');
    var t = new TransformStream({
      transform: function (chunk, c) { var s = d.decode(chunk, { stream: true }); if (s) c.enqueue(s); },
      flush: function (c) { var s = d.decode(); if (s) c.enqueue(s); }
    });
    this.encoding = (enc || 'utf-8').toLowerCase(); this.readable = t.readable; this.writable = t.writable;
  }
  function TextEncoderStream() {
    var e = new G.TextEncoder();
    var t = new TransformStream({ transform: function (chunk, c) { c.enqueue(e.encode(String(chunk))); } });
    this.encoding = 'utf-8'; this.readable = t.readable; this.writable = t.writable;
  }
  def(G, 'TextDecoderStream', TextDecoderStream); def(G, 'TextEncoderStream', TextEncoderStream);

  // fetch: response.body passa a ser um stream (a resposta chega inteira, num pedaço só)
  function corpoComoStream(r) {
    var texto = r.__texto;
    try {
      Object.defineProperty(r, 'body', { configurable: true, enumerable: true, get: function () {
        if (!this.__stream) {
          this.__stream = new ReadableStream({ start: function (c) { if (texto) c.enqueue(new G.TextEncoder().encode(texto)); c.close(); } });
        }
        return this.__stream;
      } });
    } catch (e) {}
  }
  if (typeof G.fetch === 'function') {
    var fetch0 = G.fetch;
    forca(G, 'fetch', function () {
      return fetch0.apply(this, arguments).then(function (r) { if (r && r.__texto !== undefined) corpoComoStream(r); return r; });
    });
  }
  if (G.Response && G.Response.prototype && G.Response.prototype.clone) {
    var clone0 = G.Response.prototype.clone;
    G.Response.prototype.clone = function () { var r = clone0.call(this); if (this.__texto !== undefined) corpoComoStream(r); return r; };
  }

  // ---------- arquivos ----------
  function FileReader() {
    this.readyState = 0; this.result = null; this.error = null;
    this.onload = this.onerror = this.onloadend = this.onloadstart = this.onprogress = this.onabort = null; this.__l = {};
  }
  FileReader.EMPTY = 0; FileReader.LOADING = 1; FileReader.DONE = 2;
  FileReader.prototype.addEventListener = function (t, f) { (this.__l[t] = this.__l[t] || []).push(f); };
  FileReader.prototype.removeEventListener = function (t, f) { var l = this.__l[t] || [], i = l.indexOf(f); if (i >= 0) l.splice(i, 1); };
  FileReader.prototype.abort = function () { this.readyState = 2; };
  function emite(fr, tipo) {
    var e = new G.Event(tipo); e.target = fr;
    if (typeof fr['on' + tipo] === 'function') fr['on' + tipo](e);
    (fr.__l[tipo] || []).slice().forEach(function (f) { f.call(fr, e); });
  }
  function leitura(modo) {
    return function (blob) {
      var fr = this; fr.readyState = 1;
      depois(function () {
        emite(fr, 'loadstart');
        Promise.resolve(blob.text()).then(function (t) {
          if (modo === 'texto') fr.result = t;
          else if (modo === 'url') fr.result = 'data:' + (blob.type || 'application/octet-stream') + ';base64,' + G.btoa(unescape(encodeURIComponent(t)));
          else if (modo === 'binario') fr.result = unescape(encodeURIComponent(t));
          else fr.result = new G.TextEncoder().encode(t).buffer;
          fr.readyState = 2; emite(fr, 'load'); emite(fr, 'loadend');
        }, function (e) { fr.error = e; fr.readyState = 2; emite(fr, 'error'); emite(fr, 'loadend'); });
      });
    };
  }
  FileReader.prototype.readAsText = leitura('texto'); FileReader.prototype.readAsDataURL = leitura('url');
  FileReader.prototype.readAsBinaryString = leitura('binario'); FileReader.prototype.readAsArrayBuffer = leitura('buffer');
  def(G, 'FileReader', FileReader);

  // ---------- armazenamento, notificações e outros que só dizem "não" ----------
  function pedidoFalho(nome) {
    var req = { result: undefined, error: null, readyState: 'pending', onsuccess: null, onerror: null, onblocked: null, onupgradeneeded: null, source: null, transaction: null };
    depois(function () {
      req.readyState = 'done'; req.error = erroDom('Banco de dados indisponível neste navegador', nome || 'UnknownError');
      var e = new G.Event('error'); e.target = req;
      if (typeof req.onerror === 'function') req.onerror(e);
    });
    return req;
  }
  def(G, 'indexedDB', {
    open: function () { return pedidoFalho('UnknownError'); },
    deleteDatabase: function () { return pedidoFalho('UnknownError'); },
    databases: function () { return Promise.resolve([]); },
    cmp: function (a, b) { return a < b ? -1 : a > b ? 1 : 0; }
  });
  function Notification() { throw new TypeError("Failed to construct 'Notification': Illegal constructor"); }
  Notification.permission = 'denied'; Notification.maxActions = 0;
  Notification.requestPermission = function (cb) { if (typeof cb === 'function') cb('denied'); return Promise.resolve('denied'); };
  def(G, 'Notification', Notification);
  def(G, 'XMLSerializer', function XMLSerializer() {});
  G.XMLSerializer.prototype.serializeToString = function (n) { return n.nodeType === 9 && n.documentElement ? n.documentElement.outerHTML : (n.outerHTML !== undefined ? n.outerHTML : String(n.textContent)); };
  def(G, 'Audio', function Audio(src) {
    var a = G.document.createElement('audio');
    if (src) a.setAttribute('src', src);
    a.play = function () { return Promise.resolve(); }; a.pause = nada; a.load = nada;
    return a;
  });
  var nav = G.navigator;
  if (nav) {
    def(nav, 'geolocation', {
      getCurrentPosition: function (ok, no) { depois(function () { if (typeof no === 'function') no({ code: 1, message: 'User denied Geolocation', PERMISSION_DENIED: 1, POSITION_UNAVAILABLE: 2, TIMEOUT: 3 }); }); },
      watchPosition: function (ok, no) { this.getCurrentPosition(ok, no); return 0; },
      clearWatch: nada
    });
    def(nav, 'storage', { estimate: function () { return Promise.resolve({ quota: 1073741824, usage: 0 }); }, persist: function () { return Promise.resolve(false); }, persisted: function () { return Promise.resolve(false); } });
  }
  if (G.Element && G.Element.prototype) {
    def(G.Element.prototype, 'hasPointerCapture', function () { return false; });
    def(G.Element.prototype, 'setPointerCapture', nada);
    def(G.Element.prototype, 'releasePointerCapture', nada);
    def(G.Element.prototype, 'getAnimations', function () { return []; });
  }

  // ---------- structuredClone ----------
  forca(G, 'structuredClone', function (v) {
    var vistos = new Map();
    function copia(x) {
      if (x === null || typeof x !== 'object') {
        if (typeof x === 'function' || typeof x === 'symbol') throw erroDom(String(x) + ' could not be cloned.', 'DataCloneError');
        return x;
      }
      if (vistos.has(x)) return vistos.get(x);
      var r;
      if (x instanceof Date) return new Date(x.getTime());
      if (x instanceof RegExp) return new RegExp(x.source, x.flags);
      if (x instanceof ArrayBuffer) return x.slice(0);
      if (ArrayBuffer.isView(x)) return new x.constructor(x.buffer.slice(0), x.byteOffset, x.length);
      if (x instanceof Map) { r = new Map(); vistos.set(x, r); x.forEach(function (val, k) { r.set(copia(k), copia(val)); }); return r; }
      if (x instanceof Set) { r = new Set(); vistos.set(x, r); x.forEach(function (val) { r.add(copia(val)); }); return r; }
      if (x instanceof Error) { r = new x.constructor(x.message); vistos.set(x, r); return r; }
      r = Array.isArray(x) ? [] : {};
      vistos.set(x, r);
      Object.keys(x).forEach(function (k) { r[k] = copia(x[k]); });
      return r;
    }
    return copia(v);
  });

  // ---------- crypto.subtle.digest (SHA-1 e SHA-256) ----------
  function bytesDe(d) {
    if (d instanceof ArrayBuffer) return new Uint8Array(d);
    if (ArrayBuffer.isView(d)) return new Uint8Array(d.buffer, d.byteOffset, d.byteLength);
    throw new TypeError('data must be a BufferSource');
  }
  function rotl(x, n) { return (x << n) | (x >>> (32 - n)); }
  function rotr(x, n) { return (x >>> n) | (x << (32 - n)); }
  function prepara(b) {
    var n = b.length, total = ((n + 9 + 63) >> 6) << 6, m = new Uint8Array(total);
    m.set(b); m[n] = 0x80;
    var bits = n * 8, dv = new DataView(m.buffer);
    dv.setUint32(total - 8, Math.floor(bits / 4294967296)); dv.setUint32(total - 4, bits >>> 0);
    return dv;
  }
  function sha1(b) {
    var dv = prepara(b), h0 = 0x67452301, h1 = 0xEFCDAB89, h2 = 0x98BADCFE, h3 = 0x10325476, h4 = 0xC3D2E1F0, w = new Array(80);
    for (var o = 0; o < dv.byteLength; o += 64) {
      for (var i = 0; i < 16; i++) w[i] = dv.getUint32(o + i * 4);
      for (i = 16; i < 80; i++) w[i] = rotl(w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16], 1);
      var a = h0, bb = h1, c = h2, d = h3, e = h4;
      for (i = 0; i < 80; i++) {
        var f, k;
        if (i < 20) { f = (bb & c) | (~bb & d); k = 0x5A827999; } else if (i < 40) { f = bb ^ c ^ d; k = 0x6ED9EBA1; }
        else if (i < 60) { f = (bb & c) | (bb & d) | (c & d); k = 0x8F1BBCDC; } else { f = bb ^ c ^ d; k = 0xCA62C1D6; }
        var t = (rotl(a, 5) + f + e + k + w[i]) | 0; e = d; d = c; c = rotl(bb, 30); bb = a; a = t;
      }
      h0 = (h0 + a) | 0; h1 = (h1 + bb) | 0; h2 = (h2 + c) | 0; h3 = (h3 + d) | 0; h4 = (h4 + e) | 0;
    }
    var out = new DataView(new ArrayBuffer(20));
    [h0, h1, h2, h3, h4].forEach(function (h, i) { out.setUint32(i * 4, h >>> 0); });
    return out.buffer;
  }
  var K256 = [0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da, 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2];
  function sha256(b) {
    var dv = prepara(b), h = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19], w = new Array(64);
    for (var o = 0; o < dv.byteLength; o += 64) {
      for (var i = 0; i < 16; i++) w[i] = dv.getUint32(o + i * 4);
      for (i = 16; i < 64; i++) {
        var s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >>> 3), s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >>> 10);
        w[i] = (w[i - 16] + s0 + w[i - 7] + s1) | 0;
      }
      var a = h[0], bb = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7];
      for (i = 0; i < 64; i++) {
        var S1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25), ch = (e & f) ^ (~e & g), t1 = (hh + S1 + ch + K256[i] + w[i]) | 0;
        var S0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22), mj = (a & bb) ^ (a & c) ^ (bb & c), t2 = (S0 + mj) | 0;
        hh = g; g = f; f = e; e = (d + t1) | 0; d = c; c = bb; bb = a; a = (t1 + t2) | 0;
      }
      h = [(h[0] + a) | 0, (h[1] + bb) | 0, (h[2] + c) | 0, (h[3] + d) | 0, (h[4] + e) | 0, (h[5] + f) | 0, (h[6] + g) | 0, (h[7] + hh) | 0];
    }
    var out = new DataView(new ArrayBuffer(32));
    h.forEach(function (x, i) { out.setUint32(i * 4, x >>> 0); });
    return out.buffer;
  }
  function naoSuportado(nome) { return function () { return Promise.reject(erroDom('Operação ' + nome + ' não é suportada', 'NotSupportedError')); }; }
  if (G.crypto && !G.crypto.subtle) {
    var subtle = {
      digest: function (alg, dados) {
        return new Promise(function (ok, no) {
          try {
            var nome = String(typeof alg === 'string' ? alg : alg && alg.name).toUpperCase().replace(/[^A-Z0-9]/g, ''), b = bytesDe(dados);
            if (nome === 'SHA256') ok(sha256(b)); else if (nome === 'SHA1') ok(sha1(b));
            else no(erroDom('Algoritmo não suportado: ' + nome, 'NotSupportedError'));
          } catch (e) { no(e); }
        });
      }
    };
    ['importKey', 'exportKey', 'generateKey', 'encrypt', 'decrypt', 'sign', 'verify', 'deriveBits', 'deriveKey', 'wrapKey', 'unwrapKey'].forEach(function (n) { subtle[n] = naoSuportado(n); });
    try { G.crypto.subtle = subtle; } catch (e) { forca(G.crypto, 'subtle', subtle); }
  }
  // Classes que os sites citam em instanceof ou em verificações de recurso (o ChatGPT falhava com "Can't find variable: CryptoKey").
  forma('CryptoKey', function () { return false; });
  forma('SubtleCrypto', function (v) { return !!v && typeof v.digest === 'function'; });
  forma('Crypto', function (v) { return !!v && typeof v.getRandomValues === 'function'; });
  G.__extra = true;
})(this);
"""#
}
