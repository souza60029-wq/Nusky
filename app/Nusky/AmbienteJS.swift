// app/Nusky/AmbienteJS.swift
// Gerado a partir de ambiente.js. Não edite o JavaScript aqui sem testar no Node primeiro.
// Raw string (#"""): as barras do JavaScript passam sem alteração.

/// Ambiente de navegador que roda dentro do JavaScriptCore:
/// DOM real (árvore, seletores, eventos), temporizadores, fetch, XHR, URL, storage.
enum AmbienteJS {
    static let codigo = #"""
// Ambiente de navegador do Nusky: DOM real, eventos, temporizadores, fetch, XHR, URL.
// Roda dentro do JavaScriptCore. Nativo fornece: __parse, __erro, __pedir, __fim, __pagina.
(function (G) {
  'use strict';
  var pagina = G.__pagina;
  var inicioMs = Date.now();
  var nada = function () {};
  var doc = null;

  // ---------- util ----------
  function kebab(s) { return String(s).replace(/[A-Z]/g, function (c) { return '-' + c.toLowerCase(); }); }
  function camel(s) { return String(s).replace(/-([a-z])/g, function (_, c) { return c.toUpperCase(); }); }
  function esc(s) { return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;'); }
  function escAttr(s) { return s.replace(/&/g, '&amp;').replace(/"/g, '&quot;'); }
  function erro(m) { try { G.__erro(String(m)); } catch (e) {} }
  var VAZIAS = { area: 1, base: 1, br: 1, col: 1, embed: 1, hr: 1, img: 1, input: 1, link: 1, meta: 1, source: 1, track: 1, wbr: 1 };
  var CRUS = { script: 1, style: 1 };

  // ---------- URL ----------
  function resolverCaminho(p) {
    var partes = p.split('/'), saida = [];
    for (var i = 0; i < partes.length; i++) {
      var s = partes[i];
      if (s === '..') { if (saida.length > 1) saida.pop(); }
      else if (s !== '.') saida.push(s);
    }
    var r = saida.join('/');
    var ultimo = partes[partes.length - 1];
    if ((ultimo === '.' || ultimo === '..') && r.charAt(r.length - 1) !== '/') r += '/';
    return r;
  }
  var RE_URL = /^([a-zA-Z][a-zA-Z0-9+.\-]*:)?(?:\/\/([^\/?#]*))?([^?#]*)(\?[^#]*)?(#.*)?$/;
  function analisarUrl(str, base) {
    str = String(str).replace(/^\s+|\s+$/g, '');
    var m = RE_URL.exec(str);
    if (!m) throw new TypeError('URL inválida: ' + str);
    var protocolo = m[1], host = m[2], caminho = m[3] || '', busca = m[4] || '', hash = m[5] || '';
    if (!protocolo) {
      if (!base) throw new TypeError('URL inválida: ' + str);
      var b = base instanceof URL ? base : new URL(base);
      protocolo = b.protocol;
      if (host === undefined) {
        host = b.__host;
        if (caminho === '') { caminho = b.pathname; if (!m[4]) busca = b.search; }
        else if (caminho.charAt(0) !== '/') {
          var dir = b.pathname.replace(/[^\/]*$/, '');
          caminho = dir + caminho;
        }
      }
    }
    protocolo = protocolo.toLowerCase();
    if (host === undefined) host = '';
    if (caminho === '' && (protocolo === 'http:' || protocolo === 'https:')) caminho = '/';
    if (caminho.charAt(0) === '/') caminho = resolverCaminho(caminho);
    return { protocolo: protocolo, host: host.toLowerCase(), caminho: caminho, busca: busca === '?' ? '' : busca, hash: hash === '#' ? '' : hash };
  }
  function URL(str, base) {
    if (!(this instanceof URL)) throw new TypeError('use new');
    var p = analisarUrl(str, base);
    this.protocol = p.protocolo; this.__host = p.host; this.pathname = p.caminho; this.hash = p.hash;
    var self = this;
    this.searchParams = new URLSearchParams(p.busca);
    this.searchParams.__aoMudar = function () { self.__busca = null; };
    this.__busca = p.busca;
  }
  Object.defineProperties(URL.prototype, {
    search: { get: function () { if (this.__busca === null) { var s = this.searchParams.toString(); this.__busca = s ? '?' + s : ''; } return this.__busca; },
              set: function (v) { v = String(v); this.__busca = v && v.charAt(0) !== '?' ? '?' + v : v; this.searchParams.__recarregar(this.__busca); } },
    host: { get: function () { return this.__host; }, set: function (v) { this.__host = String(v).toLowerCase(); } },
    hostname: { get: function () { return this.__host.replace(/:\d+$/, ''); }, set: function (v) { var m = /:\d+$/.exec(this.__host); this.__host = String(v).toLowerCase() + (m ? m[0] : ''); } },
    port: { get: function () { var m = /:(\d+)$/.exec(this.__host); return m ? m[1] : ''; } },
    origin: { get: function () { return this.protocol + '//' + this.__host; } },
    href: { get: function () { return this.protocol + (this.__host || this.protocol === 'file:' ? '//' + this.__host : '') + this.pathname + this.search + this.hash; },
            set: function (v) { var n = new URL(v); this.protocol = n.protocol; this.__host = n.__host; this.pathname = n.pathname; this.search = n.search; this.hash = n.hash; } }
  });
  URL.prototype.toString = function () { return this.href; };
  URL.prototype.toJSON = function () { return this.href; };
  URL.canParse = function (u, b) { try { new URL(u, b); return true; } catch (e) { return false; } };
  function decUri(s) { try { return decodeURIComponent(s.replace(/\+/g, ' ')); } catch (e) { return s; } }
  function URLSearchParams(init) {
    this.__l = [];
    this.__aoMudar = null;
    if (init && typeof init === 'object') {
      if (init instanceof URLSearchParams) this.__l = init.__l.map(function (p) { return [p[0], p[1]]; });
      else if (Array.isArray(init)) { for (var i = 0; i < init.length; i++) this.__l.push([String(init[i][0]), String(init[i][1])]); }
      else { for (var k in init) if (Object.prototype.hasOwnProperty.call(init, k)) this.__l.push([k, String(init[k])]); }
    } else if (typeof init === 'string') this.__recarregar(init);
  }
  URLSearchParams.prototype.__recarregar = function (s) {
    s = String(s).replace(/^\?/, ''); this.__l = [];
    if (!s) return;
    var ps = s.split('&');
    for (var i = 0; i < ps.length; i++) {
      if (!ps[i]) continue;
      var j = ps[i].indexOf('=');
      this.__l.push(j < 0 ? [decUri(ps[i]), ''] : [decUri(ps[i].slice(0, j)), decUri(ps[i].slice(j + 1))]);
    }
  };
  URLSearchParams.prototype.__m = function () { if (this.__aoMudar) this.__aoMudar(); };
  URLSearchParams.prototype.append = function (k, v) { this.__l.push([String(k), String(v)]); this.__m(); };
  URLSearchParams.prototype.set = function (k, v) {
    k = String(k); var ach = false, n = [];
    for (var i = 0; i < this.__l.length; i++) { if (this.__l[i][0] === k) { if (!ach) { ach = true; n.push([k, String(v)]); } } else n.push(this.__l[i]); }
    if (!ach) n.push([k, String(v)]);
    this.__l = n; this.__m();
  };
  URLSearchParams.prototype.get = function (k) { for (var i = 0; i < this.__l.length; i++) if (this.__l[i][0] === k) return this.__l[i][1]; return null; };
  URLSearchParams.prototype.getAll = function (k) { return this.__l.filter(function (p) { return p[0] === k; }).map(function (p) { return p[1]; }); };
  URLSearchParams.prototype.has = function (k) { return this.get(k) !== null; };
  URLSearchParams.prototype['delete'] = function (k) { this.__l = this.__l.filter(function (p) { return p[0] !== k; }); this.__m(); };
  URLSearchParams.prototype.forEach = function (fn, t) { this.__l.slice().forEach(function (p) { fn.call(t, p[1], p[0], this); }, this); };
  URLSearchParams.prototype.keys = function () { return this.__l.map(function (p) { return p[0]; })[Symbol.iterator](); };
  URLSearchParams.prototype.values = function () { return this.__l.map(function (p) { return p[1]; })[Symbol.iterator](); };
  URLSearchParams.prototype.entries = function () { return this.__l.map(function (p) { return [p[0], p[1]]; })[Symbol.iterator](); };
  URLSearchParams.prototype[Symbol.iterator] = URLSearchParams.prototype.entries;
  URLSearchParams.prototype.sort = function () { this.__l.sort(function (a, b) { return a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0; }); this.__m(); };
  URLSearchParams.prototype.toString = function () {
    function c(s) { return encodeURIComponent(s).replace(/%20/g, '+').replace(/[!'()~]/g, function (x) { return '%' + x.charCodeAt(0).toString(16).toUpperCase(); }); }
    return this.__l.map(function (p) { return c(p[0]) + '=' + c(p[1]); }).join('&');
  };
  function resolver(href, base) { try { return new URL(href, base || pagina.href).href; } catch (e) { return null; } }

  // ---------- texto: UTF-8, base64 ----------
  function TextEncoder() { this.encoding = 'utf-8'; }
  TextEncoder.prototype.encode = function (s) {
    s = unescape(encodeURIComponent(String(s === undefined ? '' : s)));
    var a = new Uint8Array(s.length);
    for (var i = 0; i < s.length; i++) a[i] = s.charCodeAt(i);
    return a;
  };
  function TextDecoder(enc) { this.encoding = enc || 'utf-8'; }
  TextDecoder.prototype.decode = function (b) {
    if (!b) return '';
    var a = b instanceof ArrayBuffer ? new Uint8Array(b) : new Uint8Array(b.buffer, b.byteOffset, b.byteLength);
    var s = '';
    for (var i = 0; i < a.length; i += 8192) s += String.fromCharCode.apply(null, a.subarray(i, i + 8192));
    try { return decodeURIComponent(escape(s)); } catch (e) { return s; }
  };
  var B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  G.btoa = function (s) {
    s = String(s); var o = '';
    for (var i = 0; i < s.length; i += 3) {
      var a = s.charCodeAt(i), b = s.charCodeAt(i + 1), c = s.charCodeAt(i + 2);
      if (a > 255 || b > 255 || c > 255) throw new Error('InvalidCharacterError');
      var n = (a << 16) | ((b || 0) << 8) | (c || 0);
      o += B64.charAt(n >> 18 & 63) + B64.charAt(n >> 12 & 63) + (i + 1 < s.length ? B64.charAt(n >> 6 & 63) : '=') + (i + 2 < s.length ? B64.charAt(n & 63) : '=');
    }
    return o;
  };
  G.atob = function (s) {
    s = String(s).replace(/[\s=]+/g, ''); var o = '', bits = 0, v = 0;
    for (var i = 0; i < s.length; i++) {
      var k = B64.indexOf(s.charAt(i)); if (k < 0) throw new Error('InvalidCharacterError');
      v = (v << 6) | k; bits += 6;
      if (bits >= 8) { bits -= 8; o += String.fromCharCode((v >> bits) & 255); }
    }
    return o;
  };

  // ---------- eventos ----------
  function Event(tipo, init) {
    init = init || {};
    this.type = String(tipo); this.bubbles = !!init.bubbles; this.cancelable = !!init.cancelable;
    this.composed = !!init.composed; this.defaultPrevented = false; this.target = null; this.currentTarget = null;
    this.timeStamp = Date.now() - inicioMs; this.isTrusted = false; this.eventPhase = 0;
    this.__parar = false; this.__pararJa = false;
    for (var k in init) if (!(k in this)) this[k] = init[k];
  }
  Event.prototype.preventDefault = function () { if (this.cancelable) this.defaultPrevented = true; };
  Event.prototype.stopPropagation = function () { this.__parar = true; };
  Event.prototype.stopImmediatePropagation = function () { this.__parar = true; this.__pararJa = true; };
  Event.prototype.composedPath = function () { return this.target ? [this.target] : []; };
  function subEvento(nome) {
    var C = function (t, i) { Event.call(this, t, i); };
    C.prototype = Object.create(Event.prototype); C.prototype.constructor = C;
    Object.defineProperty(C, 'name', { value: nome });
    return C;
  }
  function CustomEvent(t, i) { Event.call(this, t, i); this.detail = i && i.detail !== undefined ? i.detail : null; }
  CustomEvent.prototype = Object.create(Event.prototype);

  function disparar(alvo, ev) {
    var l = alvo.__ev && alvo.__ev[ev.type];
    var h = alvo['on' + ev.type];
    ev.currentTarget = alvo;
    if (typeof h === 'function') { try { h.call(alvo, ev); } catch (e) { erro('evento ' + ev.type + ': ' + e); } }
    if (!l) return;
    l = l.slice();
    for (var i = 0; i < l.length; i++) {
      if (ev.__pararJa) break;
      var it = l[i];
      if (it.once) alvo.removeEventListener(ev.type, it.fn);
      try { typeof it.fn === 'function' ? it.fn.call(alvo, ev) : it.fn.handleEvent(ev); } catch (e) { erro('evento ' + ev.type + ': ' + e); }
    }
  }
  var AlvoEventos = {
    addEventListener: function (t, fn, opt) {
      if (!fn) return;
      var m = this.__ev || (this.__ev = {}), l = m[t] || (m[t] = []);
      for (var i = 0; i < l.length; i++) if (l[i].fn === fn) return;
      l.push({ fn: fn, once: !!(opt && typeof opt === 'object' && opt.once) });
    },
    removeEventListener: function (t, fn) {
      var l = this.__ev && this.__ev[t]; if (!l) return;
      for (var i = 0; i < l.length; i++) if (l[i].fn === fn) { l.splice(i, 1); return; }
    },
    dispatchEvent: function (ev) {
      if (!ev.target) ev.target = this;
      var caminho = [], n = this;
      while (n) {
        caminho.push(n);
        if (n === G) break;
        n = n.parentNode || (n === doc ? G : null);
      }
      for (var i = 0; i < caminho.length; i++) {
        if (i > 0 && !ev.bubbles && !(ev.type === 'load' || ev.type === 'DOMContentLoaded')) break;
        disparar(caminho[i], ev);
        if (ev.__parar) break;
      }
      return !ev.defaultPrevented;
    }
  };

  // ---------- seletores ----------
  function lerSeletor(texto) {
    var i = 0, s = String(texto);
    function ident() { var m = /^(?:\\.|[\w\-\u00a0-\uffff])+/.exec(s.slice(i)); if (!m) return ''; i += m[0].length; return m[0].replace(/\\(.)/g, '$1'); }
    function espacos() { var a = i; while (i < s.length && /\s/.test(s.charAt(i))) i++; return i > a; }
    function simples() {
      var r = { tag: null, id: null, cls: [], attrs: [], pseudos: [] }, algo = false;
      if (s.charAt(i) === '*') { i++; algo = true; } else { var t = ident(); if (t) { r.tag = t.toLowerCase(); algo = true; } }
      for (;;) {
        var c = s.charAt(i);
        if (c === '#') { i++; r.id = ident(); algo = true; }
        else if (c === '.') { i++; r.cls.push(ident()); algo = true; }
        else if (c === '[') {
          i++; espacos(); var nome = ident(); espacos(); var op = '', val = '';
          var m = /^([~|^$*]?=)/.exec(s.slice(i));
          if (m) {
            op = m[1]; i += op.length; espacos();
            var q = s.charAt(i);
            if (q === '"' || q === "'") { var f = s.indexOf(q, i + 1); if (f < 0) f = s.length; val = s.slice(i + 1, f); i = f + 1; } else val = ident();
          }
          espacos(); var flag = /^[iIsS]/.test(s.slice(i)) ? s.charAt(i++) : '';
          espacos(); if (s.charAt(i) === ']') i++;
          r.attrs.push({ n: nome.toLowerCase(), op: op, v: val, i: flag.toLowerCase() === 'i' }); algo = true;
        } else if (c === ':') {
          i++; if (s.charAt(i) === ':') i++;
          var pn = ident().toLowerCase(), arg = null;
          if (s.charAt(i) === '(') {
            var prof = 1, ini = ++i;
            while (i < s.length && prof > 0) { var d = s.charAt(i++); if (d === '(') prof++; else if (d === ')') prof--; }
            arg = s.slice(ini, i - 1);
          }
          r.pseudos.push({ n: pn, a: arg }); algo = true;
        } else break;
      }
      return algo ? r : null;
    }
    var lista = [];
    for (;;) {
      espacos();
      var cadeia = [], comb = ' ';
      for (;;) {
        var sm = simples();
        if (!sm) throw new SyntaxError('seletor inválido: ' + texto);
        cadeia.push({ c: comb, s: sm });
        var teveEsp = espacos(), c = s.charAt(i);
        if (c === '>' || c === '+' || c === '~') { comb = c; i++; espacos(); }
        else if (c === ',' || i >= s.length) break;
        else if (teveEsp) comb = ' ';
        else throw new SyntaxError('seletor inválido: ' + texto);
      }
      lista.push(cadeia);
      if (s.charAt(i) === ',') { i++; continue; }
      break;
    }
    return lista;
  }
  var cacheSel = {};
  function seletor(t) { return cacheSel[t] || (cacheSel[t] = lerSeletor(t)); }
  function filhosEl(n) { var r = []; for (var i = 0; i < n.childNodes.length; i++) if (n.childNodes[i].nodeType === 1) r.push(n.childNodes[i]); return r; }
  function nth(expr, pos) {
    expr = expr.replace(/\s+/g, '').toLowerCase();
    if (expr === 'odd') return pos % 2 === 1;
    if (expr === 'even') return pos % 2 === 0;
    var m = /^([+-]?\d*)n([+-]\d+)?$/.exec(expr);
    if (!m) return parseInt(expr, 10) === pos;
    var a = m[1] === '' || m[1] === '+' ? 1 : m[1] === '-' ? -1 : parseInt(m[1], 10), b = m[2] ? parseInt(m[2], 10) : 0;
    if (a === 0) return pos === b;
    return (pos - b) / a >= 0 && (pos - b) % a === 0;
  }
  function casaSimples(el, sm) {
    if (sm.tag && el.localName !== sm.tag) return false;
    if (sm.id !== null && el.getAttribute('id') !== sm.id) return false;
    for (var i = 0; i < sm.cls.length; i++) if (!el.classList.contains(sm.cls[i])) return false;
    for (i = 0; i < sm.attrs.length; i++) {
      var a = sm.attrs[i], v = el.getAttribute(a.n);
      if (v === null) return false;
      if (!a.op) continue;
      var x = a.i ? v.toLowerCase() : v, y = a.i ? a.v.toLowerCase() : a.v;
      if (a.op === '=' && x !== y) return false;
      if (a.op === '~=' && x.split(/\s+/).indexOf(y) < 0) return false;
      if (a.op === '|=' && x !== y && x.indexOf(y + '-') !== 0) return false;
      if (a.op === '^=' && (!y || x.indexOf(y) !== 0)) return false;
      if (a.op === '$=' && (!y || x.slice(-y.length) !== y)) return false;
      if (a.op === '*=' && (!y || x.indexOf(y) < 0)) return false;
    }
    for (i = 0; i < sm.pseudos.length; i++) {
      var p = sm.pseudos[i], pai = el.parentNode, irmaos = pai ? filhosEl(pai) : [el], pos = irmaos.indexOf(el) + 1;
      switch (p.n) {
        case 'first-child': if (pos !== 1) return false; break;
        case 'last-child': if (pos !== irmaos.length) return false; break;
        case 'only-child': if (irmaos.length !== 1) return false; break;
        case 'nth-child': if (!nth(p.a, pos)) return false; break;
        case 'nth-last-child': if (!nth(p.a, irmaos.length - pos + 1)) return false; break;
        case 'first-of-type': case 'last-of-type': case 'nth-of-type': {
          var mesmos = irmaos.filter(function (e) { return e.localName === el.localName; }), k = mesmos.indexOf(el) + 1;
          if (p.n === 'first-of-type' && k !== 1) return false;
          if (p.n === 'last-of-type' && k !== mesmos.length) return false;
          if (p.n === 'nth-of-type' && !nth(p.a, k)) return false;
          break;
        }
        case 'empty': if (el.childNodes.length) return false; break;
        case 'root': if (el !== doc.documentElement) return false; break;
        case 'not': if (casaLista(el, seletor(p.a))) return false; break;
        case 'is': case 'where': case 'matches': if (!casaLista(el, seletor(p.a))) return false; break;
        case 'checked': if (!el.checked) return false; break;
        case 'disabled': if (!el.hasAttribute('disabled')) return false; break;
        case 'enabled': if (el.hasAttribute('disabled')) return false; break;
        case 'link': case 'any-link': if (el.localName !== 'a' || !el.hasAttribute('href')) return false; break;
        default: return false;
      }
    }
    return true;
  }
  function casaCadeia(el, cadeia, k) {
    if (!casaSimples(el, cadeia[k].s)) return false;
    if (k === 0) return true;
    var c = cadeia[k].c, p;
    if (c === '>') { p = el.parentNode; return !!(p && p.nodeType === 1 && casaCadeia(p, cadeia, k - 1)); }
    if (c === ' ') { p = el.parentNode; while (p && p.nodeType === 1) { if (casaCadeia(p, cadeia, k - 1)) return true; p = p.parentNode; } return false; }
    if (c === '+') { p = el.previousElementSibling; return !!(p && casaCadeia(p, cadeia, k - 1)); }
    p = el.previousElementSibling;
    while (p) { if (casaCadeia(p, cadeia, k - 1)) return true; p = p.previousElementSibling; }
    return false;
  }
  function casaLista(el, lista) { for (var i = 0; i < lista.length; i++) if (casaCadeia(el, lista[i], lista[i].length - 1)) return true; return false; }
  function buscar(raiz, texto, primeiro) {
    var lista = seletor(texto), achados = [];
    (function visita(n) {
      for (var i = 0; i < n.childNodes.length; i++) {
        var f = n.childNodes[i];
        if (f.nodeType !== 1) continue;
        if (casaLista(f, lista)) { achados.push(f); if (primeiro) return true; }
        if (visita(f) && primeiro) return true;
  