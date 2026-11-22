// Ambiente de navegador do Nusky: DOM real, eventos, temporizadores, fetch, XHR, URL.
// Roda dentro do JavaScriptCore. Nativo fornece: __parse, __erro, __pedir, __fim, __pagina.
(function (G) {
  'use strict';
  var pagina = G.__pagina;
  var inicioMs = Date.now();
  var nada = function () {};
  var doc = null;
  // Conta mudanças no DOM. O modo vivo só redesenha quando esse número anda.
  var sujeira = 0;
  // MutationObserver: cada mutação do DOM vira um registro para quem observa aquele nó (ou um ancestral, com subtree).
  var observadores = [];
  function contemNo(a, n) { for (var p = n.parentNode; p; p = p.parentNode) if (p === a) return true; return false; }
  function registrar(tipo, alvo, d) {
    for (var i = 0; i < observadores.length; i++) {
      var o = observadores[i];
      for (var j = 0; j < o.__regs.length; j++) {
        var r = o.__regs[j], op = r.opts;
        if (!(r.alvo === alvo || (op.subtree && contemNo(r.alvo, alvo)))) continue;
        if (tipo === 'childList' && !op.childList) continue;
        if (tipo === 'attributes' && (!op.attributes || (op.attributeFilter && op.attributeFilter.indexOf(d.name) < 0))) continue;
        if (tipo === 'characterData' && !op.characterData) continue;
        o.__fila.push({ type: tipo, target: alvo, addedNodes: d.added || [], removedNodes: d.removed || [], previousSibling: d.prev || null, nextSibling: d.next || null,
          attributeName: tipo === 'attributes' ? d.name : null, attributeNamespace: null,
          oldValue: ((tipo === 'attributes' && op.attributeOldValue) || (tipo === 'characterData' && op.characterDataOldValue)) ? d.old : null });
        if (!o.__agendado) {
          o.__agendado = true;
          (function (ob) { Promise.resolve().then(function () {
            ob.__agendado = false;
            var f = ob.__fila; ob.__fila = [];
            if (f.length) { try { ob.__cb.call(ob, f, ob); } catch (e) { erro('MutationObserver: ' + e); } }
          }); })(o);
        }
        break;
      }
    }
  }

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
    if (typeof h !== 'function' && alvo.__attrs) {
      var av = alvo.getAttribute('on' + ev.type);
      if (av) { try { h = alvo['on' + ev.type] = new Function('event', av); } catch (e) { erro('on' + ev.type + ': ' + e); h = null; } }
    }
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
      if (vivo && (t === 'click' || t === 'mousedown' || t === 'mouseup' || t === 'pointerdown' || t === 'pointerup' || t === 'touchend')) { sujeira++; pedirTick(); }
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
        n = n.parentNode || n.__host || (n === doc ? G : null);
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
  // Caminho quente de qualquer seletor: lê os atributos direto, sem criar classList a cada elemento.
  function atributoDireto(el, nome) { var a = el.__attrs; for (var i = 0; i < a.length; i++) if (a[i][0] === nome) return a[i][1]; return null; }
  function temClasse(el, c) {
    var v = atributoDireto(el, 'class');
    if (v === null || v === '') return false;
    var i = v.indexOf(c), n = c.length;
    while (i >= 0) {
      var a = i === 0 ? 32 : v.charCodeAt(i - 1), b = i + n >= v.length ? 32 : v.charCodeAt(i + n);
      if ((a === 32 || a === 9 || a === 10 || a === 13 || a === 12) && (b === 32 || b === 9 || b === 10 || b === 13 || b === 12)) return true;
      i = v.indexOf(c, i + 1);
    }
    return false;
  }
  function casaSimples(el, sm) {
    if (sm.tag && el.localName !== sm.tag) return false;
    if (sm.id !== null && atributoDireto(el, 'id') !== sm.id) return false;
    for (var i = 0; i < sm.cls.length; i++) if (!temClasse(el, sm.cls[i])) return false;
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
  // Índice de ids. Todo acerto é conferido (o elemento ainda tem esse id e continua na página), então nunca
  // devolve elemento errado. Quando o DOM não mudou desde que o índice foi montado, o índice é completo: um id
  // que não está nele não existe, e a resposta é imediata. Se a página muda a cada consulta, montar o índice
  // inteiro não compensa; nesse caso vale a busca com saída antecipada de sempre (modo "seguidas").
  var cacheId = Object.create(null), indexadoEm = -1, ultimaConsulta = -1, seguidas = 0;
  function dentroDe(c, raiz) { for (var p = c.parentNode; p; p = p.parentNode) if (p === raiz) return true; return false; }
  function caminhaIds(raiz, id) {
    var achado = null;
    (function visita(n) {
      for (var i = 0; i < n.childNodes.length; i++) {
        var f = n.childNodes[i];
        if (f.nodeType !== 1) continue;
        var v = atributoDireto(f, 'id');
        if (v !== null && v !== '') { if (id === null) { if (!(v in cacheId)) cacheId[v] = f; } else if (v === id) { achado = f; return true; } }
        if (f.childNodes.length && visita(f)) return true;
      }
      return false;
    })(raiz);
    return achado;
  }
  function porId(raiz, id) {
    var c = cacheId[id];
    if (c && atributoDireto(c, 'id') === id && (raiz === doc ? c.isConnected : dentroDe(c, raiz))) return c;
    if (raiz === doc) {
      if (indexadoEm === sujeira) return null;
      seguidas = sujeira === ultimaConsulta ? 0 : seguidas + 1;
      ultimaConsulta = sujeira;
      if (seguidas <= 3) { cacheId = Object.create(null); caminhaIds(doc, null); indexadoEm = sujeira; return cacheId[id] || null; }
    }
    var achado = caminhaIds(raiz, id);
    if (achado) cacheId[id] = achado;
    return achado;
  }
  var RE_SO_ID = /^#([A-Za-z_][\w-]*)$/;
  function buscar(raiz, texto, primeiro) {
    if (primeiro) { var mi = RE_SO_ID.exec(texto); if (mi) { var ei = porId(raiz, mi[1]); return ei ? [ei] : []; } }
    var lista = seletor(texto), achados = [];
    (function visita(n) {
      for (var i = 0; i < n.childNodes.length; i++) {
        var f = n.childNodes[i];
        if (f.nodeType !== 1) continue;
        if (casaLista(f, lista)) { achados.push(f); if (primeiro) return true; }
        if (visita(f) && primeiro) return true;
      }
      return false;
    })(raiz);
    return achados;
  }

  // ---------- nós ----------
  function Node(tipo) { this.nodeType = tipo; this.parentNode = null; this.childNodes = []; this.ownerDocument = doc; }
  Node.prototype = Object.create(Object.prototype);
  for (var kEv in AlvoEventos) Node.prototype[kEv] = AlvoEventos[kEv];
  Node.ELEMENT_NODE = 1; Node.TEXT_NODE = 3; Node.COMMENT_NODE = 8; Node.DOCUMENT_NODE = 9; Node.DOCUMENT_FRAGMENT_NODE = 11;
  function def(proto, props) { Object.keys(props).forEach(function (k) { Object.defineProperty(proto, k, { get: props[k].get, set: props[k].set, configurable: true }); }); }
  def(Node.prototype, {
    firstChild: { get: function () { return this.childNodes[0] || null; } },
    lastChild: { get: function () { return this.childNodes[this.childNodes.length - 1] || null; } },
    nextSibling: { get: function () { var p = this.parentNode; if (!p) return null; return p.childNodes[p.childNodes.indexOf(this) + 1] || null; } },
    previousSibling: { get: function () { var p = this.parentNode; if (!p) return null; var i = p.childNodes.indexOf(this); return i > 0 ? p.childNodes[i - 1] : null; } },
    parentElement: { get: function () { return this.parentNode && this.parentNode.nodeType === 1 ? this.parentNode : null; } },
    nextElementSibling: { get: function () { var n = this.nextSibling; while (n && n.nodeType !== 1) n = n.nextSibling; return n; } },
    previousElementSibling: { get: function () { var n = this.previousSibling; while (n && n.nodeType !== 1) n = n.previousSibling; return n; } },
    isConnected: { get: function () { var n = this; while (n) { if (n === doc) return true; n = n.parentNode || n.__host || null; } return false; } },
    nodeValue: { get: function () { return this.nodeType === 3 || this.nodeType === 8 ? this.data : null; }, set: function (v) { if (this.nodeType === 3 || this.nodeType === 8) this.data = String(v); } },
    textContent: {
      get: function () {
        if (this.nodeType === 3 || this.nodeType === 8) return this.data;
        var s = ''; for (var i = 0; i < this.childNodes.length; i++) { var f = this.childNodes[i]; if (f.nodeType !== 8) s += f.textContent; } return s;
      },
      set: function (v) {
        if (this.nodeType === 3 || this.nodeType === 8) { this.data = String(v); return; }
        this.__limpar(); v = v == null ? '' : String(v);
        if (v) this.__anexar(doc.createTextNode(v));
      }
    }
  });
  Node.prototype.__limpar = function () { sujeira++; if (observadores.length && this.childNodes.length) registrar('childList', this, { removed: this.childNodes.slice() }); for (var i = 0; i < this.childNodes.length; i++) this.childNodes[i].parentNode = null; this.childNodes = []; };
  Node.prototype.__anexar = function (n) { sujeira++; var ant = this.childNodes[this.childNodes.length - 1]; n.parentNode = this; this.childNodes.push(n); if (observadores.length) registrar('childList', this, { added: [n], prev: ant || null }); };
  Node.prototype.hasChildNodes = function () { return this.childNodes.length > 0; };
  Node.prototype.getRootNode = function () { var n = this; while (n.parentNode) n = n.parentNode; return n; };
  Node.prototype.contains = function (n) { while (n) { if (n === this) return true; n = n.parentNode; } return false; };
  Node.prototype.insertBefore = function (n, ref) {
    if (!n || typeof n.nodeType !== 'number') throw new TypeError('não é um nó');
    if (n.nodeType === 11) { var fs = n.childNodes.slice(); for (var i = 0; i < fs.length; i++) this.insertBefore(fs[i], ref); return n; }
    if (n.contains && n.contains(this)) throw new Error('HierarchyRequestError');
    if (n.parentNode) n.parentNode.removeChild(n);
    var idx = ref ? this.childNodes.indexOf(ref) : this.childNodes.length;
    if (idx < 0) throw new Error('NotFoundError');
    this.childNodes.splice(idx, 0, n);
    n.parentNode = this; sujeira++;
    if (observadores.length) registrar('childList', this, { added: [n], prev: this.childNodes[idx - 1] || null, next: this.childNodes[idx + 1] || null });
    if (n.nodeType === 1 && this.isConnected) iniciarScripts(n);
    return n;
  };
  Node.prototype.appendChild = function (n) { return this.insertBefore(n, null); };
  Node.prototype.removeChild = function (n) {
    var i = this.childNodes.indexOf(n);
    if (i < 0) throw new Error('NotFoundError');
    var ant = this.childNodes[i - 1] || null, dep = this.childNodes[i + 1] || null;
    this.childNodes.splice(i, 1); n.parentNode = null; sujeira++;
    if (observadores.length) registrar('childList', this, { removed: [n], prev: ant, next: dep });
    return n;
  };
  Node.prototype.replaceChild = function (novo, velho) { this.insertBefore(novo, velho); this.removeChild(velho); return velho; };
  Node.prototype.remove = function () { if (this.parentNode) this.parentNode.removeChild(this); };
  function paraNos(args) {
    var r = [];
    for (var i = 0; i < args.length; i++) r.push(args[i] && typeof args[i].nodeType === 'number' ? args[i] : doc.createTextNode(String(args[i])));
    return r;
  }
  Node.prototype.append = function () { var ns = paraNos(arguments); for (var i = 0; i < ns.length; i++) this.appendChild(ns[i]); };
  Node.prototype.prepend = function () { var ns = paraNos(arguments), ref = this.firstChild; for (var i = 0; i < ns.length; i++) this.insertBefore(ns[i], ref); };
  Node.prototype.before = function () { var p = this.parentNode; if (!p) return; var ns = paraNos(arguments); for (var i = 0; i < ns.length; i++) p.insertBefore(ns[i], this); };
  Node.prototype.after = function () { var p = this.parentNode; if (!p) return; var ref = this.nextSibling, ns = paraNos(arguments); for (var i = 0; i < ns.length; i++) p.insertBefore(ns[i], ref); };
  Node.prototype.replaceWith = function () { var p = this.parentNode; if (!p) return; var ref = this.nextSibling, ns = paraNos(arguments); p.removeChild(this); for (var i = 0; i < ns.length; i++) p.insertBefore(ns[i], ref); };
  Node.prototype.replaceChildren = function () { this.__limpar(); this.append.apply(this, arguments); };
  Node.prototype.normalize = nada;
  Node.prototype.isEqualNode = function (o) { return this === o; };
  Node.prototype.isSameNode = function (o) { return this === o; };
  Node.prototype.compareDocumentPosition = function (o) { return this === o ? 0 : this.contains(o) ? 20 : o.contains(this) ? 10 : 4; };
  Node.prototype.cloneNode = function (profundo) {
    var c;
    if (this.nodeType === 3) c = doc.createTextNode(this.data);
    else if (this.nodeType === 8) c = doc.createComment(this.data);
    else if (this.nodeType === 11) c = doc.createDocumentFragment();
    else if (this.nodeType === 1) {
      c = doc.createElement(this.localName); c.namespaceURI = this.namespaceURI;
      for (var i = 0; i < this.__attrs.length; i++) c.__attrs.push([this.__attrs[i][0], this.__attrs[i][1]]);
      c.__ran = true;
    } else return null;
    if (profundo) for (var j = 0; j < this.childNodes.length; j++) c.__anexar(this.childNodes[j].cloneNode(true));
    return c;
  };

  function Text(d) { Node.call(this, 3); this.__d = d === undefined ? '' : String(d); }
  Text.prototype = Object.create(Node.prototype); Text.prototype.constructor = Text;
  Object.defineProperty(Text.prototype, 'data', { get: function () { return this.__d; }, set: function (v) { v = String(v); if (v !== this.__d) { var velho = this.__d; this.__d = v; sujeira++; if (observadores.length) registrar('characterData', this, { old: velho }); } }, configurable: true });
  def(Text.prototype, { nodeName: { get: function () { return '#text'; } }, length: { get: function () { return this.data.length; } }, wholeText: { get: function () { return this.data; } } });
  function Comment(d) { Node.call(this, 8); this.data = d === undefined ? '' : String(d); }
  Comment.prototype = Object.create(Node.prototype); Comment.prototype.constructor = Comment;
  def(Comment.prototype, { nodeName: { get: function () { return '#comment'; } } });
  function DocumentFragment() { Node.call(this, 11); }
  DocumentFragment.prototype = Object.create(Node.prototype); DocumentFragment.prototype.constructor = DocumentFragment;
  def(DocumentFragment.prototype, { nodeName: { get: function () { return '#document-fragment'; } }, children: { get: function () { return filhosEl(this); } } });
  DocumentFragment.prototype.querySelector = function (s) { return buscar(this, s, true)[0] || null; };
  DocumentFragment.prototype.querySelectorAll = function (s) { return buscar(this, s, false); };
  DocumentFragment.prototype.getElementById = function (id) { return buscar(this, '#' + id, true)[0] || null; };

  // estilo
  function Estilo(el) {
    var props = {}, alvo = this;
    Object.defineProperty(this, '__el', { value: el }); Object.defineProperty(this, '__p', { value: props });
    return new Proxy(this, {
      get: function (t, k) {
        if (typeof k === 'symbol') return t[k];
        if (k in Estilo.prototype || k === '__el' || k === '__p') return t[k];
        var v = props[kebab(k)]; return v === undefined ? '' : v;
      },
      set: function (t, k, v) {
        if (k === 'cssText') { t.cssText = v; return true; }
        t.setProperty(kebab(k), v); return true;
      },
      has: function (t, k) { return typeof k === 'string' && (kebab(k) in props || k in Estilo.prototype); },
      ownKeys: function () { return Object.keys(props).map(camel); },
      getOwnPropertyDescriptor: function (t, k) { var n = kebab(k); return n in props ? { value: props[n], enumerable: true, configurable: true, writable: true } : undefined; }
    });
  }
  Estilo.prototype.setProperty = function (n, v) {
    var p = this.__p; n = String(n).toLowerCase();
    if (v === null || v === undefined || v === '') delete p[n]; else p[n] = String(v);
    this.__sincronizar();
  };
  Estilo.prototype.getPropertyValue = function (n) { var v = this.__p[String(n).toLowerCase()]; return v === undefined ? '' : v; };
  Estilo.prototype.removeProperty = function (n) { var v = this.getPropertyValue(n); this.setProperty(n, ''); return v; };
  Estilo.prototype.__sincronizar = function () {
    var p = this.__p, partes = [];
    for (var k in p) partes.push(k + ': ' + p[k]);
    var t = partes.join('; ');
    this.__el.__definirAttr('style', t ? t + ';' : '', true);
  };
  Estilo.prototype.__carregar = function (txt) {
    var p = this.__p; for (var k in p) delete p[k];
    String(txt).split(';').forEach(function (d) {
      var i = d.indexOf(':'); if (i < 0) return;
      var n = d.slice(0, i).trim().toLowerCase(), v = d.slice(i + 1).trim();
      if (n && v) p[n] = v;
    });
  };
  Object.defineProperty(Estilo.prototype, 'cssText', {
    get: function () { var p = this.__p, partes = []; for (var k in p) partes.push(k + ': ' + p[k]); return partes.length ? partes.join('; ') + ';' : ''; },
    set: function (v) { this.__carregar(v); this.__sincronizar(); }
  });
  Object.defineProperty(Estilo.prototype, 'length', { get: function () { return Object.keys(this.__p).length; } });

  // elemento
  function Element(tag) {
    Node.call(this, 1);
    this.localName = String(tag).toLowerCase(); this.namespaceURI = 'http://www.w3.org/1999/xhtml';
    this.__attrs = []; this.__estilo = null; this.__ran = false; this.__parser = false;
  }
  Element.prototype = Object.create(Node.prototype); Element.prototype.constructor = Element;
  def(Element.prototype, {
    tagName: { get: function () { return this.namespaceURI === 'http://www.w3.org/1999/xhtml' ? this.localName.toUpperCase() : this.localName; } },
    nodeName: { get: function () { return this.tagName; } },
    id: { get: function () { return this.getAttribute('id') || ''; }, set: function (v) { this.setAttribute('id', v); } },
    className: { get: function () { return this.getAttribute('class') || ''; }, set: function (v) { this.setAttribute('class', v); } },
    children: { get: function () { return filhosEl(this); } },
    childElementCount: { get: function () { var c = 0, a = this.childNodes; for (var i = 0; i < a.length; i++) if (a[i].nodeType === 1) c++; return c; } },
    firstElementChild: { get: function () { var a = this.childNodes; for (var i = 0; i < a.length; i++) if (a[i].nodeType === 1) return a[i]; return null; } },
    lastElementChild: { get: function () { var a = this.childNodes; for (var i = a.length - 1; i >= 0; i--) if (a[i].nodeType === 1) return a[i]; return null; } },
    attributes: { get: function () { return this.__attrs.map(function (a) { return { name: a[0], value: a[1], nodeName: a[0], nodeValue: a[1] }; }); } },
    style: { get: function () { if (!this.__estilo) { this.__estilo = new Estilo(this); var s = this.getAttribute('style'); if (s) this.__estilo.__carregar(s); } return this.__estilo; },
             set: function (v) { this.style.cssText = v; } },
    classList: { get: function () { return listaClasses(this); } },
    dataset: { get: function () { return conjuntoDados(this); } },
    innerHTML: { get: function () { var o = []; for (var i = 0; i < this.childNodes.length; i++) serializar(this.childNodes[i], o, false); return o.join(''); },
                 set: function (h) { this.__limpar(); var f = fragmento(String(h == null ? '' : h), this); for (var i = 0; i < f.length; i++) this.__anexar(f[i]); } },
    outerHTML: { get: function () { var o = []; serializar(this, o, false); return o.join(''); },
                 set: function (h) { var p = this.parentNode; if (!p) return; var ref = this.nextSibling, f = fragmento(String(h), p); p.removeChild(this); for (var i = 0; i < f.length; i++) p.insertBefore(f[i], ref); } },
    innerText: { get: function () { return this.textContent; }, set: function (v) { this.textContent = v; } },
    value: { get: function () { return this.__valor !== undefined ? this.__valor : (this.getAttribute('value') || ''); }, set: function (v) { this.__valor = String(v); } },
    checked: { get: function () { return this.__marcado !== undefined ? this.__marcado : this.hasAttribute('checked'); }, set: function (v) { this.__marcado = !!v; } },
    disabled: { get: function () { return this.hasAttribute('disabled'); }, set: function (v) { v ? this.setAttribute('disabled', '') : this.removeAttribute('disabled'); } },
    hidden: { get: function () { return this.hasAttribute('hidden'); }, set: function (v) { v ? this.setAttribute('hidden', '') : this.removeAttribute('hidden'); } },
    src: { get: function () { var v = this.getAttribute('src'); return v === null ? '' : (resolver(v) || v); }, set: function (v) { this.setAttribute('src', v); } },
    href: { get: function () { var v = this.getAttribute('href'); return v === null ? '' : (resolver(v) || v); }, set: function (v) { this.setAttribute('href', v); } },
    type: { get: function () { return this.getAttribute('type') || ''; }, set: function (v) { this.setAttribute('type', v); } },
    name: { get: function () { return this.getAttribute('name') || ''; }, set: function (v) { this.setAttribute('name', v); } },
    title: { get: function () { return this.getAttribute('title') || ''; }, set: function (v) { this.setAttribute('title', v); } },
    text: { get: function () { return this.textContent; }, set: function (v) { this.textContent = v; } },
    offsetWidth: { get: function () { return 0; } }, offsetHeight: { get: function () { return 0; } },
    clientWidth: { get: function () { return 0; } }, clientHeight: { get: function () { return 0; } },
    scrollTop: { get: function () { return 0; }, set: nada }, scrollLeft: { get: function () { return 0; }, set: nada },
    scrollHeight: { get: function () { return 0; } }, scrollWidth: { get: function () { return 0; } },
    offsetParent: { get: function () { return null; } }
  });
  Element.prototype.__definirAttr = function (n, v, deEstilo) {
    for (var i = 0; i < this.__attrs.length; i++) if (this.__attrs[i][0] === n) { if (this.__attrs[i][1] !== v) { var velho = this.__attrs[i][1]; this.__attrs[i][1] = v; sujeira++; if (observadores.length) registrar('attributes', this, { name: n, old: velho }); } return; }
    this.__attrs.push([n, v]); sujeira++;
    if (observadores.length) registrar('attributes', this, { name: n, old: null });
  };
  Element.prototype.setAttribute = function (n, v) {
    n = String(n).toLowerCase(); v = String(v);
    this.__definirAttr(n, v);
    if (n === 'style' && this.__estilo) this.__estilo.__carregar(v);
  };
  Element.prototype.getAttribute = function (n) {
    n = String(n).toLowerCase();
    for (var i = 0; i < this.__attrs.length; i++) if (this.__attrs[i][0] === n) return this.__attrs[i][1];
    return null;
  };
  Element.prototype.hasAttribute = function (n) { return this.getAttribute(n) !== null; };
  Element.prototype.removeAttribute = function (n) {
    n = String(n).toLowerCase(); sujeira++;
    for (var i = 0; i < this.__attrs.length; i++) if (this.__attrs[i][0] === n) { var velho = this.__attrs[i][1]; this.__attrs.splice(i, 1); if (observadores.length) registrar('attributes', this, { name: n, old: velho }); break; }
    if (n === 'style' && this.__estilo) this.__estilo.__carregar('');
  };
  Element.prototype.toggleAttribute = function (n, f) { var tem = this.hasAttribute(n), q = f === undefined ? !tem : !!f; q ? this.setAttribute(n, '') : this.removeAttribute(n); return q; };
  Element.prototype.getAttributeNames = function () { return this.__attrs.map(function (a) { return a[0]; }); };
  Element.prototype.setAttributeNS = function (ns, n, v) { this.setAttribute(n, v); };
  Element.prototype.getAttributeNS = function (ns, n) { return this.getAttribute(n); };
  Element.prototype.removeAttributeNS = function (ns, n) { this.removeAttribute(n); };
  Element.prototype.hasAttributes = function () { return this.__attrs.length > 0; };
  Element.prototype.querySelector = function (s) { return buscar(this, s, true)[0] || null; };
  Element.prototype.querySelectorAll = function (s) { return buscar(this, s, false); };
  Element.prototype.matches = function (s) { return casaLista(this, seletor(s)); };
  Element.prototype.webkitMatchesSelector = Element.prototype.matches;
  Element.prototype.closest = function (s) { var l = seletor(s), n = this; while (n && n.nodeType === 1) { if (casaLista(n, l)) return n; n = n.parentNode; } return null; };
  Element.prototype.getElementsByTagName = function (t) { t = String(t).toLowerCase(); return t === '*' ? buscar(this, '*', false) : buscar(this, t, false); };
  Element.prototype.getElementsByClassName = function (c) { return buscar(this, String(c).trim().split(/\s+/).map(function (x) { return '.' + x; }).join(''), false); };
  Element.prototype.insertAdjacentHTML = function (pos, h) {
    var f = fragmento(String(h), this), i;
    pos = String(pos).toLowerCase();
    if (pos === 'beforeend') for (i = 0; i < f.length; i++) this.appendChild(f[i]);
    else if (pos === 'afterbegin') { var r = this.firstChild; for (i = 0; i < f.length; i++) this.insertBefore(f[i], r); }
    else if (this.parentNode) { var ref = pos === 'beforebegin' ? this : this.nextSibling; for (i = 0; i < f.length; i++) this.parentNode.insertBefore(f[i], ref); }
  };
  Element.prototype.insertAdjacentElement = function (pos, el) { this.insertAdjacentHTML(pos, ''); pos = String(pos).toLowerCase();
    if (pos === 'beforeend') this.appendChild(el); else if (pos === 'afterbegin') this.insertBefore(el, this.firstChild);
    else if (this.parentNode) this.parentNode.insertBefore(el, pos === 'beforebegin' ? this : this.nextSibling); return el; };
  Element.prototype.insertAdjacentText = function (pos, t) { this.insertAdjacentElement(pos, doc.createTextNode(t)); };
  Element.prototype.getBoundingClientRect = function () { return { x: 0, y: 0, top: 0, left: 0, right: 0, bottom: 0, width: 0, height: 0 }; };
  Element.prototype.getClientRects = function () { return []; };
  Element.prototype.focus = nada; Element.prototype.blur = nada; Element.prototype.scrollIntoView = nada;
  Element.prototype.scrollTo = nada; Element.prototype.scrollBy = nada; Element.prototype.select = nada;
  Element.prototype.click = function () { this.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true })); };
  Element.prototype.attachShadow = function (init) {
    if (this.__sombra) throw new Error('NotSupportedError: Shadow root cannot be created on a host which already hosts a shadow tree.');
    var f = new DocumentFragment(); f.__host = this; f.host = this; f.mode = (init && init.mode) === 'closed' ? 'closed' : 'open';
    this.__sombra = f; this.shadowRoot = f.mode === 'open' ? f : null; sujeira++;
    return f;
  };
  Element.prototype.animate = function () { return { cancel: nada, finish: nada, onfinish: null, finished: Promise.resolve() }; };
  Element.prototype.requestFullscreen = function () { return Promise.reject(new Error('sem tela cheia')); };
  Element.prototype.setPointerCapture = nada; Element.prototype.releasePointerCapture = nada;
  Element.prototype.checkVisibility = function () { return true; };

  function listaClasses(el) {
    function lista() { return (el.getAttribute('class') || '').split(/\s+/).filter(Boolean); }
    function grava(l) { el.setAttribute('class', l.join(' ')); }
    return {
      add: function () { var l = lista(), mudou = false; for (var i = 0; i < arguments.length; i++) if (l.indexOf(String(arguments[i])) < 0) { l.push(String(arguments[i])); mudou = true; } if (mudou) grava(l); },
      remove: function () { var l = lista(), mudou = false; for (var i = 0; i < arguments.length; i++) { var k = l.indexOf(String(arguments[i])); if (k >= 0) { l.splice(k, 1); mudou = true; } } if (mudou) grava(l); },
      toggle: function (c, f) { c = String(c); var tem = lista().indexOf(c) >= 0, q = f === undefined ? !tem : !!f; if (q && !tem) this.add(c); else if (!q && tem) this.remove(c); return q; },
      contains: function (c) { return lista().indexOf(String(c)) >= 0; },
      replace: function (a, b) { var l = lista(), k = l.indexOf(a); if (k < 0) return false; l[k] = b; grava(l); return true; },
      item: function (i) { return lista()[i] || null; },
      forEach: function (fn) { lista().forEach(fn); },
      toString: function () { return lista().join(' '); },
      get length() { return lista().length; },
      get value() { return el.getAttribute('class') || ''; }
    };
  }
  function conjuntoDados(el) {
    return new Proxy({}, {
      get: function (t, k) { if (typeof k === 'symbol') return undefined; var v = el.getAttribute('data-' + kebab(k)); return v === null ? undefined : v; },
      set: function (t, k, v) { el.setAttribute('data-' + kebab(k), v); return true; },
      deleteProperty: function (t, k) { el.removeAttribute('data-' + kebab(k)); return true; },
      has: function (t, k) { return el.hasAttribute('data-' + kebab(k)); },
      ownKeys: function () { return el.__attrs.filter(function (a) { return a[0].indexOf('data-') === 0; }).map(function (a) { return camel(a[0].slice(5)); }); },
      getOwnPropertyDescriptor: function (t, k) { var v = el.getAttribute('data-' + kebab(k)); return v === null ? undefined : { value: v, enumerable: true, configurable: true, writable: true }; }
    });
  }

  // classes especializadas (instanceof)
  var HTMLElement = function () {}; HTMLElement.prototype = Element.prototype;
  var tiposHTML = ['Div', 'Span', 'Anchor', 'Image', 'Input', 'Button', 'Form', 'Script', 'Style', 'Link', 'Canvas', 'Select', 'TextArea', 'Body', 'Head', 'Html', 'IFrame', 'Template'];
  tiposHTML.forEach(function (n) { G['HTML' + n + 'Element'] = HTMLElement; });
  G.HTMLElement = HTMLElement; G.Element = Element; G.Node = Node; G.Text = Text; G.Comment = Comment;
  G.DocumentFragment = DocumentFragment; G.SVGElement = HTMLElement;
  var MouseEvent = subEvento('MouseEvent');

  // ---------- serialização e fragmentos ----------
  // ---------- cliques: quais elementos o toque deve entregar ao JavaScript ----------
  var marcando = false, mapaClique = {}, proxNid = 1;
  var RE_EVT = /^on(click|mousedown|mouseup|pointerdown|pointerup|touchend)$/;
  var EVC = ['click', 'mousedown', 'mouseup', 'pointerdown', 'pointerup', 'touchend'];
  var TAGS_CLIC = { button: 1, summary: 1, label: 1, select: 1 };
  var ROLES_CLIC = { button: 1, tab: 1, menuitem: 1, link: 1, 'switch': 1, checkbox: 1, radio: 1, option: 1, treeitem: 1 };
  EVC.forEach(function (t) {
    Object.defineProperty(Node.prototype, 'on' + t, {
      get: function () { return this['__on' + t] || null; },
      set: function (v) { this['__on' + t] = v; if (vivo) { sujeira++; pedirTick(); } },
      configurable: true
    });
  });
  function temOuvinteClique(a) {
    var m = a.__ev;
    if (m) for (var i = 0; i < EVC.length; i++) if (m[EVC[i]] && m[EVC[i]].length) return true;
    for (var j = 0; j < EVC.length; j++) if (typeof a['on' + EVC[j]] === 'function') return true;
    if (a.__attrs) for (var k = 0; k < a.__attrs.length; k++) if (RE_EVT.test(a.__attrs[k][0])) return true;
    return false;
  }
  function temTextoDireto(n) {
    for (var i = 0; i < n.childNodes.length; i++) { var f = n.childNodes[i]; if (f.nodeType === 3 && /\S/.test(f.data)) return true; }
    return false;
  }
  // cob: 0 = ninguém escuta cliques acima; 1 = escuta no document/body; 2 = escuta num ancestral.
  // Em 2, o elemento mais interno com texto (ou imagem) é o alvo, como o dedo acertaria de verdade.
  function ehClicavel(n, cob) {
    var t = n.localName;
    if (temOuvinteClique(n)) return true;
    if (t === 'a') { var h = n.getAttribute('href'); return !!(cob && h && h.charAt(0) !== '#' && !/^\s*javascript:/i.test(h)); }
    if (TAGS_CLIC[t]) return true;
    if (t === 'input') { var ty = (n.getAttribute('type') || '').toLowerCase(); return ty === 'checkbox' || ty === 'radio' || ty === 'button' || ty === 'submit' || ty === 'reset'; }
    var r = n.getAttribute('role');
    if (r && ROLES_CLIC[r.toLowerCase()]) return true;
    if (cob === 2 && (t === 'img' || temTextoDireto(n))) return true;
    if (cob) {
      var e = n.getAttribute('style');
      if (e && /cursor\s*:\s*pointer/i.test(e)) return true;
      if (n.hasAttribute('data-toggle') || n.hasAttribute('data-bs-toggle') || n.hasAttribute('data-action') || n.hasAttribute('data-target') || n.hasAttribute('data-href')) return true;
    }
    return false;
  }
  // Destino de navegação do toque: o <a href> mais próximo (vazio se não houver).
  function hrefDe(n) {
    while (n && n.nodeType === 1) {
      if (n.localName === 'a') {
        var h = n.getAttribute('href');
        if (h && h.charAt(0) !== '#' && !/^\s*javascript:/i.test(h)) { var u = resolver(h); return u && /^https?:/i.test(u) ? u : ''; }
      }
      n = n.parentNode;
    }
    return '';
  }
  function serializar(n, o, ignorarScripts, cob, host) {
    if (n.nodeType === 3) {
      var p = n.parentNode;
      o.push(p && p.nodeType === 1 && CRUS[p.localName] ? n.data : esc(n.data));
    } else if (n.nodeType === 8) { o.push('<!--' + n.data + '-->'); }
    else if (n.nodeType === 11 || n.nodeType === 9) { for (var i = 0; i < n.childNodes.length; i++) serializar(n.childNodes[i], o, ignorarScripts, cob, host); }
    else if (n.nodeType === 1) {
      var t = n.localName;
      if (host && t === 'slot') { serializarSlot(n, host, o, ignorarScripts, cob); return; }
      if (ignorarScripts && (t === 'script' || t === 'noscript')) return;
      o.push('<' + t);
      for (var j = 0; j < n.__attrs.length; j++) o.push(' ' + n.__attrs[j][0] + '="' + escAttr(n.__attrs[j][1]) + '"');
      var cobFilhos = cob;
      if (marcando) {
        if (ehClicavel(n, cob)) {
          var nid = n.__nid || (n.__nid = proxNid++);
          mapaClique[nid] = n;
          o.push(' data-nusky-js="' + escAttr('nusky-js:' + nid + '|' + hrefDe(n)) + '"');
        }
        if (cob < 2 && n !== doc.documentElement && n !== doc.body && temOuvinteClique(n)) cobFilhos = 2;
      }
      o.push('>');
      if (VAZIAS[t]) return;
      if (t === 'style' && n.__folha) o.push(n.__folha.__t);
      else if (n.__sombra) {
        // Árvore da sombra achatada: o que o navegador desenharia (a sombra, com os filhos do hospedeiro nos <slot>).
        for (var s1 = 0; s1 < n.__sombra.childNodes.length; s1++) serializar(n.__sombra.childNodes[s1], o, ignorarScripts, cobFilhos, n);
      } else for (var k = 0; k < n.childNodes.length; k++) serializar(n.childNodes[k], o, ignorarScripts, cobFilhos, host);
      o.push('</' + t + '>');
    }
  }
  // <slot>: no lugar dele entram os filhos do hospedeiro que escolheram esse slot (ou o conteúdo reserva do próprio slot).
  function serializarSlot(slot, host, o, ignorarScripts, cob) {
    var nome = slot.getAttribute('name') || '', achou = false;
    for (var i = 0; i < host.childNodes.length; i++) {
      var f = host.childNodes[i], alvo = f.nodeType === 1 ? (f.getAttribute('slot') || '') : '';
      if (f.nodeType === 1 ? alvo === nome : (f.nodeType === 3 && nome === '')) { achou = true; serializar(f, o, ignorarScripts, cob); }
    }
    if (!achou) for (var j = 0; j < slot.childNodes.length; j++) serializar(slot.childNodes[j], o, ignorarScripts, cob, host);
  }
  var SVGNS = 'http://www.w3.org/2000/svg';
  function construir(json, pai, parser, nsPai) {
    for (var i = 0; i < json.length; i++) {
      var j = json[i];
      if (j.t === 'x') { var tx = new Text(j.v); tx.parentNode = pai; pai.childNodes.push(tx); continue; }
      if (j.t === 'c') { var cm = new Comment(j.v); cm.parentNode = pai; pai.childNodes.push(cm); continue; }
      var el = new Element(j.g), ns = nsPai;
      if (j.g === 'svg') ns = SVGNS;
      if (ns) el.namespaceURI = ns;
      for (var a in j.a) el.__attrs.push([a, j.a[a]]);
      el.__ran = !parser; el.__parser = !!parser;
      el.parentNode = pai; pai.childNodes.push(el);
      if (j.g === 'noscript') continue;
      if (j.c && j.c.length) construir(j.c, el, parser, j.g === 'foreignobject' ? null : ns);
    }
  }
  function fragmento(html, contexto) {
    if (html.indexOf('<') < 0 && html.indexOf('&') < 0) return html ? [new Text(html)] : [];
    var json;
    try { json = JSON.parse(G.__parse(html)); } catch (e) { erro('innerHTML: ' + e); return []; }
    var tmp = new DocumentFragment();
    construir(json, tmp, false, contexto && contexto.namespaceURI === SVGNS ? SVGNS : null);
    var r = tmp.childNodes.slice();
    for (var i = 0; i < r.length; i++) r[i].parentNode = null;
    return r;
  }

  // ---------- documento ----------
  function Document() { Node.call(this, 9); }
  Document.prototype = Object.create(Node.prototype); Document.prototype.constructor = Document;
  doc = new Document(); doc.ownerDocument = null;
  def(Document.prototype, {
    nodeName: { get: function () { return '#document'; } },
    children: { get: function () { return filhosEl(this); } },
    title: { get: function () { var t = this.querySelector('title'); return t ? t.textContent : ''; }, set: function (v) {
      var t = this.querySelector('title'); if (!t) { t = this.createElement('title'); (this.head || this.documentElement).appendChild(t); } t.textContent = v; } },
    cookie: { get: function () { return Object.keys(jarra).map(function (k) { return k + '=' + jarra[k]; }).join('; '); },
              set: function (c) { var p = String(c).split(';'), kv = p[0], i = kv.indexOf('='); if (i < 0) return;
                var k = kv.slice(0, i).trim(), v = kv.slice(i + 1).trim(), apagar = false;
                for (var x = 1; x < p.length; x++) { var q = p[x].trim().toLowerCase(); if (q === 'max-age=0' || /^max-age=-/.test(q)) apagar = true; if (q.indexOf('expires=') === 0 && Date.parse(q.slice(8)) < Date.now()) apagar = true; }
                if (apagar) delete jarra[k]; else jarra[k] = v; } },
    URL: { get: function () { return pagina.href; } }, documentURI: { get: function () { return pagina.href; } },
    baseURI: { get: function () { return pagina.href; } },
    domain: { get: function () { return pagina.host.replace(/:\d+$/, ''); } },
    referrer: { get: function () { return ''; } },
    characterSet: { get: function () { return 'UTF-8'; } }, charset: { get: function () { return 'UTF-8'; } },
    contentType: { get: function () { return 'text/html'; } }, compatMode: { get: function () { return 'CSS1Compat'; } },
    visibilityState: { get: function () { return 'visible'; } }, hidden: { get: function () { return false; } },
    activeElement: { get: function () { return this.body; } },
    scrollingElement: { get: function () { return this.documentElement; } },
    forms: { get: function () { return buscar(this, 'form', false); } }, images: { get: function () { return buscar(this, 'img', false); } },
    scripts: { get: function () { return buscar(this, 'script', false); } }, links: { get: function () { return buscar(this, 'a[href]', false); } },
    all: { get: function () { return buscar(this, '*', false); } }, fonts: { get: function () { return { ready: Promise.resolve(), load: function () { return Promise.resolve([]); }, check: function () { return true; }, addEventListener: nada, forEach: nada }; } },
    styleSheets: { get: function () { return []; } }, adoptedStyleSheets: { get: function () { return []; }, set: nada },
    cookieEnabled: { get: function () { return true; } },
    documentElement: { get: function () { for (var i = 0; i < this.childNodes.length; i++) { var f = this.childNodes[i]; if (f.nodeType === 1 && f.localName === 'html') return f; } return null; } },
    head: { get: function () { var h = this.documentElement; if (!h) return null; for (var i = 0; i < h.childNodes.length; i++) if (h.childNodes[i].localName === 'head') return h.childNodes[i]; return null; } },
    body: { get: function () { var h = this.documentElement; if (!h) return null; for (var i = 0; i < h.childNodes.length; i++) if (h.childNodes[i].localName === 'body') return h.childNodes[i]; return null; } }
  });
  var jarra = {};
  doc.readyState = 'loading'; doc.defaultView = G; doc.nodeType = 9;
  Document.prototype.createElement = function (t) { var e = new Element(String(t)); e.__ran = false; return e; };
  Document.prototype.createElementNS = function (ns, t) { var e = new Element(String(t)); e.namespaceURI = ns || 'http://www.w3.org/1999/xhtml'; return e; };
  Document.prototype.createTextNode = function (t) { return new Text(t); };
  Document.prototype.createComment = function (t) { return new Comment(t); };
  Document.prototype.createDocumentFragment = function () { return new DocumentFragment(); };
  Document.prototype.createEvent = function (t) { return new Event(''); };
  Document.prototype.createRange = function () { return { setStart: nada, setEnd: nada, selectNodeContents: nada, collapse: nada, getBoundingClientRect: function () { return { top: 0, left: 0, width: 0, height: 0, right: 0, bottom: 0 }; }, getClientRects: function () { return []; }, createContextualFragment: function (h) { var f = new DocumentFragment(); fragmento(h, null).forEach(function (n) { f.appendChild(n); }); return f; } }; };
  Document.prototype.createTreeWalker = function () { return { nextNode: function () { return null; } }; };
  Document.prototype.getElementById = function (id) { return porId(this, String(id)); };
  Document.prototype.getElementsByTagName = Element.prototype.getElementsByTagName;
  Document.prototype.getElementsByClassName = Element.prototype.getElementsByClassName;
  Document.prototype.getElementsByName = function (n) { return buscar(this, '[name="' + n + '"]', false); };
  Document.prototype.querySelector = Element.prototype.querySelector;
  Document.prototype.querySelectorAll = Element.prototype.querySelectorAll;
  Document.prototype.hasFocus = function () { return true; };
  Document.prototype.getSelection = function () { return null; };
  Document.prototype.elementFromPoint = function () { return null; };
  Document.prototype.execCommand = function () { return false; };
  Document.prototype.importNode = function (n, p) { return n.cloneNode(!!p); };
  Document.prototype.adoptNode = function (n) { return n; };
  Document.prototype.open = nada; Document.prototype.close = nada;
  Document.prototype.write = function (h) {
    var f = fragmento(String(h), null), atual = doc.currentScript;
    // marca como "do analisador": os scripts novos rodam na ordem, logo depois do atual
    (function marca(ns) { for (var i = 0; i < ns.length; i++) { if (ns[i].nodeType === 1) { ns[i].__parser = true; ns[i].__ran = false; marca(ns[i].childNodes); } } })(f);
    var alvo = atual && atual.parentNode ? atual.parentNode : (doc.body || doc.documentElement || doc);
    var ref = atual && atual.parentNode ? atual.nextSibling : null;
    var anterior = fase.pronto; fase.pronto = false;
    for (var i = 0; i < f.length; i++) alvo.insertBefore(f[i], ref);
    fase.pronto = anterior;
  };
  Document.prototype.writeln = function (h) { this.write(String(h) + '\n'); };

  // ---------- montagem do documento a partir da árvore do Rust ----------
  function montarDocumento(json) {
    construir(json, doc, true, null);
    var html = doc.documentElement;
    if (!html) {
      html = new Element('html');
      var cab0 = null, corpo0 = null, antigos = doc.childNodes.slice();
      doc.__limpar(); doc.__anexar(html);
      for (var i = 0; i < antigos.length; i++) {
        var a = antigos[i]; a.parentNode = null;
        if (a.nodeType === 1 && a.localName === 'head') cab0 = a;
        else if (a.nodeType === 1 && a.localName === 'body') corpo0 = a;
      }
      cab0 = cab0 || new Element('head'); corpo0 = corpo0 || new Element('body');
      html.__anexar(cab0); html.__anexar(corpo0);
      for (var j = 0; j < antigos.length; j++) {
        var b = antigos[j];
        if (b === cab0 || b === corpo0) continue;
        var t = b.nodeType === 1 ? b.localName : '';
        (t === 'style' || t === 'link' || t === 'meta' || t === 'title' || t === 'base' ? cab0 : corpo0).__anexar(b);
      }
    }
    if (!doc.head) { var h = new Element('head'); h.parentNode = html; html.childNodes.unshift(h); }
    if (!doc.body) { var b = new Element('body'); html.__anexar(b); }
  }

  // ---------- temporizadores (tempo virtual) ----------
  var fila = [], reserva = [], proxId = 1, agora = 0, execTimers = 0, HORIZONTE = 10000, MAX_TIMERS = 4000;
  // Modo vivo: depois da primeira exibição o JavaScript continua, com relógio de verdade
  // e frequência limitada (economia de CPU, bateria e memória no iPhone 6s).
  var vivo = false, pausado = false, pausadoEm = 0, proximoDue = Infinity;
  var bombaAgendada = false;
  function bombearTimers() {
    if (vivo || bombaAgendada) return;
    bombaAgendada = true;
    Promise.resolve().then(function () { bombaAgendada = false; drenar(); });
  }
  function agendar(fn, ms, args, repete) {
    ms = Math.max(0, Number(ms) || 0);
    if (vivo) ms = Math.max(ms, 4);
    var t = { id: proxId++, fn: fn, args: args, due: (vivo ? Date.now() : agora) + ms, ms: Math.max(ms, 1), repete: repete, vezes: 0 };
    fila.push(t);
    if (vivo && !pausado && t.due < proximoDue) { proximoDue = t.due; acordar(t.due - Date.now()); }
    // Um módulo com await no topo continua depois de uma microtarefa, e ninguém mais chama o escoador de temporizadores
    // virtuais nessa hora: sem isto, "await new Promise(r => setTimeout(r, 50))" ficava parado até os 6 s.
    if (moduloEsperando) bombearTimers();
    return t.id;
  }
  function acordar(ms) { try { G.__acordar(Math.max(0, ms)); } catch (e) {} }
  function pedirTick() { if (vivo) agendar(nada, 0, [], false); }
  G.setTimeout = function (fn, ms) { if (typeof fn !== 'function') return 0; return agendar(fn, ms, Array.prototype.slice.call(arguments, 2), false); };
  G.setInterval = function (fn, ms) { if (typeof fn !== 'function') return 0; return agendar(fn, ms, Array.prototype.slice.call(arguments, 2), true); };
  G.clearTimeout = G.clearInterval = function (id) { fila = fila.filter(function (t) { return t.id !== id; }); if (reserva.length) reserva = reserva.filter(function (t) { return t.id !== id; }); };
  // Quadros: 60 por segundo, até o desenho da tela ficar caro. Aí o nativo informa o custo e os quadros que
  // ninguém chegaria a ver deixam de ser calculados (como um navegador que perde quadros sob carga).
  var cadencia = 16;
  G.__cadencia = function (ms) { cadencia = Math.max(16, Math.min(1000, Number(ms) || 16)); };
  G.requestAnimationFrame = function (fn) { return agendar(function () { fn(Date.now() - inicioMs); }, vivo ? cadencia : 16, [], false); };
  G.cancelAnimationFrame = G.clearTimeout;
  G.requestIdleCallback = function (fn) { return agendar(function () { fn({ didTimeout: false, timeRemaining: function () { return 10; } }); }, 1, [], false); };
  G.cancelIdleCallback = G.clearTimeout;
  G.queueMicrotask = function (fn) { Promise.resolve().then(fn).catch(function (e) { erro('microtask: ' + e); }); };
  function drenar() {
    if (vivo) return;
    while (fila.length && execTimers < MAX_TIMERS) {
      var k = 0;
      for (var i = 1; i < fila.length; i++) if (fila[i].due < fila[k].due || (fila[i].due === fila[k].due && fila[i].id < fila[k].id)) k = i;
      var t = fila[k];
      if (t.due > HORIZONTE) break;
      fila.splice(k, 1); agora = Math.max(agora, t.due); execTimers++;
      if (t.repete) { t.vezes++; t.due = agora + t.ms; if (t.vezes < 10) fila.push(t); else reserva.push(t); }
      try { t.fn.apply(G, t.args); } catch (e) { erro('temporizador: ' + e); }
    }
    // O que sobrou (muito adiante, ou o limite de tempo virtual) não se perde: espera o modo vivo.
    if (fila.length) { reserva = reserva.concat(fila); fila = []; }
  }
  var entregue = 0, avisoPend = false;
  function notificar() {
    if (!vivo || avisoPend || sujeira === entregue) return;
    avisoPend = true;
    try { G.__aviso(); } catch (e) { avisoPend = false; }
  }
  G.__vivo = function () {
    if (vivo) return;
    var todos = fila.concat(reserva), real = Date.now();
    fila = []; reserva = [];
    vivo = true; proximoDue = Infinity;
    for (var i = 0; i < todos.length; i++) {
      var t = todos[i]; t.vezes = 0;
      t.due = real + Math.max(16, t.due - agora);
      fila.push(t);
    }
    entregue = sujeira;
    rearmar();
  };
  function rearmar() {
    var m = Infinity;
    for (var i = 0; i < fila.length; i++) if (fila[i].due < m) m = fila[i].due;
    proximoDue = m;
    if (m !== Infinity) acordar(m - Date.now());
  }
  G.__tick = function () {
    if (!vivo || pausado) return;
    var inicio = Date.now(), n = 0;
    for (;;) {
      var agoraR = Date.now(), k = -1;
      for (var i = 0; i < fila.length; i++) if (fila[i].due <= agoraR && (k < 0 || fila[i].due < fila[k].due)) k = i;
      if (k < 0 || n >= 100 || agoraR - inicio > 50) break;
      var t = fila.splice(k, 1)[0]; n++;
      if (t.repete) { t.due = Date.now() + t.ms; fila.push(t); }
      try { t.fn.apply(G, t.args); } catch (e) { erro('temporizador: ' + e); }
    }
    rearmar();
    notificar();
  };
  G.__pausar = function () { if (vivo && !pausado) { pausado = true; pausadoEm = Date.now(); } };
  G.__retomar = function () {
    if (!pausado) return;
    pausado = false;
    var d = Date.now() - pausadoEm;
    for (var i = 0; i < fila.length; i++) fila[i].due += d;
    rearmar();
  };

  // ---------- rede ----------
  var pedidos = {}, proxPedido = 1, pendentes = 0;
  function pedir(url, metodo, cab, corpo, ok, falha, guardar) {
    var id = proxPedido++; pendentes++;
    pedidos[id] = { ok: ok, falha: falha };
    if (bloqueado(url)) { estat.bloqueados++; agendar(function () { G.__resposta(id, 204, '{}', '', ''); }, 0, [], false); return id; }
    try { G.__pedir(id, String(url), String(metodo || 'GET'), JSON.stringify(cab || {}), corpo == null ? '' : String(corpo), !!guardar); }
    catch (e) { delete pedidos[id]; pendentes--; falha(e); }
    return id;
  }
  G.__resposta = function (id, status, cabJson, texto, msgErro) {
    var p = pedidos[id]; if (!p) return;
    delete pedidos[id]; pendentes--;
    try {
      if (msgErro) p.falha(new TypeError(msgErro));
      else p.ok({ status: status, cab: JSON.parse(cabJson || '{}'), texto: texto });
    } catch (e) { erro('rede: ' + e); }
    avancar();
    pedirTick();
  };
  function Headers(init) {
    this.__m = {};
    if (init) { if (init instanceof Headers) init.forEach(function (v, k) { this.set(k, v); }, this);
      else if (Array.isArray(init)) init.forEach(function (p) { this.append(p[0], p[1]); }, this);
      else for (var k in init) this.set(k, init[k]); }
  }
  Headers.prototype.get = function (k) { var v = this.__m[String(k).toLowerCase()]; return v === undefined ? null : v; };
  Headers.prototype.set = function (k, v) { this.__m[String(k).toLowerCase()] = String(v); };
  Headers.prototype.append = function (k, v) { k = String(k).toLowerCase(); this.__m[k] = k in this.__m ? this.__m[k] + ', ' + v : String(v); };
  Headers.prototype.has = function (k) { return String(k).toLowerCase() in this.__m; };
  Headers.prototype['delete'] = function (k) { delete this.__m[String(k).toLowerCase()]; };
  Headers.prototype.forEach = function (fn, t) { for (var k in this.__m) fn.call(t, this.__m[k], k, this); };
  Headers.prototype.entries = function () { var m = this.__m; return Object.keys(m).map(function (k) { return [k, m[k]]; })[Symbol.iterator](); };
  Headers.prototype.keys = function () { return Object.keys(this.__m)[Symbol.iterator](); };
  Headers.prototype.values = function () { var m = this.__m; return Object.keys(m).map(function (k) { return m[k]; })[Symbol.iterator](); };
  Headers.prototype[Symbol.iterator] = Headers.prototype.entries;
  function corpoTexto(c) {
    if (c == null) return '';
    if (typeof c === 'string') return c;
    if (c instanceof URLSearchParams) return c.toString();
    if (c instanceof ArrayBuffer || ArrayBuffer.isView(c)) return new TextDecoder().decode(c);
    if (c.__texto !== undefined) return c.__texto;
    return String(c);
  }
  function Response(corpo, init) {
    init = init || {};
    this.__texto = corpo == null ? '' : corpoTexto(corpo); this.status = init.status === undefined ? 200 : init.status;
    this.ok = this.status >= 200 && this.status < 300; this.statusText = init.statusText || '';
    this.headers = new Headers(init.headers); this.url = init.url || ''; this.type = 'basic'; this.redirected = false;
    this.bodyUsed = false; this.body = null;
  }
  Response.prototype.text = function () { this.bodyUsed = true; return Promise.resolve(this.__texto); };
  Response.prototype.json = function () { var t = this.__texto; this.bodyUsed = true; return new Promise(function (ok, no) { try { ok(JSON.parse(t)); } catch (e) { no(e); } }); };
  Response.prototype.arrayBuffer = function () { this.bodyUsed = true; return Promise.resolve(new TextEncoder().encode(this.__texto).buffer); };
  Response.prototype.blob = function () { return Promise.resolve(new Blob([this.__texto])); };
  Response.prototype.formData = function () { return Promise.reject(new Error('formData não suportado')); };
  Response.prototype.clone = function () { var r = new Response(this.__texto, { status: this.status, statusText: this.statusText, headers: this.headers, url: this.url }); return r; };
  Response.error = function () { var r = new Response('', { status: 0 }); r.type = 'error'; return r; };
  Response.json = function (d, i) { return new Response(JSON.stringify(d), i); };
  function Request(entrada, init) {
    init = init || {};
    var base = entrada instanceof Request ? entrada : null;
    this.url = base ? base.url : (resolver(String(entrada && entrada.href || entrada)) || String(entrada));
    this.method = String(init.method || (base && base.method) || 'GET').toUpperCase();
    this.headers = new Headers(init.headers || (base && base.headers));
    this.body = init.body !== undefined ? init.body : (base ? base.body : null);
    this.signal = init.signal || null; this.credentials = init.credentials || 'same-origin'; this.mode = init.mode || 'cors';
  }
  Request.prototype.clone = function () { return new Request(this); };
  Request.prototype.text = function () { return Promise.resolve(corpoTexto(this.body)); };
  Request.prototype.json = function () { return this.text().then(JSON.parse); };
  function Blob(partes, opts) { this.__texto = (partes || []).map(corpoTexto).join(''); this.type = (opts && opts.type) || ''; this.size = this.__texto.length; }
  Blob.prototype.text = function () { return Promise.resolve(this.__texto); };
  Blob.prototype.arrayBuffer = function () { return Promise.resolve(new TextEncoder().encode(this.__texto).buffer); };
  Blob.prototype.slice = function (a, b) { return new Blob([this.__texto.slice(a, b)], { type: this.type }); };
  function FormData() { this.__l = []; }
  FormData.prototype.append = function (k, v) { this.__l.push([String(k), v]); };
  FormData.prototype.set = function (k, v) { this['delete'](k); this.append(k, v); };
  FormData.prototype.get = function (k) { for (var i = 0; i < this.__l.length; i++) if (this.__l[i][0] === k) return this.__l[i][1]; return null; };
  FormData.prototype.has = function (k) { return this.get(k) !== null; };
  FormData.prototype['delete'] = function (k) { this.__l = this.__l.filter(function (p) { return p[0] !== k; }); };
  FormData.prototype.entries = function () { return this.__l.slice()[Symbol.iterator](); };
  function AbortSignal() { this.aborted = false; this.reason = undefined; this.onabort = null; this.__ev = null; }
  AbortSignal.prototype.addEventListener = AlvoEventos.addEventListener; AbortSignal.prototype.removeEventListener = AlvoEventos.removeEventListener;
  AbortSignal.prototype.throwIfAborted = function () { if (this.aborted) throw this.reason; };
  AbortSignal.abort = function (r) { var s = new AbortSignal(); s.aborted = true; s.reason = r || new Error('AbortError'); return s; };
  AbortSignal.timeout = function (ms) { var c = new AbortController(); G.setTimeout(function () { c.abort(new Error('TimeoutError')); }, ms); return c.signal; };
  function AbortController() { this.signal = new AbortSignal(); }
  AbortController.prototype.abort = function (r) {
    var s = this.signal; if (s.aborted) return;
    s.aborted = true; s.reason = r === undefined ? Object.assign(new Error('The operation was aborted.'), { name: 'AbortError' }) : r;
    var ev = new Event('abort'); ev.target = s; disparar(s, ev);
  };
  G.fetch = function (entrada, init) {
    return new Promise(function (ok, no) {
      var req;
      try { req = new Request(entrada, init); } catch (e) { no(e); return; }
      if (req.signal && req.signal.aborted) { no(req.signal.reason); return; }
      var cab = {}; req.headers.forEach(function (v, k) { cab[k] = v; });
      var id = pedir(req.url, req.method, cab, req.method === 'GET' || req.method === 'HEAD' ? '' : corpoTexto(req.body), function (r) {
        var resp = new Response(r.texto, { status: r.status, headers: r.cab, url: req.url });
        ok(resp);
      }, function (e) { no(e); });
      if (req.signal) req.signal.addEventListener('abort', function () { if (pedidos[id]) { delete pedidos[id]; pendentes--; } no(req.signal.reason); });
    });
  };
  function XHR() { this.readyState = 0; this.status = 0; this.statusText = ''; this.responseText = ''; this.response = null; this.responseType = ''; this.responseURL = '';
    this.timeout = 0; this.withCredentials = false; this.upload = { addEventListener: nada }; this.__cab = {}; this.__rcab = {}; this.__ev = null; }
  XHR.prototype = Object.create(Node.prototype);
  XHR.prototype.addEventListener = AlvoEventos.addEventListener; XHR.prototype.removeEventListener = AlvoEventos.removeEventListener;
  XHR.prototype.dispatchEvent = function (ev) { ev.target = this; disparar(this, ev); return true; };
  XHR.prototype.open = function (m, u) { this.__m = m; this.__u = resolver(String(u)) || String(u); this.readyState = 1; this.__estado(); };
  XHR.prototype.setRequestHeader = function (k, v) { this.__cab[k] = v; };
  XHR.prototype.getResponseHeader = function (k) { var v = this.__rcab[String(k).toLowerCase()]; return v === undefined ? null : v; };
  XHR.prototype.getAllResponseHeaders = function () { var o = ''; for (var k in this.__rcab) o += k + ': ' + this.__rcab[k] + '\r\n'; return o; };
  XHR.prototype.overrideMimeType = nada;
  XHR.prototype.__estado = function () { var ev = new Event('readystatechange'); ev.target = this; disparar(this, ev); };
  XHR.prototype.__evt = function (t) { var ev = new Event(t); ev.target = this; disparar(this, ev); };
  XHR.prototype.send = function (corpo) {
    var self = this;
    pedir(this.__u, this.__m || 'GET', this.__cab, corpo == null ? '' : corpoTexto(corpo), function (r) {
      self.status = r.status; self.statusText = r.status === 200 ? 'OK' : ''; self.__rcab = {}; for (var k in r.cab) self.__rcab[k.toLowerCase()] = r.cab[k];
      self.responseURL = self.__u; self.responseText = r.texto;
      if (self.responseType === 'json') { try { self.response = JSON.parse(r.texto); } catch (e) { self.response = null; } }
      else if (self.responseType === 'arraybuffer') self.response = new TextEncoder().encode(r.texto).buffer;
      else self.response = r.texto;
      self.readyState = 4; self.__estado(); self.__evt('load'); self.__evt('loadend');
    }, function (e) { self.readyState = 4; self.__estado(); self.__evt('error'); self.__evt('loadend'); });
  };
  XHR.prototype.abort = function () { this.readyState = 0; this.__evt('abort'); };
  XHR.DONE = 4; XHR.UNSENT = 0; XHR.OPENED = 1; XHR.HEADERS_RECEIVED = 2; XHR.LOADING = 3;

  // ---------- scripts ----------
  var fase = { pronto: false };
  // ---------- módulos ES ----------
  // O JavaScriptCore não expõe carregador de módulos. Então o módulo é reescrito, por tokens (strings, templates,
  // regex e comentários não confundem a leitura), numa função comum: import vira leitura do módulo já executado,
  // export vira um getter (ligação viva), import() vira uma chamada ao carregador e import.meta vira um objeto.
  var PALAVRAS_REGEX = { 'return': 1, 'typeof': 1, 'instanceof': 1, 'in': 1, 'of': 1, 'new': 1, 'delete': 1, 'void': 1, 'throw': 1, 'case': 1, 'do': 1, 'else': 1, 'yield': 1, 'await': 1 };
  function ehIdent(c) { return (c >= 97 && c <= 122) || (c >= 65 && c <= 90) || (c >= 48 && c <= 57) || c === 95 || c === 36 || c > 127; }
  function regexPermitido(prev) {
    if (prev === '' ) return true;
    if (prev === ')' || prev === ']' || prev === '}' || prev === 'num' || prev === 'str') return false;
    if (prev.length === 1 && !ehIdent(prev.charCodeAt(0))) return true;
    return !!PALAVRAS_REGEX[prev];
  }
  function pularString(src, i, q) {
    for (i++; i < src.length; i++) { var c = src.charCodeAt(i); if (c === 92) i++; else if (c === q || c === 10) return i + 1; }
    return src.length;
  }
  function pularRegex(src, i) {
    var dentro = false;
    for (i++; i < src.length; i++) {
      var c = src.charCodeAt(i);
      if (c === 92) i++;
      else if (c === 10) return i;
      else if (c === 91) dentro = true;
      else if (c === 93) dentro = false;
      else if (c === 47 && !dentro) { i++; while (i < src.length && ehIdent(src.charCodeAt(i))) i++; return i; }
    }
    return src.length;
  }
  // devolve o índice logo depois do '}' que fecha o "${" aberto antes de i
  function pularCodigoAte(src, i) {
    var prof = 0, prev = '';
    while (i < src.length) {
      var c = src.charCodeAt(i);
      if (c <= 32) { i++; continue; }
      if (c === 47) {
        var d = src.charCodeAt(i + 1);
        if (d === 47) { var f = src.indexOf('\n', i); i = f < 0 ? src.length : f; continue; }
        if (d === 42) { var g = src.indexOf('*/', i + 2); i = g < 0 ? src.length : g + 2; continue; }
        if (regexPermitido(prev)) { i = pularRegex(src, i); prev = 'num'; continue; }
        i++; prev = '/'; continue;
      }
      if (c === 39 || c === 34) { i = pularString(src, i, c); prev = 'str'; continue; }
      if (c === 96) { i = pularTemplate(src, i); prev = 'str'; continue; }
      if (c === 123) { prof++; i++; prev = '{'; continue; }
      if (c === 125) { if (prof === 0) return i + 1; prof--; i++; prev = '}'; continue; }
      if (ehIdent(c)) { var j = i; while (j < src.length && ehIdent(src.charCodeAt(j))) j++; var w = src.slice(i, j); prev = c >= 48 && c <= 57 ? 'num' : w; i = j; continue; }
      prev = src.charAt(i); i++;
    }
    return i;
  }
  function pularTemplate(src, i) {
    for (i++; i < src.length; i++) {
      var c = src.charCodeAt(i);
      if (c === 92) i++;
      else if (c === 96) return i + 1;
      else if (c === 36 && src.charCodeAt(i + 1) === 123) i = pularCodigoAte(src, i + 2) - 1;
    }
    return src.length;
  }
  var RE_IMP_EFEITO = /import\s*(['"])((?:\\.|(?!\1)[^\\\n])*)\1[ \t]*;?/y;
  var RE_IMP = /import\s*([\s\S]*?)\s*from\s*(['"])((?:\\.|(?!\2)[^\\\n])*)\2[ \t]*;?/y;
  var RE_EXP_LISTA = /export\s*\{([\s\S]*?)\}\s*(?:from\s*(['"])((?:\\.|(?!\2)[^\\\n])*)\2)?[ \t]*;?/y;
  var RE_EXP_ESTRELA = /export\s*\*\s*(?:as\s+([\w$]+)\s*)?from\s*(['"])((?:\\.|(?!\2)[^\\\n])*)\2[ \t]*;?/y;
  var RE_EXP_PADRAO = /export\s+default\s+/y;
  var RE_DECL_FN = /(?:async\s+function\b\s*\*?\s*|function\b\s*\*?\s*|class\b\s*)([A-Za-z_$][\w$]*)?/y;
  var RE_EXP_DECL = /export\s+(?=(?:async\s+function|function|class|const|let|var)\b)/y;
  function partesTopo(t) {
    var r = [], prof = 0, ini = 0;
    for (var i = 0; i < t.length; i++) {
      var c = t.charCodeAt(i);
      if (c === 39 || c === 34) { i = pularString(t, i, c) - 1; continue; }
      if (c === 123 || c === 91 || c === 40) prof++; else if (c === 125 || c === 93 || c === 41) prof--;
      else if (c === 44 && prof === 0) { r.push(t.slice(ini, i)); ini = i + 1; }
    }
    r.push(t.slice(ini)); return r;
  }
  function semPadrao(e) {
    var prof = 0;
    for (var i = 0; i < e.length; i++) { var c = e.charCodeAt(i); if (c === 123 || c === 91 || c === 40) prof++; else if (c === 125 || c === 93 || c === 41) prof--; else if (c === 61 && prof === 0) return e.slice(0, i); }
    return e;
  }
  function nomesPadrao(p, out) {
    p = p.trim();
    var a = p.charAt(0);
    if (a === '{' || a === '[') {
      partesTopo(p.slice(1, -1)).forEach(function (e) {
        e = e.trim(); if (!e) return;
        if (e.indexOf('...') === 0) { nomesPadrao(semPadrao(e.slice(3)), out); return; }
        if (a === '{') { var prof = 0, dp = -1; for (var i = 0; i < e.length; i++) { var c = e.charCodeAt(i); if (c === 123 || c === 91 || c === 40) prof++; else if (c === 125 || c === 93 || c === 41) prof--; else if (c === 58 && prof === 0) { dp = i; break; } if (c === 61 && prof === 0) break; } if (dp >= 0) { nomesPadrao(semPadrao(e.slice(dp + 1)), out); return; } }
        nomesPadrao(semPadrao(e), out);
      });
    } else { var m = /^[\w$]+/.exec(p); if (m) out.push(m[0]); }
  }
  // Depois de "export const|let|var": nomes declarados (inclui desestruturação e vários declaradores).
  function nomesDeclarados(src, i) {
    var nomes = [];
    for (;;) {
      while (i < src.length && src.charCodeAt(i) <= 32) i++;
      var c = src.charAt(i);
      if (c === '{' || c === '[') {
        var ini = i, prof = 0;
        for (; i < src.length; i++) { var k = src.charCodeAt(i); if (k === 39 || k === 34) { i = pularString(src, i, k) - 1; continue; } if (k === 96) { i = pularTemplate(src, i) - 1; continue; } if (k === 123 || k === 91 || k === 40) prof++; else if (k === 125 || k === 93 || k === 41) { prof--; if (prof === 0) { i++; break; } } }
        nomesPadrao(src.slice(ini, i), nomes);
      } else {
        var m = /[\w$]+/y; m.lastIndex = i; var r = m.exec(src); if (!r) return nomes; nomes.push(r[0]); i += r[0].length;
      }
      // pula o inicializador até a vírgula que separa declaradores (ou o fim da declaração)
      var prof2 = 0, prev = '';
      for (; i < src.length; ) {
        var d = src.charCodeAt(i);
        if (d === 39 || d === 34) { i = pularString(src, i, d); prev = 'str'; continue; }
        if (d === 96) { i = pularTemplate(src, i); prev = 'str'; continue; }
        if (d === 47) { var e2 = src.charCodeAt(i + 1); if (e2 === 47) { var f = src.indexOf('\n', i); i = f < 0 ? src.length : f; continue; } if (e2 === 42) { var g = src.indexOf('*/', i + 2); i = g < 0 ? src.length : g + 2; continue; } if (regexPermitido(prev)) { i = pularRegex(src, i); prev = 'num'; continue; } }
        if (d === 123 || d === 91 || d === 40) { prof2++; prev = src.charAt(i); i++; continue; }
        if (d === 125 || d === 93 || d === 41) { prof2--; if (prof2 < 0) return nomes; prev = src.charAt(i); i++; continue; }
        if (prof2 === 0 && d === 59) return nomes;
        if (prof2 === 0 && d === 44) { i++; break; }
        if (prof2 === 0 && d === 10) {
          var q = i + 1; while (q < src.length && (src.charCodeAt(q) === 32 || src.charCodeAt(q) === 9 || src.charCodeAt(q) === 13 || src.charCodeAt(q) === 10)) q++;
          var nx = src.charAt(q), terminaExpr = prev === 'str' || prev === 'num' || prev === ')' || prev === ']' || prev === '}' || (prev !== '' && ehIdent(prev.charCodeAt(0)));
          if (terminaExpr && (nx === '' || ehIdent(nx.charCodeAt(0)) || nx === '}')) return nomes;
        }
        if (d <= 32) { i++; continue; }
        if (ehIdent(d)) { var j = i; while (j < src.length && ehIdent(src.charCodeAt(j))) j++; var w = src.slice(i, j); prev = d >= 48 && d <= 57 ? 'num' : w; i = j; continue; }
        prev = src.charAt(i); i++;
      }
      if (i >= src.length) return nomes;
    }
  }
  function transformarModulo(src) {
    if (src.charCodeAt(0) === 35 && src.charCodeAt(1) === 33) src = '//' + src.slice(2);   // #! de arquivo executável
    var n = src.length, i = 0, ini = 0, prev = '', prof = 0;
    var out = [], specs = [], cabeca = [], getters = [], reexp = [], tla = false;
    function spec(s) { var k = specs.indexOf(s); if (k < 0) { specs.push(s); k = specs.length - 1; } return k; }
    function corta(de, ate, troca) { out.push(src.slice(ini, de)); if (troca) out.push(troca); ini = ate; }
    function usa(re, pos) { re.lastIndex = pos; return re.exec(src); }
    while (i < n) {
      var c = src.charCodeAt(i);
      if (c <= 32) { i++; continue; }
      if (c === 47) {
        var d = src.charCodeAt(i + 1);
        if (d === 47) { var f = src.indexOf('\n', i); i = f < 0 ? n : f; continue; }
        if (d === 42) { var g = src.indexOf('*/', i + 2); i = g < 0 ? n : g + 2; continue; }
        if (regexPermitido(prev)) { i = pularRegex(src, i); prev = 'num'; continue; }
        i++; prev = '/'; continue;
      }
      if (c === 39 || c === 34) { i = pularString(src, i, c); prev = 'str'; continue; }
      if (c === 96) { i = pularTemplate(src, i); prev = 'str'; continue; }
      if (c === 40 || c === 91 || c === 123) { prof++; prev = src.charAt(i); i++; continue; }
      if (c === 41 || c === 93 || c === 125) { prof--; prev = src.charAt(i); i++; continue; }
      if (ehIdent(c)) {
        var j = i; while (j < n && ehIdent(src.charCodeAt(j))) j++;
        var w = src.slice(i, j), antesPonto = prev === '.';
        if (w === 'await' && !antesPonto && prof === 0) tla = true;
        if (c >= 48 && c <= 57) { prev = 'num'; i = j; continue; }
        if (w === 'import' && !antesPonto) {
          var k2 = j; while (k2 < n && src.charCodeAt(k2) <= 32) k2++;
          var nx = src.charAt(k2);
          if (nx === '(') { corta(i, j, '__import'); i = j; prev = 'import'; continue; }
          if (nx === '.') { var mm = usa(/\.\s*meta\b/y, k2); if (mm) { corta(i, k2 + mm[0].length, '__meta'); i = k2 + mm[0].length; prev = 'meta'; continue; } }
          if (prof === 0) {
            var m1 = usa(RE_IMP_EFEITO, i);
            if (m1) { spec(m1[2]); corta(i, i + m1[0].length, ''); i = ini; prev = ';'; continue; }
            var m2 = usa(RE_IMP, i);
            if (m2) {
              var idx = spec(m2[3]), cl = m2[1].trim(), br = cl.indexOf('{');
              var pre = (br >= 0 ? cl.slice(0, br) : cl).replace(/,\s*$/, '').trim();
              var chaves = br >= 0 ? cl.slice(br + 1, cl.lastIndexOf('}')) : '';
              if (pre) pre.split(',').forEach(function (p) {
                p = p.trim(); if (!p) return;
                var ns = /^\*\s*as\s+([\w$]+)$/.exec(p);
                if (ns) cabeca.push('var ' + ns[1] + '=__imp[' + idx + '];'); else cabeca.push('var ' + p + '=__imp[' + idx + '].default;');
              });
              chaves.split(',').forEach(function (p) {
                p = p.trim(); if (!p) return;
                var q = /^([\w$]+|'[^']*'|"[^"]*")(?:\s+as\s+([\w$]+))?$/.exec(p); if (!q) return;
                var orig = q[1].charAt(0) === '"' || q[1].charAt(0) === "'" ? q[1].slice(1, -1) : q[1];
                cabeca.push('var ' + (q[2] || orig) + '=__imp[' + idx + '][' + JSON.stringify(orig) + '];');
              });
              corta(i, i + m2[0].length, ''); i = ini; prev = ';'; continue;
            }
          }
        }
        if (w === 'export' && !antesPonto && prof === 0) {
          var e1 = usa(RE_EXP_PADRAO, i);
          if (e1) {
            var df = usa(RE_DECL_FN, i + e1[0].length);
            if (df && df[1] && df[1] !== 'extends') { getters.push(['default', df[1]]); corta(i, i + e1[0].length, ''); }
            else { getters.push(['default', '__padrao']); corta(i, i + e1[0].length, 'var __padrao='); }
            i = i + e1[0].length; prev = ';'; continue;
          }
          var e2 = usa(RE_EXP_LISTA, i);
          if (e2) {
            var ik = e2[3] !== undefined ? spec(e2[3]) : -1;
            e2[1].split(',').forEach(function (p) {
              p = p.trim(); if (!p) return;
              var q = /^([\w$]+|'[^']*'|"[^"]*")(?:\s+as\s+([\w$]+|'[^']*'|"[^"]*"))?$/.exec(p); if (!q) return;
              var un = function (x) { return x.charAt(0) === '"' || x.charAt(0) === "'" ? x.slice(1, -1) : x; };
              var local = un(q[1]), expo = q[2] ? un(q[2]) : local;
              getters.push([expo, ik >= 0 ? '__imp[' + ik + '][' + JSON.stringify(local) + ']' : local]);
            });
            corta(i, i + e2[0].length, ''); i = ini; prev = ';'; continue;
          }
          var e3 = usa(RE_EXP_ESTRELA, i);
          if (e3) {
            var ie = spec(e3[3]);
            if (e3[1]) getters.push([e3[1], '__imp[' + ie + ']']); else reexp.push(ie);
            corta(i, i + e3[0].length, ''); i = ini; prev = ';'; continue;
          }
          var e4 = usa(RE_EXP_DECL, i);
          if (e4) {
            var pos = i + e4[0].length, kw = /(?:async\s+function|function|class|const|let|var)/y; kw.lastIndex = pos;
            var kwm = kw.exec(src), kwTxt = kwm[0];
            if (kwTxt === 'const' || kwTxt === 'let' || kwTxt === 'var') nomesDeclarados(src, pos + kwTxt.length).forEach(function (nm) { getters.push([nm, nm]); });
            else { var fm = usa(RE_DECL_FN, pos); if (fm && fm[1]) getters.push([fm[1], fm[1]]); }
            corta(i, i + e4[0].length, ''); i = i + e4[0].length; prev = ';'; continue;
          }
        }
        prev = w; i = j; continue;
      }
      prev = src.charAt(i); i++;
    }
    out.push(src.slice(ini));
    var topo = (tla ? '(async function' : '(function') + '(__exp,__imp,__meta,__import,__rex){"use strict";';
    getters.forEach(function (g) { topo += 'Object.defineProperty(__exp,' + JSON.stringify(g[0]) + ',{enumerable:true,configurable:true,get:function(){return ' + g[1] + '}});'; });
    reexp.forEach(function (k) { topo += '__rex(__exp,__imp[' + k + ']);'; });
    topo += cabeca.join('');
    return { codigo: topo + out.join('') + '\n})', specs: specs, tla: tla };
  }

  // ---------- carregador de módulos ----------
  // estado: 0 baixando, 1 pronto para executar, 2 executando, 3 executado, 4 com erro
  var modulos = Object.create(null), mapaImp = Object.create(null), adiados = [], proxInline = 0;
  function resolverModulo(spec, base) {
    spec = String(spec);
    var m = mapaImp[spec];
    if (m === undefined) {
      var ks = Object.keys(mapaImp);
      for (var i = 0; i < ks.length; i++) { var k = ks[i]; if (k.charAt(k.length - 1) === '/' && spec.indexOf(k) === 0) { m = mapaImp[k] + spec.slice(k.length); break; } }
    }
    if (m !== undefined) spec = m;
    else if (!/^(\.{0,2}\/|[a-z][a-z0-9+.-]*:)/i.test(spec)) return null;
    return resolver(spec, base);
  }
  function modulo(url, texto) {
    var r = modulos[url];
    if (r) return r;
    r = modulos[url] = { url: url, base: url, estado: 0, exports: {}, deps: [], fn: null, espera: [], erro: null };
    if (texto !== undefined) { r.base = pagina.href; preparar(r, texto); return r; }
    pedir(url, 'GET', { accept: '*/*' }, '', function (x) {
      if (x.status >= 200 && x.status < 300) preparar(r, x.texto); else falharModulo(r, new Error('HTTP ' + x.status + ' em ' + url));
    }, function () { falharModulo(r, new Error('falha de rede em ' + url)); });
    return r;
  }
  function acordarEspera(r) { var e = r.espera; r.espera = []; e.forEach(function (f) { f(); }); }
  function falharModulo(r, e) { r.estado = 4; r.erro = e; erro('módulo ' + r.url + ': ' + (e && e.message || e)); acordarEspera(r); }
  // Reescreve sintaxe que o JavaScriptCore do iOS 15 ainda não conhece (Safari 16.4): blocos "static { ... }" de classe e
  // regex com lookbehind (?<=...) / (?<!...), que passam a usar o motor de regex do app.
  // Cada bloco vira um campo estático que roda os mesmos comandos, na mesma ordem e com o mesmo `this`:
  //   static { corpo }   ->   static __nsb0=(()=>{ corpo })();
  // Só é chamada quando o script falhou ao ler, então scripts comuns não pagam nada.
  function modernizar(src) {
    if (!/static\s*\{/.test(src) && !/\(\?<[=!]/.test(src) && !/\/[dgimsuy]*v[dgimsuy]*(?![\w$])/.test(src)) return src;
    var n = src.length, i = 0, prev = '', prevIni = -1, antesPonto = false, pilha = [], ed = [], k = 0;
    while (i < n) {
      var c = src.charCodeAt(i);
      if (c <= 32) { i++; continue; }
      if (c === 47) {
        var d = src.charCodeAt(i + 1);
        if (d === 47) { var f = src.indexOf('\n', i); i = f < 0 ? n : f; continue; }
        if (d === 42) { var g = src.indexOf('*/', i + 2); i = g < 0 ? n : g + 2; continue; }
        if (regexPermitido(prev)) {
          var fimRx = pularRegex(src, i), lit = src.slice(i, fimRx);
          // Regex com lookbehind, que o iOS 15 não lê: vira uma chamada ao motor de regex do app (__rx).
          var fl = /[a-z]*$/.exec(lit)[0];
          if (/\(\?<[=!]/.test(lit)) {
            ed.push([i, fimRx, '__rx(' + JSON.stringify(lit.slice(1, lit.length - fl.length - 1)) + ',' + JSON.stringify(fl.replace('v', 'u')) + ')']);
          } else if (fl.indexOf('v') >= 0) {
            // Flag v (Safari 17): o RegExp global tenta a flag u no lugar.
            ed.push([i, fimRx, 'new RegExp(' + JSON.stringify(lit.slice(1, lit.length - fl.length - 1)) + ',' + JSON.stringify(fl) + ')']);
          }
          i = fimRx; prev = 'num'; continue;
        }
        i++; prev = '/'; continue;
      }
      if (c === 39 || c === 34) { i = pularString(src, i, c); prev = 'str'; continue; }
      if (c === 96) { i = pularTemplate(src, i); prev = 'str'; continue; }
      if (c === 123) { pilha.push(prev === 'static' && !antesPonto ? { ini: prevIni, abre: i } : null); prev = '{'; i++; continue; }
      if (c === 125) {
        var e = pilha.pop();
        if (e) { ed.push([e.ini, e.abre + 1, 'static __nsb' + (k++) + '=(()=>{']); ed.push([i, i + 1, '})();']); }
        prev = '}'; i++; continue;
      }
      if (ehIdent(c)) {
        var j = i; while (j < n && ehIdent(src.charCodeAt(j))) j++;
        antesPonto = prev === '.';
        prev = c >= 48 && c <= 57 ? 'num' : src.slice(i, j); prevIni = i; i = j; continue;
      }
      prev = src.charAt(i); i++;
    }
    if (!ed.length) return src;
    ed.sort(function (a, b) { return a[0] - b[0]; });
    var out = [], pos = 0;
    for (var q = 0; q < ed.length; q++) { out.push(src.slice(pos, ed[q][0]), ed[q][2]); pos = ed[q][1]; }
    out.push(src.slice(pos));
    return out.join('');
  }
  // Mensagens de "o script nem chegou a rodar": só nesses casos vale tentar de novo reescrito.
  function erroDeLeitura(m) { return /^(Unexpected|Expected|Unterminated|Invalid regular|Invalid escape|Missing|Cannot use)/i.test(String(m)); }
  function trechoDoErro(src, m) {
    var x = /:(\d+):(\d+)\)$/.exec(String(m));
    if (!x || !src) return '';
    var linha = src.split('\n')[+x[1] - 1] || '', c = +x[2];
    return ' | perto de: «' + linha.slice(Math.max(0, c - 50), c + 50) + '»';
  }
  function avaliarModulo(codigo, url) {
    try { return (0, eval)(codigo + '\n//# sourceURL=' + url); }
    catch (e) {
      if (!(e instanceof SyntaxError)) throw e;
      var novo = modernizar(codigo);
      if (novo === codigo) throw e;
      return (0, eval)(novo + '\n//# sourceURL=' + url);
    }
  }
  function preparar(r, texto) {
    try {
      var t = transformarModulo(texto);
      r.fn = avaliarModulo(t.codigo, r.url);
      r.tla = t.tla;
      r.deps = t.specs.map(function (sp) {
        var u = resolverModulo(sp, r.base);
        if (!u) throw new TypeError('Failed to resolve module specifier "' + sp + '"');
        return modulo(u);
      });
    } catch (e) { falharModulo(r, e); return; }
    r.estado = 1; acordarEspera(r);
  }
  // chama cb quando o módulo e todas as suas dependências (em qualquer profundidade) já estão baixadas e compiladas
  function quandoPronto(r, cb) {
    var vistos = Object.create(null), falta = 0, chamado = false;
    function fim() { if (!chamado && falta === 0) { chamado = true; cb(); } }
    function visita(m) {
      if (vistos[m.url]) return; vistos[m.url] = 1;
      if (m.estado === 0) { falta++; m.espera.push(function () { falta--; deps(m); fim(); }); return; }
      deps(m);
    }
    function deps(m) { for (var i = 0; i < m.deps.length; i++) visita(m.deps[i]); }
    visita(r); fim();
  }
  function reexportar(alvo, fonte) {
    Object.keys(fonte).forEach(function (k) {
      if (k !== 'default' && !(k in alvo)) Object.defineProperty(alvo, k, { enumerable: true, configurable: true, get: function () { return fonte[k]; } });
    });
  }
  // Devolve undefined quando roda de uma vez, ou uma Promise quando o módulo (ou uma dependência) tem await no topo.
  function executarModulo(r) {
    if (r.estado === 4) throw r.erro;
    if (r.estado >= 2) return r.promessa;
    r.estado = 2;
    var i = 0;
    function passo() {
      while (i < r.deps.length) {
        var p = executarModulo(r.deps[i++]);
        if (p && typeof p.then === 'function') return p.then(passo);
      }
      var imps = r.deps.map(function (d) { return d.exports; });
      var ret = r.fn.call(undefined, r.exports, imps, { url: r.url }, function (sp) { return importarDinamico(sp, r.base); }, reexportar);
      if (r.tla) return ret.then(function () { r.estado = 3; });
      r.estado = 3;
    }
    var pr;
    try { pr = passo(); } catch (e) { r.estado = 4; r.erro = e; throw e; }
    if (pr) {
      r.promessa = pr.then(null, function (e) { r.estado = 4; r.erro = e; throw e; });
      return r.promessa;
    }
  }
  function importarDinamico(spec, base) {
    return new Promise(function (res, rej) {
      var u = resolverModulo(spec, base);
      if (!u) { rej(new TypeError('Failed to resolve module specifier "' + spec + '"')); return; }
      var r = modulo(u);
      quandoPronto(r, function () {
        var p;
        try { p = executarModulo(r); } catch (e) { rej(e); return; }
        if (p) p.then(function () { res(r.exports); }, rej); else res(r.exports);
      });
    });
  }
  // Devolve true se ficou esperando (await no topo); nesse caso chama fim() quando terminar.
  function executarScriptModulo(a, fim) {
    var src = a.el.getAttribute('src');
    function ok() { estat.executados++; if (src) eventoCarga(a.el, 'load'); }
    function falha(e) { erro('módulo ' + a.r.url + ': ' + (e && e.message || e)); if (src) eventoCarga(a.el, 'error'); }
    var p;
    try { p = executarModulo(a.r); } catch (e) { falha(e); return false; }
    if (p) { p.then(function () { ok(); if (fim) fim(); }, function (e) { falha(e); if (fim) fim(); }); return true; }
    ok();
    return false;
  }
  var moduloEsperando = false;
  function agendarModulo(s) {
    var src = s.getAttribute('src'), r;
    if (src) { var url = resolver(src); if (!url) return; r = modulo(url); }
    else r = modulo('inline:' + (++proxInline), s.textContent);
    var a = { r: r, el: s, pronto: false, aguardando: false };
    if (doc.readyState === 'loading') { adiados.push(a); return; }
    quandoPronto(r, function () { executarScriptModulo(a); });   // inserido depois do carregamento: roda assim que o grafo chegar
  }
  // Módulos da página rodam depois de todos os scripts comuns e antes do DOMContentLoaded, na ordem do documento.
  // Devolve false enquanto ainda espera algum módulo chegar.
  function executarAdiados() {
    if (moduloEsperando) return false;
    while (adiados.length) {
      var a = adiados[0];
      if (!a.pronto) {
        if (!a.aguardando) {
          a.aguardando = true;
          var sinc = true;
          quandoPronto(a.r, function () { a.pronto = true; if (!sinc) avancar(); });
          sinc = false;
        }
        if (!a.pronto) return false;
      }
      adiados.shift();
      if (executarScriptModulo(a, function () { moduloEsperando = false; avancar(); })) { moduloEsperando = true; bombearTimers(); return false; }
    }
    return true;
  }
  var TIPOS_JS = { '': 1, 'text/javascript': 1, 'application/javascript': 1, 'text/ecmascript': 1, 'application/ecmascript': 1, 'text/jscript': 1 };
  var estat = { executados: 0, ignorados: 0, bloqueados: 0 };
  // Rastreadores e anúncios: não baixam nem rodam. Economiza rede, CPU e memória.
  var BLOQ = ['google-analytics.com', 'googletagmanager.com', 'googletagservices.com', 'googlesyndication.com', 'googleadservices.com', 'doubleclick.net', '2mdn.net',
    'connect.facebook.net', 'hotjar.com', 'clarity.ms', 'mixpanel.com', 'segment.com', 'segment.io', 'amplitude.com', 'fullstory.com', 'nr-data.net',
    'taboola.com', 'outbrain.com', 'criteo.com', 'criteo.net', 'scorecardresearch.com', 'quantserve.com', 'chartbeat.com', 'chartbeat.net', 'adnxs.com',
    'rubiconproject.com', 'pubmatic.com', 'openx.net', 'amazon-adsystem.com', 'moatads.com', 'adsrvr.org', 'bat.bing.com', 'ads-twitter.com',
    'analytics.tiktok.com', 'px.ads.linkedin.com', 'hs-analytics.net', 'adform.net', 'casalemedia.com', 'demdex.net', 'omtrdc.net', 'mc.yandex.ru'];
  function bloqueado(url) {
    if (!pagina.bloquear) return false;
    var m = /^[a-z]+:\/\/([^\/?#:@]+)/i.exec(String(url));
    if (!m) return false;
    var h = m[1].toLowerCase();
    for (var i = 0; i < BLOQ.length; i++) { var b = BLOQ[i]; if (h === b || h.length > b.length && h.slice(-b.length - 1) === '.' + b) return true; }
    return false;
  }
  // Scripts de página rodam como "Script", não como eval: let, const e class do topo ficam visíveis aos scripts
  // seguintes, como num navegador. O texto dos scripts externos nunca passa pelo heap do JavaScript.
  function rodarScript(url, r) {
    if (!r.nativo) { rodarCodigo(url, r.texto); return; }
    estat.executados++;
    var m = G.__avaliarGuardado(String(url));
    if (m && erroDeLeitura(m) && typeof G.__fonteGuardada === 'function') {
      // O script nem chegou a rodar: tenta de novo com a sintaxe nova reescrita (static { } de classe).
      var fonte = G.__fonteGuardada(String(url)), novo = fonte ? modernizar(fonte) : fonte;
      if (novo && novo !== fonte) m = G.__avaliar(String(url), novo);
      else if (fonte) m += trechoDoErro(fonte, m);
    }
    if (m) erro(m);
  }
  function rodarCodigo(origem, codigo) {
    estat.executados++;
    if (typeof G.__avaliar === 'function') {
      var texto = String(codigo), msg = G.__avaliar(String(origem), texto);
      if (msg && erroDeLeitura(msg)) {
        var novo = modernizar(texto);
        if (novo !== texto) msg = G.__avaliar(String(origem), novo); else msg += trechoDoErro(texto, msg);
      }
      if (msg) erro(msg);
      return;
    }
    try { (0, eval)(codigo + '\n//# sourceURL=' + origem); }
    catch (e) {
      var extra = '';
      if (e && e.line) {
        var c = e.column || 0, l = codigo.split('\n')[e.line - 1] || '';
        extra = ' [linha ' + e.line + ', coluna ' + c + ', o script tem ' + codigo.split('\n').length + ' linhas e ' + codigo.length + ' caracteres] trecho: ' + l.slice(Math.max(0, c - 70), c + 70);
      }
      erro(origem + ': ' + (e && e.message ? e.message : e) + extra);
    }
  }
  function ehModulo(s) { return (s.getAttribute('type') || '').toLowerCase().split(';')[0].trim() === 'module'; }
  function podeRodar(s) {
    var tipo = (s.getAttribute('type') || '').toLowerCase().split(';')[0].trim();
    if (!(tipo in TIPOS_JS) && tipo !== 'module') return false;
    if (s.hasAttribute('nomodule')) return false;
    var src = s.getAttribute('src');
    if (src && pagina.ignorar && pagina.ignorar.length) {
      for (var ig = 0; ig < pagina.ignorar.length; ig++) if (String(src).indexOf(pagina.ignorar[ig]) >= 0) { if (!s.__bq) { s.__bq = 1; estat.ignorados++; } return false; }
    }
    if (src && pagina.bloquear) { var u = resolver(src); if (u && bloqueado(u)) { if (!s.__bq) { s.__bq = 1; estat.bloqueados++; } return false; } }
    return true;
  }
  // Como o "preload scanner" dos navegadores: pede todos os scripts de uma vez, em paralelo.
  // A execução continua na ordem da página; só o download deixa de ser uma fila.
  function preCarregar() {
    var n = 0, pre = [];
    // 1ª passada: mapas de importação precisam existir antes de qualquer módulo ser resolvido
    (function visita(no) {
      for (var i = 0; i < no.childNodes.length; i++) {
        var f = no.childNodes[i];
        if (f.nodeType !== 1) continue;
        if (f.localName === 'script' && (f.getAttribute('type') || '').toLowerCase() === 'importmap') {
          try {
            var im = JSON.parse(f.textContent).imports || {};
            Object.keys(im).forEach(function (k) { var u = resolver(im[k]); if (u) mapaImp[k] = u; });
          } catch (e) { erro('importmap: ' + e); }
        }
        visita(f);
      }
    })(doc);
    (function visita(no) {
      for (var i = 0; i < no.childNodes.length && n < 64; i++) {
        var f = no.childNodes[i];
        if (f.nodeType !== 1) continue;
        if (f.localName === 'script' && f.__parser && podeRodar(f)) {
          var src = f.getAttribute('src');
          var u = src ? resolver(src) : null;
          if (u) { if (ehModulo(f)) modulo(u); else baixarScript(u); n++; }
        } else if (f.localName === 'link' && (f.getAttribute('rel') || '').toLowerCase() === 'modulepreload') {
          var h = f.getAttribute('href'), hu = h ? resolver(h) : null;
          if (hu) { modulo(hu); n++; }
        }
        visita(f);
      }
    })(doc);
  }
  var baixados = {};
  function baixarScript(url) {
    if (baixados[url]) return baixados[url];
    var r = baixados[url] = { pronto: false, texto: null, falhou: false, espera: [], nativo: false };
    var guardar = typeof G.__avaliarGuardado === 'function';
    pedir(url, 'GET', { accept: '*/*' }, '', function (x) {
      r.pronto = true; if (x.status >= 200 && x.status < 300) { r.texto = guardar ? null : x.texto; r.nativo = guardar; } else r.falhou = true;
      var e = r.espera; r.espera = []; e.forEach(function (f) { f(); });
    }, function () { r.pronto = true; r.falhou = true; var e = r.espera; r.espera = []; e.forEach(function (f) { f(); }); }, guardar);
    return r;
  }
  function eventoCarga(el, tipo) { var ev = new Event(tipo); ev.target = el; disparar(el, ev); }
  // script inserido depois da montagem (ex.: carregamento de pedaços do site)
  function acharScripts(raiz) {
    var r = [];
    if (raiz.localName === 'script') { r.push(raiz); return r; }
    (function visita(n) {
      for (var i = 0; i < n.childNodes.length; i++) {
        var f = n.childNodes[i];
        if (f.nodeType !== 1) continue;
        if (f.localName === 'script') r.push(f); else if (f.childNodes.length) visita(f);
      }
    })(raiz);
    return r;
  }
  function iniciarScripts(raiz) {
    if (raiz.nodeType === 1 && raiz.localName !== 'script' && !raiz.childNodes.length) return;
    var lista = acharScripts(raiz);
    lista.forEach(function (s) {
      if (s.__ran || s.__parser) return;
      s.__ran = true;
      if (!podeRodar(s)) { estat.ignorados++; return; }
      if (ehModulo(s)) { agendarModulo(s); return; }
      var src = s.getAttribute('src');
      if (src) {
        var url = resolver(src); if (!url) return;
        var r = baixarScript(url);
        var corre = function () {
          if (r.falhou) { eventoCarga(s, 'error'); return; }
          var ant = doc.currentScript; doc.currentScript = s; rodarScript(url, r); doc.currentScript = ant; eventoCarga(s, 'load');
        };
        r.pronto ? corre() : r.espera.push(corre);
      } else {
        var ant = doc.currentScript; doc.currentScript = s; rodarCodigo('inline-dinamico', s.textContent); doc.currentScript = ant;
      }
    });
  }
  doc.currentScript = null;
  var sequencia = { esperando: null, acabou: false };
  function proximoScript() {
    var achado = null;
    (function visita(n) {
      for (var i = 0; i < n.childNodes.length && !achado; i++) {
        var f = n.childNodes[i];
        if (f.nodeType !== 1) continue;
        if (f.localName === 'script' && !f.__ran && f.__parser) { achado = f; return; }
        visita(f);
      }
    })(doc);
    return achado;
  }
  function seguirSequencia() {
    for (;;) {
      var s = proximoScript();
      if (!s) { sequencia.acabou = true; return; }
      if (!podeRodar(s)) { s.__ran = true; estat.ignorados++; continue; }
      if (ehModulo(s)) { s.__ran = true; agendarModulo(s); continue; }
      var src = s.getAttribute('src');
      if (src) {
        var url = resolver(src);
        if (!url) { s.__ran = true; continue; }
        var r = baixarScript(url);
        if (!r.pronto) { sequencia.esperando = s; r.espera.push(avancar); return; }
        s.__ran = true;
        if (r.falhou) { eventoCarga(s, 'error'); continue; }
        doc.currentScript = s; rodarScript(url, r); doc.currentScript = null; eventoCarga(s, 'load');
      } else {
        s.__ran = true; doc.currentScript = s; rodarCodigo('inline', s.textContent); doc.currentScript = null;
      }
    }
  }
  var terminou = false;
  function avancar() {
    if (terminou) return;
    if (!sequencia.acabou) seguirSequencia();
    if (!sequencia.acabou) return;
    if (!executarAdiados()) return;
    if (doc.readyState === 'loading') {
      doc.readyState = 'interactive'; fase.pronto = true;
      var e1 = new Event('readystatechange'); e1.target = doc; disparar(doc, e1);
      var e2 = new Event('DOMContentLoaded', { bubbles: true }); e2.target = doc; doc.dispatchEvent(e2);
    }
    drenar();
    if (pendentes === 0 && doc.readyState !== 'complete') {
      doc.readyState = 'complete';
      var e3 = new Event('readystatechange'); e3.target = doc; disparar(doc, e3);
      var e4 = new Event('load'); e4.target = G; disparar(G, e4);
      drenar();
    }
    if (pendentes === 0 && fila.length === 0) { terminou = true; G.__fim(); }
  }

  // ---------- janela ----------
  var agente = pagina.agente;
  var loc = new URL(pagina.href);
  var localizacao = {
    get href() { return loc.href; }, set href(v) { G.__navegar && G.__navegar(String(v)); },
    get protocol() { return loc.protocol; }, get host() { return loc.host; }, get hostname() { return loc.hostname; }, get port() { return loc.port; },
    get pathname() { return loc.pathname; }, get search() { return loc.search; }, get hash() { return loc.hash; }, set hash(v) { loc.hash = v ? (String(v).charAt(0) === '#' ? v : '#' + v) : ''; },
    get origin() { return loc.origin; },
    assign: nada, replace: nada, reload: nada, toString: function () { return loc.href; }, ancestorOrigins: []
  };
  function armazenamento() {
    var d = {};
    return { getItem: function (k) { return Object.prototype.hasOwnProperty.call(d, k) ? d[k] : null; }, setItem: function (k, v) { d[k] = String(v); },
      removeItem: function (k) { delete d[k]; }, clear: function () { d = {}; }, key: function (i) { return Object.keys(d)[i] || null; },
      get length() { return Object.keys(d).length; } };
  }
  function proxyArmazenamento() {
    var a = armazenamento();
    return new Proxy(a, {
      get: function (t, k) { if (typeof k === 'symbol' || k in t) return t[k]; var v = t.getItem(k); return v === null ? undefined : v; },
      set: function (t, k, v) { t.setItem(k, v); return true; },
      deleteProperty: function (t, k) { t.removeItem(k); return true; }
    });
  }
  Object.keys(AlvoEventos).forEach(function (k) { G[k] = AlvoEventos[k].bind(G); });
  G.window = G; G.self = G; G.top = G; G.parent = G; G.frames = G; G.globalThis = G; G.document = doc; G.location = localizacao;
  doc.location = localizacao;
  G.navigator = { userAgent: agente, appVersion: agente.replace(/^Mozilla\//, ''), platform: pagina.plataforma, language: 'pt-BR', languages: ['pt-BR', 'pt', 'en'],
    onLine: true, maxTouchPoints: pagina.toque ? 5 : 0, cookieEnabled: true, vendor: 'Apple Computer, Inc.', hardwareConcurrency: 2, webdriver: false, product: 'Gecko',
    clipboard: { writeText: function () { return Promise.resolve(); }, readText: function () { return Promise.resolve(''); } },
    sendBeacon: function () { return true; }, serviceWorker: undefined, mediaDevices: undefined, permissions: { query: function () { return Promise.resolve({ state: 'denied' }); } },
    userAgentData: undefined, connection: { effectiveType: '4g', saveData: false } };
  G.localStorage = proxyArmazenamento(); G.sessionStorage = proxyArmazenamento();
  G.performance = { now: function () { return Date.now() - inicioMs; }, timeOrigin: inicioMs, mark: nada, measure: nada, getEntriesByType: function () { return []; }, getEntriesByName: function () { return []; }, clearMarks: nada, clearMeasures: nada,
    timing: { navigationStart: inicioMs }, memory: undefined };
  G.screen = { width: pagina.largura, height: pagina.altura, availWidth: pagina.largura, availHeight: pagina.altura, colorDepth: 24, pixelDepth: 24, orientation: { type: 'portrait-primary', angle: 0, addEventListener: nada } };
  G.innerWidth = pagina.largura; G.innerHeight = pagina.altura; G.outerWidth = pagina.largura; G.outerHeight = pagina.altura;
  G.devicePixelRatio = pagina.escala; G.scrollX = 0; G.scrollY = 0; G.pageXOffset = 0; G.pageYOffset = 0;
  G.scrollTo = nada; G.scroll = nada; G.scrollBy = nada; G.open = function () { return null; }; G.close = nada; G.focus = nada; G.blur = nada; G.print = nada;
  G.alert = nada; G.confirm = function () { return false; }; G.prompt = function () { return null; };
  G.postMessage = function (msg) { var ev = new Event('message'); ev.data = msg; ev.origin = loc.origin; ev.source = G; G.setTimeout(function () { disparar(G, ev); }, 0); };
  G.getSelection = function () { return { rangeCount: 0, removeAllRanges: nada, addRange: nada, toString: function () { return ''; } }; };
  G.getComputedStyle = function (el) {
    var s = el && el.style ? el.style : null;
    return new Proxy({}, { get: function (t, k) { if (k === 'getPropertyValue') return function (n) { return s ? s.getPropertyValue(n) : ''; };
      if (typeof k === 'symbol') return undefined; return s ? s[k] : ''; } });
  };
  G.matchMedia = function (q) {
    q = String(q);
    var escuro = pagina.escuro, m = false;
    if (/prefers-color-scheme:\s*dark/.test(q)) m = escuro; else if (/prefers-color-scheme:\s*light/.test(q)) m = !escuro;
    else if (/prefers-reduced-motion:\s*reduce/.test(q)) m = false;
    else { var mx = /max-width:\s*(\d+)px/.exec(q), mn = /min-width:\s*(\d+)px/.exec(q); m = true;
      if (mx && pagina.largura > +mx[1]) m = false; if (mn && pagina.largura < +mn[1]) m = false;
      if (!mx && !mn && !/hover:\s*none|pointer:\s*coarse/.test(q)) m = false; }
    return { matches: m, media: q, onchange: null, addListener: nada, removeListener: nada, addEventListener: nada, removeEventListener: nada, dispatchEvent: function () { return true; } };
  };
  G.history = { pushState: nada, replaceState: nada, back: nada, forward: nada, go: nada, state: null, length: 1, scrollRestoration: 'auto' };
  G.crypto = {
    getRandomValues: function (a) { for (var i = 0; i < a.length; i++) a[i] = Math.floor(Math.random() * 4294967296); return a; },
    randomUUID: function () { return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function (c) { var r = Math.random() * 16 | 0; return (c === 'x' ? r : (r & 3 | 8)).toString(16); }); },
    subtle: undefined };
  G.CSS = { supports: function () { return false; }, escape: function (s) { return String(s).replace(/[^\w-]/g, '\\$&'); } };
  G.structuredClone = function (v) { return v === undefined ? v : JSON.parse(JSON.stringify(v)); };
  G.reportError = function (e) { erro(String(e)); };
  G.console = { log: nada, info: nada, debug: nada, warn: nada, trace: nada, table: nada, time: nada, timeEnd: nada, timeLog: nada, group: nada, groupEnd: nada, groupCollapsed: nada, dir: nada, assert: nada, count: nada, clear: nada,
    error: function () { erro('console.error: ' + Array.prototype.join.call(arguments, ' ')); } };
  G.Event = Event; G.CustomEvent = CustomEvent; G.MouseEvent = MouseEvent; G.PointerEvent = subEvento('PointerEvent'); G.KeyboardEvent = subEvento('KeyboardEvent');
  G.FocusEvent = subEvento('FocusEvent'); G.TouchEvent = subEvento('TouchEvent'); G.InputEvent = subEvento('InputEvent'); G.ErrorEvent = subEvento('ErrorEvent');
  G.MessageEvent = subEvento('MessageEvent'); G.PopStateEvent = subEvento('PopStateEvent'); G.HashChangeEvent = subEvento('HashChangeEvent'); G.StorageEvent = subEvento('StorageEvent');
  G.EventTarget = function () {}; Object.keys(AlvoEventos).forEach(function (k) { G.EventTarget.prototype[k] = AlvoEventos[k]; });
  G.Document = Document; G.URL = URL; G.URLSearchParams = URLSearchParams; G.TextEncoder = TextEncoder; G.TextDecoder = TextDecoder;
  G.Headers = Headers; G.Response = Response; G.Request = Request; G.Blob = Blob; G.FormData = FormData; G.File = Blob;
  G.AbortController = AbortController; G.AbortSignal = AbortSignal; G.XMLHttpRequest = XHR;
  G.Image = function (w, h) { var e = doc.createElement('img'); return e; };
  G.Option = function (t, v) { var e = doc.createElement('option'); if (t) e.textContent = t; if (v !== undefined) e.setAttribute('value', v); return e; };
  G.DOMParser = function () {}; G.DOMParser.prototype.parseFromString = function (h) {
    var d = new Document(); d.__mini = true; var f = fragmento(String(h), null); f.forEach(function (n) { d.__anexar(n); }); return d; };
  // Antes os quatro eram o mesmo objeto vazio, que nunca avisava ninguém. Site que espera algo ficar "visível" (carregamento
  // preguiçoso) ou reage a mudanças no DOM nunca andava.
  function MutationObserver(cb) {
    if (typeof cb !== 'function') throw new TypeError('MutationObserver callback is not a function');
    this.__cb = cb; this.__regs = []; this.__fila = []; this.__agendado = false;
  }
  MutationObserver.prototype.observe = function (alvo, opts) {
    opts = opts || {};
    var o = { childList: !!opts.childList, subtree: !!opts.subtree,
      attributes: opts.attributes !== undefined ? !!opts.attributes : !!(opts.attributeOldValue || opts.attributeFilter),
      characterData: opts.characterData !== undefined ? !!opts.characterData : !!opts.characterDataOldValue,
      attributeOldValue: !!opts.attributeOldValue, characterDataOldValue: !!opts.characterDataOldValue, attributeFilter: opts.attributeFilter || null };
    for (var i = 0; i < this.__regs.length; i++) if (this.__regs[i].alvo === alvo) { this.__regs[i].opts = o; return; }
    this.__regs.push({ alvo: alvo, opts: o });
    if (observadores.indexOf(this) < 0) observadores.push(this);
  };
  MutationObserver.prototype.disconnect = function () { this.__regs = []; this.__fila = []; var k = observadores.indexOf(this); if (k >= 0) observadores.splice(k, 1); };
  MutationObserver.prototype.takeRecords = function () { var f = this.__fila; this.__fila = []; return f; };
  G.MutationObserver = MutationObserver;

  // Não há layout dentro do JavaScript, então "visível" e "tamanho" são suposições: tudo conta como visível, com a largura da tela.
  function retangulo() { return { x: 0, y: 0, width: pagina.largura || 375, height: 0, top: 0, left: 0, right: pagina.largura || 375, bottom: 0 }; }
  function IntersectionObserver(cb, opts) {
    if (typeof cb !== 'function') throw new TypeError('IntersectionObserver callback is not a function');
    opts = opts || {};
    this.__cb = cb; this.root = opts.root || null; this.rootMargin = opts.rootMargin || '0px';
    this.thresholds = [].concat(opts.threshold === undefined ? [0] : opts.threshold);
    this.__alvos = []; this.__pend = []; this.__agendado = false;
  }
  IntersectionObserver.prototype.observe = function (el) {
    if (!el || this.__alvos.indexOf(el) >= 0) return;
    this.__alvos.push(el);
    // Trava contra "carregar mais" em laço: o aviso inicial vale no máximo 3 vezes por elemento, e não mais de uma por segundo.
    var agora = Date.now();
    if ((el.__io || 0) >= 3 || (el.__ioT && agora - el.__ioT < 1000)) return;
    el.__io = (el.__io || 0) + 1; el.__ioT = agora;
    this.__pend.push(el);
    if (!this.__agendado) {
      var self = this; this.__agendado = true;
      G.setTimeout(function () {
        self.__agendado = false;
        var itens = self.__pend.splice(0).filter(function (x) { return self.__alvos.indexOf(x) >= 0; });
        if (!itens.length) return;
        var tempo = Date.now() - inicioMs;
        try { self.__cb.call(self, itens.map(function (x) { return { target: x, isIntersecting: true, intersectionRatio: 1, boundingClientRect: retangulo(), intersectionRect: retangulo(), rootBounds: retangulo(), time: tempo }; }), self); }
        catch (e) { erro('IntersectionObserver: ' + e); }
      }, 0);
    }
  };
  IntersectionObserver.prototype.unobserve = function (el) { var i = this.__alvos.indexOf(el); if (i >= 0) this.__alvos.splice(i, 1); };
  IntersectionObserver.prototype.disconnect = function () { this.__alvos = []; this.__pend = []; };
  IntersectionObserver.prototype.takeRecords = function () { return []; };
  G.IntersectionObserver = IntersectionObserver;

  function ResizeObserver(cb) {
    if (typeof cb !== 'function') throw new TypeError('ResizeObserver callback is not a function');
    this.__cb = cb; this.__alvos = [];
  }
  ResizeObserver.prototype.observe = function (el) {
    if (!el || this.__alvos.indexOf(el) >= 0) return;
    this.__alvos.push(el);
    var self = this;
    G.setTimeout(function () {
      if (self.__alvos.indexOf(el) < 0) return;
      var larg = pagina.largura || 375, caixa = [{ inlineSize: larg, blockSize: 0 }];
      try { self.__cb.call(self, [{ target: el, contentRect: retangulo(), borderBoxSize: caixa, contentBoxSize: caixa, devicePixelContentBoxSize: caixa }], self); }
      catch (e) { erro('ResizeObserver: ' + e); }
    }, 0);
  };
  ResizeObserver.prototype.unobserve = function (el) { var i = this.__alvos.indexOf(el); if (i >= 0) this.__alvos.splice(i, 1); };
  ResizeObserver.prototype.disconnect = function () { this.__alvos = []; };
  G.ResizeObserver = ResizeObserver;

  function PerformanceObserver(cb) { this.__cb = cb; }
  PerformanceObserver.prototype.observe = nada; PerformanceObserver.prototype.disconnect = nada; PerformanceObserver.prototype.takeRecords = function () { return []; };
  PerformanceObserver.supportedEntryTypes = ['mark', 'measure', 'navigation', 'resource'];
  G.PerformanceObserver = PerformanceObserver;

  // <template>: o conteúdo fica num fragmento à parte. Sites como o GitHub fazem template.content.appendChild(...).
  Object.defineProperty(Element.prototype, 'content', {
    configurable: true,
    get: function () {
      if (this.localName !== 'template') return undefined;
      if (!this.__conteudo || this.__conteudoN !== this.childNodes.length || this.__conteudo1 !== this.childNodes[0]) {
        var f = doc.createDocumentFragment();
        for (var i = 0; i < this.childNodes.length; i++) f.appendChild(this.childNodes[i].cloneNode(true));
        this.__conteudo = f; this.__conteudoN = this.childNodes.length; this.__conteudo1 = this.childNodes[0];
      }
      return this.__conteudo;
    }
  });
  G.WebSocket = function () { throw new Error('WebSocket não suportado'); };
  G.EventSource = G.WebSocket; G.Worker = G.WebSocket; G.indexedDB = undefined; G.caches = undefined;
  G.DOMException = function (m, n) { this.message = m; this.name = n || 'Error'; };
  G.CSSStyleSheet = function () { this.cssRules = []; this.insertRule = nada; this.replaceSync = nada; };
  G.visualViewport = { width: pagina.largura, height: pagina.altura, scale: 1, addEventListener: nada, removeEventListener: nada };
  G.ontouchstart = null;

  // ---------- entrada e saída ----------
  G.__sujar = function () { sujeira++; };
  G.__iniciar = function (arvoreJson) {
    var json = JSON.parse(arvoreJson);
    montarDocumento(json);
    preCarregar();
    avancar();
  };
  G.__serializar = function () {
    var o = [];
    if (pagina.vivo) {
      var cob = (temOuvinteClique(doc) || temOuvinteClique(G) || (doc.documentElement ? temOuvinteClique(doc.documentElement) : false) || (doc.body ? temOuvinteClique(doc.body) : false)) ? 1 : 0;
      mapaClique = {}; marcando = true;
      try { serializar(doc, o, true, cob); } finally { marcando = false; }
    } else serializar(doc, o, true);
    return o.join('');
  };
  // Modo vivo: devolve o HTML novo (ou null se nada mudou desde a última entrega).
  G.__coletar = function () {
    avisoPend = false;
    if (sujeira === entregue) return null;
    entregue = sujeira;
    return G.__serializar();
  };
  function mouse(tipo, el) { var ev = new G.MouseEvent(tipo, { bubbles: true, cancelable: true, clientX: 0, clientY: 0, button: 0, view: G }); ev.target = el; return el.dispatchEvent(ev); }
  function ponteiro(tipo, el) { var ev = new G.PointerEvent(tipo, { bubbles: true, cancelable: true, pointerType: 'touch', isPrimary: true, clientX: 0, clientY: 0 }); ev.target = el; return el.dispatchEvent(ev); }
  function toque(tipo, el) {
    var pt = { identifier: 0, target: el, clientX: 0, clientY: 0, pageX: 0, pageY: 0, screenX: 0, screenY: 0 };
    var ev = new G.TouchEvent(tipo, { bubbles: true, cancelable: true, touches: tipo === 'touchend' ? [] : [pt], targetTouches: tipo === 'touchend' ? [] : [pt], changedTouches: [pt] });
    ev.target = el; return el.dispatchEvent(ev);
  }
  function marcarCheck(c, v) { c.checked = v; var i = new Event('input', { bubbles: true }); i.target = c; c.dispatchEvent(i); var h = new Event('change', { bubbles: true }); h.target = c; c.dispatchEvent(h); }
  // O que o navegador faz sozinho depois de um clique que ninguém cancelou. Devolve um endereço, se for o caso.
  function acaoPadrao(el, nivel) {
    for (var n = el; n && n.nodeType === 1; n = n.parentNode) {
      var t = n.localName;
      if (t === 'input') {
        var ty = (n.getAttribute('type') || '').toLowerCase();
        if (ty === 'checkbox') { marcarCheck(n, !n.checked); return ''; }
        if (ty === 'radio') {
          if (!n.checked) {
            var nome = n.getAttribute('name');
            if (nome) buscar(doc, 'input[type=radio]', false).forEach(function (r) { if (r !== n && r.getAttribute('name') === nome) r.checked = false; });
            marcarCheck(n, true);
          }
          return '';
        }
        return '';
      }
      if (t === 'label' && !nivel) {
        var f = n.getAttribute('for'), c = f ? doc.getElementById(f) : n.querySelector('input,select,textarea');
        if (c && c !== el) { var ev = new G.MouseEvent('click', { bubbles: true, cancelable: true }); ev.target = c; if (c.dispatchEvent(ev)) return acaoPadrao(c, 1); }
        return '';
      }
      if (t === 'summary' && n.parentNode && n.parentNode.localName === 'details') {
        var d = n.parentNode; d.hasAttribute('open') ? d.removeAttribute('open') : d.setAttribute('open', '');
        var tg = new Event('toggle'); tg.target = d; d.dispatchEvent(tg);
        return '';
      }
      if (t === 'a') return hrefDe(n);
    }
    return '';
  }
  // O toque do usuário vira a sequência de eventos de um toque de verdade.
  G.__tocar = function (id) {
    var el = mapaClique[id];
    if (!el || !el.isConnected) return JSON.stringify({ ok: 0 });
    var href = '';
    try {
      ponteiro('pointerdown', el);
      toque('touchstart', el);
      ponteiro('pointerup', el);
      var seguir = toque('touchend', el);
      if (seguir) { mouse('mousedown', el); mouse('mouseup', el); }
      if (seguir && mouse('click', el)) href = acaoPadrao(el, 0);
    } catch (e) { erro('toque: ' + e); }
    pedirTick();
    return JSON.stringify({ ok: 1, href: href });
  };
  G.__estatisticas = function () { return JSON.stringify({ executados: estat.executados, ignorados: estat.ignorados, bloqueados: estat.bloqueados, timers: execTimers, pendentes: pendentes, vivo: vivo }); };
})(this);
