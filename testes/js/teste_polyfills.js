// Polyfills do JavaScript novo (testados depois de apagar as versões nativas do Node) e o modo honesto.
const vm = require('vm'), fs = require('fs');
const base = fs.readFileSync('teste.js', 'utf8'); eval(base.slice(base.indexOf('function parse(h)'), base.indexOf('function rodar(')));
const APAGAR = `[[Promise,'withResolvers'],[Promise,'try'],[Array,'fromAsync'],[Object,'groupBy'],[Map,'groupBy'],[Object,'hasOwn'],[Array.prototype,'at'],[Array.prototype,'findLast'],[Array.prototype,'findLastIndex'],[Array.prototype,'toSorted'],[Array.prototype,'toReversed'],[Array.prototype,'toSpliced'],[Array.prototype,'with'],
 [Set.prototype,'union'],[Set.prototype,'intersection'],[Set.prototype,'difference'],[Set.prototype,'symmetricDifference'],[Set.prototype,'isSubsetOf'],[Set.prototype,'isSupersetOf'],[Set.prototype,'isDisjointFrom'],[String.prototype,'isWellFormed'],[String.prototype,'toWellFormed'],[Symbol,'dispose'],[ArrayBuffer.prototype,'transfer']].forEach(function(p){delete p[0][p[1]]});
 delete globalThis.Iterator; var IP=Object.getPrototypeOf(Object.getPrototypeOf([][Symbol.iterator]()));['map','filter','take','drop','flatMap','reduce','toArray','forEach','some','every','find'].forEach(function(k){delete IP[k]});`;
function nova(opts = {}, apagar = true) {
  const erros = []; const ctx = vm.createContext({});
  if (apagar) vm.runInContext(APAGAR, ctx);
  ctx.__parse = h => JSON.stringify(parse(h)); ctx.__erro = m => erros.push(m); ctx.__fim = () => {}; ctx.__acordar = () => {}; ctx.__aviso = () => {}; ctx.__pedir = () => {};
  ctx.__pagina = { href: 'https://site.com/', protocolo: 'https:', host: 'site.com', agente: 'UA', plataforma: 'iPhone', toque: true, largura: 375, altura: 812, escala: 2, escuro: false, ...opts };
  for (const f of ['moderno.js', 'ambiente.js', 'extra.js']) vm.runInContext(fs.readFileSync(f, 'utf8'), ctx);
  ctx.__iniciar(JSON.stringify(parse('<html><body></body></html>')));
  return { ctx, erros };
}
const ev = (c, s) => vm.runInContext(s, c);
let falhas = 0; const ok = (c, m) => { if (!c) { falhas++; console.log('FALHOU:', m); } else console.log('ok:', m); };
(async () => {
  const { ctx } = nova();
  const t = (expr, esperado, nome) => { let r; try { r = JSON.stringify(ev(ctx, expr)); } catch (e) { r = 'ERRO ' + e.message; } ok(r === JSON.stringify(esperado), nome + ' (' + r + ')'); };
  t('typeof Promise.withResolvers', 'function', 'Promise.withResolvers existe');
  ok(await ev(ctx, '(async()=>{var r=Promise.withResolvers();setTimeout?0:0;r.resolve(7);return await r.promise})()') === 7, 'withResolvers resolve');
  t('Object.groupBy([1,2,3,4],x=>x%2?"i":"p")', { i: [1, 3], p: [2, 4] }, 'Object.groupBy');
  t('[...Map.groupBy([1,2,3],x=>x>1).entries()]', [[false, [1]], [true, [2, 3]]], 'Map.groupBy');
  t('[3,1,2].toSorted()', [1, 2, 3], 'toSorted'); t('(function(){var a=[3,1,2];a.toSorted();return a})()', [3, 1, 2], 'toSorted não muda o original');
  t('[1,2,3].toReversed()', [3, 2, 1], 'toReversed'); t('[1,2,3].toSpliced(1,1,"x","y")', [1, 'x', 'y', 3], 'toSpliced'); t('[1,2,3].with(-1,9)', [1, 2, 9], 'with');
  t('try{[1].with(5,0)}catch(e){e.name}', 'RangeError', 'with fora do intervalo');
  t('[1,2,3,4].findLast(x=>x<3)', 2, 'findLast'); t('[1,2,3].at(-1)', 3, 'at');
  t('[...new Set([1,2]).union(new Set([2,3]))]', [1, 2, 3], 'Set.union'); t('[...new Set([1,2,3]).intersection(new Set([2,3,4]))]', [2, 3], 'Set.intersection');
  t('[...new Set([1,2,3]).difference(new Set([2]))]', [1, 3], 'Set.difference'); t('[...new Set([1,2]).symmetricDifference(new Set([2,3]))]', [1, 3], 'Set.symmetricDifference');
  t('new Set([1]).isSubsetOf(new Set([1,2]))', true, 'isSubsetOf'); t('new Set([1,2]).isSupersetOf(new Set([2]))', true, 'isSupersetOf'); t('new Set([1]).isDisjointFrom(new Set([2]))', true, 'isDisjointFrom');
  t('"a\\ud800b".isWellFormed()', false, 'isWellFormed'); t('"a\\ud800b".toWellFormed()', 'a\ufffdb', 'toWellFormed'); t('"😀".isWellFormed()', true, 'isWellFormed com par válido');
  t('typeof Symbol.dispose', 'symbol', 'Symbol.dispose');
  t('new ArrayBuffer(8).transfer(4).byteLength', 4, 'ArrayBuffer.transfer');
  t('URL.canParse("https://a.com")+"|"+URL.canParse("nao")', 'true|false', 'URL.canParse');
  ok(await ev(ctx, 'Array.fromAsync((async function*(){yield 1;yield 2})()).then(a=>a.join())') === '1,2', 'Array.fromAsync com iterador assíncrono');
  ok(await ev(ctx, 'Array.fromAsync([Promise.resolve(1),2],x=>x*2).then(a=>a.join())') === '2,4', 'Array.fromAsync com mapa');
  t('[1,2,3,4,5].values().filter(x=>x%2).map(x=>x*10).toArray()', [10, 30, 50], 'Iterator filter/map/toArray');
  t('[1,2,3,4].values().drop(1).take(2).toArray()', [2, 3], 'Iterator drop/take'); t('[1,2,3].values().reduce((a,b)=>a+b)', 6, 'Iterator reduce');
  t('typeof Iterator', 'function', 'Iterator global');
  ok(ev(ctx, 'AbortSignal.any([new AbortController().signal]) instanceof AbortSignal') === true, 'AbortSignal.any');
  // regex com flag v: vale a u quando a expressão é compatível
  ev(ctx, 'var nativo=RegExp;');
  t('new RegExp("[a-z]+","v").test("abc")', true, 'RegExp com flag v (sem operações de conjunto)');
  // modo honesto
  const h = nova({ honesto: true }).ctx;
  const q = e => ev(h, e);
  ok(q('typeof Promise.withResolvers') === 'undefined' && q('typeof [].toSorted') === 'undefined' && q('typeof Object.groupBy') === 'undefined', 'honesto: não define o JavaScript novo');
  ok(q('typeof TextDecoderStream') === 'undefined' && q('typeof AbortSignal.timeout') === 'undefined', 'honesto: some o que o Safari 15 não tem (streams de texto, AbortSignal.timeout)');
  ok(q('RegExp === __rxNativo') === true, 'honesto: o RegExp global volta a ser o nativo (sem lookbehind inventado)');
  const normal = nova({}, false).ctx;
  ok(ev(normal, 'typeof TextDecoderStream') === 'function', 'sem honesto: TextDecoderStream continua existindo');
  console.log(falhas ? 'FALHAS: ' + falhas : 'TUDO OK'); process.exit(falhas ? 1 : 0);
})();
