// Referência em JS do PodaCSS.swift (app/Nusky): a mesma lógica, passo a passo, para poder ser testada fora do iPhone.
const DESCARTAR = new Set(['font-face','keyframes','-webkit-keyframes','-moz-keyframes','-o-keyframes','charset','counter-style','font-feature-values','page','view-transition']);
function enxugar(css) {
  const b = Buffer.from(css, 'utf8'), n = b.length, out = [];
  let i = 0, espaco = false;
  const eh = (c) => c === 0x20 || c === 0x09 || c === 0x0a || c === 0x0d || c === 0x0c;
  const copiarTexto = (aspa) => { // i está na aspa de abertura
    out.push(b[i]); i++;
    while (i < n) { const c = b[i]; out.push(c); i++; if (c === 0x5c && i < n) { out.push(b[i]); i++; } else if (c === aspa) return; }
  };
  const pularBloco = () => { // i logo depois do "{"
    let prof = 1;
    while (i < n && prof > 0) {
      const c = b[i];
      if (c === 0x2f && b[i + 1] === 0x2a) { i += 2; while (i < n && !(b[i] === 0x2a && b[i + 1] === 0x2f)) i++; i += 2; }
      else if (c === 0x22 || c === 0x27) { i++; while (i < n) { const d = b[i]; i++; if (d === 0x5c) i++; else if (d === c) break; } }
      else { if (c === 0x7b) prof++; else if (c === 0x7d) prof--; i++; }
    }
  };
  while (i < n) {
    const c = b[i];
    if (c === 0x2f && b[i + 1] === 0x2a) { i += 2; while (i < n && !(b[i] === 0x2a && b[i + 1] === 0x2f)) i++; i += 2; espaco = true; continue; }
    if (eh(c)) { espaco = true; i++; continue; }
    if (espaco) { if (out.length && out[out.length - 1] !== 0x7b && out[out.length - 1] !== 0x7d && out[out.length - 1] !== 0x3b) out.push(0x20); espaco = false; }
    if (c === 0x22 || c === 0x27) { copiarTexto(c); continue; }
    if (c === 0x40) { // @regra
      let j = i + 1; while (j < n && ((b[j] >= 0x61 && b[j] <= 0x7a) || (b[j] >= 0x41 && b[j] <= 0x5a) || b[j] === 0x2d)) j++;
      const nome = b.slice(i + 1, j).toString('latin1').toLowerCase();
      // prelúdio até { ou ;
      let k = j; while (k < n && b[k] !== 0x7b && b[k] !== 0x3b) { if (b[k] === 0x22 || b[k] === 0x27) { const q = b[k]; k++; while (k < n && b[k] !== q) { if (b[k] === 0x5c) k++; k++; } } k++; }
      const preludio = b.slice(j, Math.min(k, n)).toString('utf8').toLowerCase().trim();
      let descartar = DESCARTAR.has(nome);
      if (nome === 'media' && /^(only\s+)?print\b/.test(preludio) && !/,|screen|all/.test(preludio)) descartar = true;
      if (descartar) { if (k < n && b[k] === 0x7b) { i = k + 1; pularBloco(); } else i = k + 1; espaco = true; continue; }
    }
    out.push(c); i++;
  }
  return Buffer.from(out).toString('utf8');
}
module.exports = { enxugar };
if (require.main === module) {
  const t = (nome, ent, esp) => { const r = enxugar(ent); console.log(r === esp ? 'ok   ' : 'FALHOU', nome, r === esp ? '' : '\n  got: ' + JSON.stringify(r) + '\n  exp: ' + JSON.stringify(esp)); };
  t('comentário', 'a{color:red}/* x { */b{color:blue}', 'a{color:red}b{color:blue}');
  t('font-face', '@font-face{font-family:x;src:url("a.woff2")}a{color:red}', 'a{color:red}');
  t('keyframes aninhado', '@keyframes s{0%{a:b}to{c:d}}p{x:y}', 'p{x:y}');
  t('print', '@media print{a{display:none}}b{c:d}', 'b{c:d}');
  t('print e screen fica', '@media print, screen{a{x:y}}', '@media print, screen{a{x:y}}');
  t('media screen fica', '@media (min-width:40em){a{x:y}}', '@media (min-width:40em){a{x:y}}');
  t('string com chave', 'a::before{content:"}{ /* "}b{c:d}', 'a::before{content:"}{ /* "}b{c:d}');
  t('aspas simples com escape', "a::before{content:'it\\'s }'}b{c:d}", "a::before{content:'it\\'s }'}b{c:d}");
  t('charset', '@charset "utf-8";a{b:c}', 'a{b:c}');
  t('layer e import ficam', '@layer a,b;@import url(x.css);p{q:r}', '@layer a,b;@import url(x.css);p{q:r}');
  t('espaços', 'a   b >  c {\n  color :  red ;\n}', 'a b > c {color : red ;}');
  t('url sem aspas', 'a{background:url(data:image/png;base64,AAA=)}', 'a{background:url(data:image/png;base64,AAA=)}');
  t('utf8', 'a::after{content:"é→"}', 'a::after{content:"é→"}');
  t('@supports fica', '@supports (a:b){p{c:d}}', '@supports (a:b){p{c:d}}');
  t('keyframes depois de font-face', '@font-face{a:b}@-webkit-keyframes x{from{a:b}}p{c:d}', 'p{c:d}');
  t('bloco sem fechar', 'p{c:d}@font-face{a:b', 'p{c:d}');
  const grande = ('.a-b{color:#fff;margin:0 1px}\n/* c */\n').repeat(60000);
  let t0 = Date.now(); const g = enxugar(grande); console.log('grande', grande.length, '->', g.length, (Date.now() - t0) + 'ms');
}
