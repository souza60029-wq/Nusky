// app/Nusky/AmbienteJSModerno.swift
import Foundation

/// Recursos do JavaScript moderno que o JavaScriptCore do iOS 15 não tem. Carrega ANTES do `AmbienteJS`.
///
/// Hoje: expressões regulares com lookbehind, `(?<=...)` e `(?<!...)`, que o Safari só entende a partir da 16.4.
/// Elas fazem o pacote inteiro de um site falhar ao ler (foi o que derrubou o claude.ai). O `RegExp` global passa
/// a recorrer a este motor quando o nativo recusa uma expressão com lookbehind, e o `AmbienteJS` reescreve as
/// regex literais dos scripts que falham ao ler para chamarem `__rx(...)`. As demais regex seguem nativas.
extension AmbienteJS {
    static let moderno = #"""
// Motor de expressões regulares com lookbehind, para o JavaScriptCore do iOS 15 (que só entende lookbehind a partir do Safari 16.4).
// Só é usado nas regex que o motor nativo recusa; as demais continuam nativas. Em vez de reimplementar tudo, vale o que a regex
// nativa já faz bem (classes \p{...}); o resto é um casador por retrocesso com continuações.
(function (G) {
  'use strict';
  var Nativo = G.RegExp;
  if (G.__rx) return;

  // ---------- leitura da expressão ----------
  var cacheAst = Object.create(null);
  function ler(src, flags) {
    var chave = flags + '/' + src;
    if (cacheAst[chave]) return cacheAst[chave];
    var i = 0, n = src.length, u = flags.indexOf('u') >= 0, nomes = [], total = 0, usaNomes = /\(\?<[^=!]/.test(src);
    function erro(m) { throw new SyntaxError('Invalid regular expression: ' + m); }
    // conta os grupos de captura antes, para saber se "\10" é referência ou escape
    (function () {
      var dentro = false;
      for (var k = 0; k < n; k++) {
        var c = src.charAt(k);
        if (c === '\\') { k++; continue; }
        if (dentro) { if (c === ']') dentro = false; continue; }
        if (c === '[') { dentro = true; continue; }
        if (c === '(') { if (src.charAt(k + 1) !== '?' || (src.charAt(k + 2) === '<' && src.charAt(k + 3) !== '=' && src.charAt(k + 3) !== '!')) total++; }
      }
    })();
    var cont = 0;
    function disj() {
      var alts = [alt()];
      while (src.charAt(i) === '|') { i++; alts.push(alt()); }
      return alts.length === 1 ? alts[0] : { t: 'alt', alts: alts };
    }
    function alt() {
      var itens = [];
      while (i < n && src.charAt(i) !== '|' && src.charAt(i) !== ')') itens.push(termo());
      return { t: 'seq', itens: itens };
    }
    function numero() { var s = ''; while (/\d/.test(src.charAt(i))) s += src.charAt(i++); return s === '' ? null : parseInt(s, 10); }
    function quantificador(nodo) {
      var c = src.charAt(i), min, max;
      if (c === '*') { min = 0; max = Infinity; i++; }
      else if (c === '+') { min = 1; max = Infinity; i++; }
      else if (c === '?') { min = 0; max = 1; i++; }
      else if (c === '{') {
        var m = /^\{(\d+)(,(\d*))?\}/.exec(src.slice(i));
        if (!m) return nodo;
        min = parseInt(m[1], 10); max = m[2] === undefined ? min : (m[3] === '' ? Infinity : parseInt(m[3], 10));
        if (max < min) erro('numbers out of order in {} quantifier');
        i += m[0].length;
      } else return nodo;
      var lento = false;
      if (src.charAt(i) === '?') { lento = true; i++; }
      return { t: 'rep', sub: nodo, min: min, max: max, lento: lento };
    }
    function pontoDeCodigo() {
      var c = src.charCodeAt(i);
      if (u && c >= 0xd800 && c <= 0xdbff && i + 1 < n) { var d = src.charCodeAt(i + 1); if (d >= 0xdc00 && d <= 0xdfff) { i += 2; return ((c - 0xd800) << 10) + (d - 0xdc00) + 0x10000; } }
      i++; return c;
    }
    function hex(len) { var s = src.substr(i, len); if (s.length === len && /^[0-9a-fA-F]+$/.test(s)) { i += len; return parseInt(s, 16); } return null; }
    // escape fora ou dentro de classe; devolve um nó de caractere, de classe ou de propriedade
    function escape(emClasse) {
      i++;   // a barra
      if (i >= n) erro('\\ at end of pattern');
      var c = src.charAt(i++);
      switch (c) {
        case 'd': case 'D': case 'w': case 'W': case 's': case 'S': return { t: 'esc', k: c };
        case 't': return { t: 'chr', c: 9 }; case 'n': return { t: 'chr', c: 10 }; case 'v': return { t: 'chr', c: 11 };
        case 'f': return { t: 'chr', c: 12 }; case 'r': return { t: 'chr', c: 13 };
        case 'b': return emClasse ? { t: 'chr', c: 8 } : { t: 'wb', neg: false };
        case 'B': if (!emClasse) return { t: 'wb', neg: true }; return { t: 'chr', c: 66 };
        case '0': if (!/\d/.test(src.charAt(i))) return { t: 'chr', c: 0 }; break;
        case 'c': { var l = src.charAt(i); if (/[A-Za-z]/.test(l)) { i++; return { t: 'chr', c: l.charCodeAt(0) % 32 }; } i--; return { t: 'chr', c: 92 }; }
        case 'x': { var h = hex(2); return { t: 'chr', c: h === null ? 120 : h }; }
        case 'u': {
          if (u && src.charAt(i) === '{') { var m = /^\{([0-9a-fA-F]+)\}/.exec(src.slice(i)); if (m) { i += m[0].length; return { t: 'chr', c: parseInt(m[1], 16) }; } }
          var h4 = hex(4);
          if (h4 === null) return { t: 'chr', c: 117 };
          if (u && h4 >= 0xd800 && h4 <= 0xdbff && src.substr(i, 2) === '\\u') { var save = i; i += 2; var lo = hex(4); if (lo !== null && lo >= 0xdc00 && lo <= 0xdfff) return { t: 'chr', c: ((h4 - 0xd800) << 10) + (lo - 0xdc00) + 0x10000 }; i = save; }
          return { t: 'chr', c: h4 };
        }
        case 'p': case 'P': if (u) { var mp = /^\{([^}]*)\}/.exec(src.slice(i)); if (!mp) erro('Invalid property name'); i += mp[0].length; return { t: 'prop', nome: mp[1], neg: c === 'P' }; } return { t: 'chr', c: c.charCodeAt(0) };
        case 'k': if (!emClasse && (usaNomes || u)) { var mk = /^<([^>]+)>/.exec(src.slice(i)); if (!mk) erro('Invalid named reference'); i += mk[0].length; return { t: 'back', nome: mk[1] }; } return { t: 'chr', c: 107 };
      }
      if (c >= '1' && c <= '9' && !emClasse) {
        var j = i - 1, s = c; while (/\d/.test(src.charAt(i))) s += src.charAt(i++);
        var num = parseInt(s, 10);
        if (num <= total) return { t: 'back', idx: num };
        // não é referência: vira escape octal/identidade
        i = j + 1; return { t: 'chr', c: c.charCodeAt(0) };
      }
      return { t: 'chr', c: c.charCodeAt(0) };
    }
    function classe() {
      i++;   // [
      var neg = false; if (src.charAt(i) === '^') { neg = true; i++; }
      var itens = [];
      while (i < n && src.charAt(i) !== ']') {
        var a = classeAtomo();
        if (src.charAt(i) === '-' && src.charAt(i + 1) !== ']' && i + 1 < n) {
          i++;
          var b = classeAtomo();
          if (a.t === 'chr' && b.t === 'chr') { if (a.c > b.c) erro('Range out of order in character class'); itens.push({ de: a.c, ate: b.c }); continue; }
          itens.push(a); itens.push({ de: 45, ate: 45 }); itens.push(b); continue;
        }
        itens.push(a);
      }
      if (i >= n) erro('Unterminated character class');
      i++;
      return { t: 'cls', neg: neg, itens: itens.map(function (x) { return x.t === 'chr' ? { de: x.c, ate: x.c } : x; }) };
    }
    function classeAtomo() { if (src.charAt(i) === '\\') return escape(true); return { t: 'chr', c: pontoDeCodigo() }; }
    function termo() {
      var c = src.charAt(i), nodo;
      if (c === '^') { i++; return { t: 'ini' }; }
      if (c === '$') { i++; return { t: 'fim' }; }
      if (c === '(') {
        var idx = 0, nome = null, tipo = 'ncg', neg = false;
        if (src.charAt(i + 1) === '?') {
          var d = src.charAt(i + 2);
          if (d === ':') { i += 3; tipo = 'ncg'; }
          else if (d === '=' || d === '!') { i += 3; tipo = 'la'; neg = d === '!'; }
          else if (d === '<' && (src.charAt(i + 3) === '=' || src.charAt(i + 3) === '!')) { neg = src.charAt(i + 3) === '!'; i += 4; tipo = 'lb'; }
          else if (d === '<') { var mn = /^\(\?<([^>]+)>/.exec(src.slice(i)); if (!mn) erro('Invalid capture group name'); nome = mn[1]; i += mn[0].length; idx = ++cont; tipo = 'grp'; nomes.push([nome, idx]); }
          else erro('Invalid group');
        } else { i++; idx = ++cont; tipo = 'grp'; }
        var sub = disj();
        if (src.charAt(i) !== ')') erro('Unterminated group');
        i++;
        nodo = { t: tipo, sub: sub, idx: idx, nome: nome, neg: neg };
        if (tipo === 'lb') return nodo;               // lookbehind não leva quantificador
        if (tipo === 'la' && !u) return quantificador(nodo);
        return quantificador(nodo);
      }
      if (c === ')') erro('Unmatched \')\'');
      if (c === '.') { i++; return quantificador({ t: 'any' }); }
      if (c === '[') return quantificador(classe());
      if (c === '\\') {
        var e = escape(false);
        return e.t === 'wb' ? e : quantificador(e);
      }
      if (c === '*' || c === '+' || c === '?') erro('Nothing to repeat');
      if (c === '{' && /^\{\d+(,\d*)?\}/.test(src.slice(i))) erro('Nothing to repeat');
      return quantificador({ t: 'chr', c: pontoDeCodigo() });
    }
    var ast = disj();
    if (i < n) erro('Unmatched \')\'');
    for (var q = 0; q < nomes.length; q++) for (var r = q + 1; r < nomes.length; r++) if (nomes[q][0] === nomes[r][0]) erro('Duplicate capture group name');
    return (cacheAst[chave] = { ast: ast, grupos: cont, nomes: nomes });
  }

  // ---------- caracteres ----------
  function digito(c) { return c >= 48 && c <= 57; }
  function palavra(c) { return digito(c) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c === 95; }
  function espaco(c) { return c === 32 || (c >= 9 && c <= 13) || c === 160 || c === 0x1680 || (c >= 0x2000 && c <= 0x200a) || c === 0x2028 || c === 0x2029 || c === 0x202f || c === 0x205f || c === 0x3000 || c === 0xfeff; }
  function quebra(c) { return c === 10 || c === 13 || c === 0x2028 || c === 0x2029; }
  var cachePropriedade = Object.create(null);
  function propriedade(nome, c) {
    var re = cachePropriedade[nome] || (cachePropriedade[nome] = new Nativo('^\\p{' + nome + '}$', 'u'));
    return re.test(String.fromCodePoint(c));
  }
  function canon(c) {
    var s = String.fromCodePoint(c), m = s.toUpperCase();
    if (m.length !== s.length) return c;
    var r = m.codePointAt(0);
    return (c >= 128 && r < 128) ? c : r;
  }
  function noEscape(k, c) {
    switch (k) {
      case 'd': return digito(c); case 'D': return !digito(c);
      case 'w': return palavra(c); case 'W': return !palavra(c);
      case 's': return espaco(c); case 'S': return !espaco(c);
    }
    return false;
  }
  function itemCasa(it, c) {
    if (it.de !== undefined) return c >= it.de && c <= it.ate;
    if (it.t === 'esc') return noEscape(it.k, c);
    if (it.t === 'prop') return propriedade(it.nome, c) !== it.neg;
    return false;
  }
  function classeCasa(nodo, c, ic) {
    var achou = false;
    for (var k = 0; k < nodo.itens.length && !achou; k++) achou = itemCasa(nodo.itens[k], c);
    if (!achou && ic) {
      var a = canon(c), b = String.fromCodePoint(c).toLowerCase();
      var bl = b.length === String.fromCodePoint(c).length ? b.codePointAt(0) : c;
      for (var k2 = 0; k2 < nodo.itens.length && !achou; k2++) achou = itemCasa(nodo.itens[k2], a) || itemCasa(nodo.itens[k2], bl);
    }
    return achou !== nodo.neg;
  }

  // ---------- compilação para funções casadoras ----------
  // Cada nó vira f(e, p, k): tenta casar em p e chama a continuação k(q). Devolve true ou false.
  var cacheComp = Object.create(null);
  function leitura(e, p) {
    var s = e.s;
    if (p >= s.length) return -1;
    var c = s.charCodeAt(p);
    if (e.u && c >= 0xd800 && c <= 0xdbff && p + 1 < s.length) { var d = s.charCodeAt(p + 1); if (d >= 0xdc00 && d <= 0xdfff) return ((c - 0xd800) << 10) + (d - 0xdc00) + 0x10000; }
    return c;
  }
  function tam(c) { return c > 0xffff ? 2 : 1; }
  function umaLetra(nodo) {
    // devolve t(e, c) -> bool para nós que casam exatamente um caractere
    switch (nodo.t) {
      case 'chr': return function (e, c) { return c === nodo.c || (e.ic && canon(c) === canon(nodo.c)); };
      case 'any': return function (e, c) { return e.dotAll || !quebra(c); };
      case 'cls': return function (e, c) { return classeCasa(nodo, c, e.ic); };
      case 'esc': return function (e, c) { return noEscape(nodo.k, c); };
      case 'prop': return function (e, c) { return propriedade(nodo.nome, c) !== nodo.neg; };
    }
    return null;
  }
  function eBorda(e, p) {
    var a = p > 0 && palavra(e.s.charCodeAt(p - 1)), b = p < e.s.length && palavra(e.s.charCodeAt(p));
    return a !== b;
  }
  function compilar(nodo) {
    var t = umaLetra(nodo);
    if (t) return function (e, p, k) { var c = leitura(e, p); return c >= 0 && t(e, c) ? k(p + tam(c)) : false; };
    switch (nodo.t) {
      case 'seq': {
        var fs = nodo.itens.map(compilar);
        if (fs.length === 0) return function (e, p, k) { return k(p); };
        if (fs.length === 1) return fs[0];
        return function (e, p, k) {
          function passo(idx, q) { return idx === fs.length ? k(q) : fs[idx](e, q, function (r) { return passo(idx + 1, r); }); }
          return passo(0, p);
        };
      }
      case 'alt': {
        var alts = nodo.alts.map(compilar);
        return function (e, p, k) { for (var a = 0; a < alts.length; a++) if (alts[a](e, p, k)) return true; return false; };
      }
      case 'ini': return function (e, p, k) { return (p === 0 || (e.m && quebra(e.s.charCodeAt(p - 1)))) ? k(p) : false; };
      case 'fim': return function (e, p, k) { return (p === e.s.length || (e.m && quebra(e.s.charCodeAt(p)))) ? k(p) : false; };
      case 'wb': return function (e, p, k) { return eBorda(e, p) !== nodo.neg ? k(p) : false; };
      case 'ncg': return compilar(nodo.sub);
      case 'grp': {
        var f = compilar(nodo.sub), idx = nodo.idx;
        return function (e, p, k) {
          return f(e, p, function (q) {
            var antes = e.caps[idx]; e.caps[idx] = [p, q];
            if (k(q)) return true;
            e.caps[idx] = antes; return false;
          });
        };
      }
      case 'la': {
        var fl = compilar(nodo.sub);
        return function (e, p, k) {
          var salvos = e.caps.slice();
          var achou = fl(e, p, function () { return true; });
          if (nodo.neg) { e.caps = salvos; return achou ? false : k(p); }
          if (!achou) { e.caps = salvos; return false; }
          if (k(p)) return true;
          e.caps = salvos; return false;
        };
      }
      case 'lb': {
        // Olha para trás: procura um começo s <= p tal que o trecho s..p case exatamente.
        var fb = compilar(nodo.sub);
        return function (e, p, k) {
          var salvos = e.caps.slice(), achou = false;
          for (var s = p; s >= 0 && !achou; s--) {
            if (e.u && s > 0 && s < e.s.length) { var meio = e.s.charCodeAt(s); var ant = e.s.charCodeAt(s - 1); if (meio >= 0xdc00 && meio <= 0xdfff && ant >= 0xd800 && ant <= 0xdbff) continue; }
            achou = fb(e, s, function (q) { return q === p; });
          }
          if (nodo.neg) { e.caps = salvos; return achou ? false : k(p); }
          if (!achou) { e.caps = salvos; return false; }
          if (k(p)) return true;
          e.caps = salvos; return false;
        };
      }
      case 'back': {
        return function (e, p, k) {
          var idx = nodo.idx;
          if (nodo.nome !== undefined) { for (var q = 0; q < e.nomes.length; q++) if (e.nomes[q][0] === nodo.nome) idx = e.nomes[q][1]; }
          var cap = e.caps[idx];
          if (!cap) return k(p);
          var txt = e.s.slice(cap[0], cap[1]), alvo = e.s.substr(p, txt.length);
          var igual = txt === alvo || (e.ic && txt.toUpperCase() === alvo.toUpperCase());
          return alvo.length === txt.length && igual ? k(p + txt.length) : false;
        };
      }
      case 'rep': {
        var sub = nodo.sub, min = nodo.min, max = nodo.max, lento = nodo.lento, tl = umaLetra(sub);
        if (tl) {
          // um caractere por vez: laço, sem recursão proporcional ao texto
          return function (e, p, k) {
            var pos = [p], q = p, cnt = 0;
            if (lento) {
              while (cnt < min) { var c0 = leitura(e, q); if (c0 < 0 || !tl(e, c0)) return false; q += tam(c0); cnt++; }
              for (;;) {
                if (k(q)) return true;
                if (cnt >= max) return false;
                var c1 = leitura(e, q); if (c1 < 0 || !tl(e, c1)) return false;
                q += tam(c1); cnt++;
              }
            }
            while (cnt < max) { var c = leitura(e, q); if (c < 0 || !tl(e, c)) break; q += tam(c); cnt++; pos.push(q); }
            if (cnt < min) return false;
            for (var j = cnt; j >= min; j--) if (k(pos[j])) return true;
            return false;
          };
        }
        var fs2 = compilar(sub), capturas = [];
        (function achar(x) { if (!x || typeof x !== 'object') return; if (x.t === 'grp') capturas.push(x.idx); if (x.sub) achar(x.sub); if (x.itens) x.itens.forEach(achar); if (x.alts) x.alts.forEach(achar); })(sub);
        return function (e, p, k) {
          function laco(q, cnt) {
            function mais() {
              if (cnt >= max) return false;
              var salvos = capturas.map(function (ix) { return e.caps[ix]; });
              capturas.forEach(function (ix) { e.caps[ix] = undefined; });
              var r = fs2(e, q, function (z) { if (z === q && cnt >= min) return false; return laco(z, cnt + 1); });
              if (!r) capturas.forEach(function (ix, w) { e.caps[ix] = salvos[w]; });
              return r;
            }
            if (cnt < min) return mais();
            if (lento) return k(q) || mais();
            return mais() || k(q);
          }
          return laco(p, 0);
        };
      }
    }
    throw new Error('nó desconhecido: ' + nodo.t);
  }
  function casador(info, chave) { return cacheComp[chave] || (cacheComp[chave] = compilar(info.ast)); }

  // ---------- o objeto RegExp ----------
  function RX(source, flags) {
    flags = flags === undefined ? '' : String(flags);
    if (/[^dgimsuy]/.test(flags) || /(.).*\1/.test(flags)) throw new SyntaxError("Invalid flags supplied to RegExp constructor '" + flags + "'");
    source = String(source);
    this.__info = ler(source, flags);
    this.__chave = flags + '/' + source;
    this.__f = flags;
    Object.defineProperty(this, 'source', { value: source === '' ? '(?:)' : source, writable: true, configurable: true, enumerable: false });
    Object.defineProperty(this, 'flags', { value: flags.split('').sort().join(''), writable: true, configurable: true, enumerable: false });
    var self = this;
    [['global', 'g'], ['ignoreCase', 'i'], ['multiline', 'm'], ['sticky', 'y'], ['unicode', 'u'], ['dotAll', 's'], ['hasIndices', 'd']].forEach(function (par) {
      Object.defineProperty(self, par[0], { value: flags.indexOf(par[1]) >= 0, writable: true, configurable: true, enumerable: false });
    });
    Object.defineProperty(this, 'lastIndex', { value: 0, writable: true, configurable: false, enumerable: false });
  }
  Object.setPrototypeOf(RX.prototype, Nativo.prototype);
  Object.defineProperty(RX.prototype, Symbol.toStringTag, { value: 'RegExp', configurable: true });
  function casarEm(rx, s, p) {
    var e = { s: s, caps: [], u: rx.unicode, ic: rx.ignoreCase, m: rx.multiline, dotAll: rx.dotAll, nomes: rx.__info.nomes };
    var fim = -1;
    var ok = casador(rx.__info, rx.__chave)(e, p, function (q) { fim = q; return true; });
    return ok ? { e: e, fim: fim } : null;
  }
  function montar(rx, s, p, r) {
    var info = rx.__info, res = [s.slice(p, r.fim)];
    for (var g = 1; g <= info.grupos; g++) res.push(r.e.caps[g] ? s.slice(r.e.caps[g][0], r.e.caps[g][1]) : undefined);
    res.index = p; res.input = s;
    if (info.nomes.length) { var grupos = Object.create(null); info.nomes.forEach(function (nm) { grupos[nm[0]] = res[nm[1]]; }); res.groups = grupos; } else res.groups = undefined;
    if (rx.hasIndices) {
      var ind = [[p, r.fim]]; for (var h = 1; h <= info.grupos; h++) ind.push(r.e.caps[h] ? [r.e.caps[h][0], r.e.caps[h][1]] : undefined);
      if (info.nomes.length) { var gi = Object.create(null); info.nomes.forEach(function (nm) { gi[nm[0]] = ind[nm[1]]; }); ind.groups = gi; } else ind.groups = undefined;
      res.indices = ind;
    }
    return res;
  }
  RX.prototype.exec = function (str) {
    var s = String(str), usaLi = this.global || this.sticky, li = usaLi ? Math.min(Math.max(Math.floor(Number(this.lastIndex)) || 0, 0), Infinity) : 0;
    if (li > s.length) { this.lastIndex = 0; return null; }
    for (var p = li; p <= s.length; p++) {
      var r = casarEm(this, s, p);
      if (r) { if (usaLi) this.lastIndex = r.fim; return montar(this, s, p, r); }
      if (this.sticky) break;
      if (this.unicode && p < s.length) { var c = s.charCodeAt(p); if (c >= 0xd800 && c <= 0xdbff && p + 1 < s.length) { var d = s.charCodeAt(p + 1); if (d >= 0xdc00 && d <= 0xdfff) p++; } }
    }
    if (usaLi) this.lastIndex = 0;
    return null;
  };
  RX.prototype.test = function (s) { return this.exec(s) !== null; };
  RX.prototype.toString = function () { return '/' + this.source + '/' + this.flags; };
  RX.prototype.compile = function (src, f) { var n = new RX(src === undefined ? '' : src, f); Object.assign(this, { __info: n.__info, __chave: n.__chave }); return this; };
  function proximoIndice(s, i, u) { if (u && i < s.length) { var c = s.charCodeAt(i); if (c >= 0xd800 && c <= 0xdbff && i + 1 < s.length) { var d = s.charCodeAt(i + 1); if (d >= 0xdc00 && d <= 0xdfff) return i + 2; } } return i + 1; }
  RX.prototype[Symbol.match] = function (str) {
    var s = String(str);
    if (!this.global) return this.exec(s);
    this.lastIndex = 0;
    var out = [];
    for (;;) { var r = this.exec(s); if (!r) break; out.push(r[0]); if (r[0] === '') this.lastIndex = proximoIndice(s, this.lastIndex, this.unicode); }
    return out.length ? out : null;
  };
  RX.prototype[Symbol.matchAll] = function (str) {
    var s = String(str), clone = new RX(this.source === '(?:)' ? '' : this.source, this.__f);
    clone.lastIndex = this.lastIndex;
    var glob = this.global, acabou = false;
    var it = {
      next: function () {
        if (acabou) return { value: undefined, done: true };
        var r = clone.exec(s);
        if (!r) { acabou = true; return { value: undefined, done: true }; }
        if (!glob) acabou = true; else if (r[0] === '') clone.lastIndex = proximoIndice(s, clone.lastIndex, clone.unicode);
        return { value: r, done: false };
      }
    };
    it[Symbol.iterator] = function () { return this; };
    return it;
  };
  RX.prototype[Symbol.search] = function (str) {
    var s = String(str), guardado = this.lastIndex; this.lastIndex = 0;
    var r = this.exec(s); this.lastIndex = guardado;
    return r ? r.index : -1;
  };
  function expandir(modelo, r, s) {
    return modelo.replace(/\$(\$|&|`|'|\d{1,2}|<[^>]*>)/g, function (tudo, k) {
      if (k === '$') return '$';
      if (k === '&') return r[0];
      if (k === '`') return s.slice(0, r.index);
      if (k === "'") return s.slice(r.index + r[0].length);
      if (k.charAt(0) === '<') { if (r.groups === undefined) return tudo; var v = r.groups[k.slice(1, -1)]; return v === undefined ? '' : String(v); }
      var num = parseInt(k, 10), total = r.length - 1;
      if (k.length === 2 && num > total) { num = parseInt(k.charAt(0), 10); if (num < 1 || num > total) return tudo; var resto = k.charAt(1); var v1 = r[num]; return (v1 === undefined ? '' : v1) + resto; }
      if (num < 1 || num > total) return tudo;
      return r[num] === undefined ? '' : r[num];
    });
  }
  RX.prototype[Symbol.replace] = function (str, subst) {
    var s = String(str), fn = typeof subst === 'function';
    if (!fn) subst = String(subst);
    var glob = this.global, achados = [];
    if (glob) this.lastIndex = 0;
    for (;;) {
      var r = this.exec(s);
      if (!r) break;
      achados.push(r);
      if (!glob) break;
      if (r[0] === '') this.lastIndex = proximoIndice(s, this.lastIndex, this.unicode);
    }
    var out = '', pos = 0;
    achados.forEach(function (r) {
      if (r.index < pos) return;
      var rep;
      if (fn) { var args = r.slice(); args.push(r.index, s); if (r.groups !== undefined) args.push(r.groups); rep = String(subst.apply(undefined, args)); }
      else rep = expandir(subst, r, s);
      out += s.slice(pos, r.index) + rep; pos = r.index + r[0].length;
    });
    return out + s.slice(pos);
  };
  RX.prototype[Symbol.split] = function (str, limite) {
    var s = String(str), lim = limite === undefined ? 4294967295 : limite >>> 0, out = [];
    if (lim === 0) return out;
    var sticky = new RX(this.source === '(?:)' ? '' : this.source, this.__f.replace(/[gy]/g, '') + 'y');
    if (s.length === 0) { return casarEm(sticky, s, 0) ? [] : [s]; }
    var p = 0, q = 0;
    while (q < s.length) {
      var r = casarEm(sticky, s, q);
      if (!r || r.fim === p || r.fim > s.length) { q = proximoIndice(s, q, sticky.unicode); continue; }
      if (r.fim === q && q === p) { q = proximoIndice(s, q, sticky.unicode); continue; }
      out.push(s.slice(p, q)); if (out.length === lim) return out;
      var m = montar(sticky, s, q, r);
      for (var g = 1; g < m.length; g++) { out.push(m[g]); if (out.length === lim) return out; }
      p = r.fim; q = p;
    }
    out.push(s.slice(p));
    return out;
  };

  // ---------- como entra no resto do ambiente ----------
  function temLookbehind(src) { return /\(\?<[=!]/.test(src); }
  G.__rx = function (src, flags) { return new RX(src, flags); };
  function RegExpNovo(p, f) {
    var chamado = new.target === undefined;
    if (p instanceof RX) { if (f === undefined) f = p.__f; p = p.source === '(?:)' ? '' : p.source; }
    if (chamado && f === undefined && p instanceof Nativo && !(p instanceof RX)) return p;
    try { return chamado ? Nativo(p, f) : Reflect.construct(Nativo, [p, f], new.target); }
    catch (e) {
      var fonte = p instanceof Nativo ? p.source : String(p);
      if (e instanceof SyntaxError && temLookbehind(fonte)) return new RX(fonte, f === undefined ? (p instanceof Nativo ? p.flags : '') : f);
      throw e;
    }
  }
  Object.defineProperty(RegExpNovo, 'name', { value: 'RegExp' });
  Object.defineProperty(RegExpNovo, 'length', { value: 2 });
  RegExpNovo.prototype = Nativo.prototype;
  Object.getOwnPropertyNames(Nativo).forEach(function (k) {
    if (k === 'prototype' || k === 'name' || k === 'length' || k in RegExpNovo && k !== 'escape') return;
    var d = Object.getOwnPropertyDescriptor(Nativo, k);
    try { Object.defineProperty(RegExpNovo, k, d); } catch (e) {}
  });
  try { Object.defineProperty(RegExpNovo, Symbol.species, { get: function () { return RegExpNovo; }, configurable: true }); } catch (e) {}
  try { Object.defineProperty(Nativo.prototype, 'constructor', { value: RegExpNovo, writable: true, configurable: true, enumerable: false }); } catch (e) {}
  G.RegExp = RegExpNovo;
  G.__rxClasse = RX;
})(this);
"""#
}
