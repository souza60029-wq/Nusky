// Reescrita de sintaxe que o iOS 15 não lê: lookbehind em regex achado depois de ")" e dentro de template.
const vm = require('vm'), fs = require('fs');
const base = fs.readFileSync('teste.js', 'utf8'); eval(base.slice(base.indexOf('function parse(h)'), base.indexOf('function rodar(')));
const ctx = vm.createContext({});
ctx.__parse = h => JSON.stringify(parse(h)); ctx.__erro = () => {}; ctx.__fim = () => {}; ctx.__acordar = () => {}; ctx.__aviso = () => {}; ctx.__pedir = () => {};
ctx.__pagina = { href: 'https://s.com/', protocolo: 'https:', host: 's.com', agente: 'UA', plataforma: 'iPhone', toque: true, largura: 375, altura: 812, escala: 2, escuro: false };
for (const f of ['moderno.js', 'ambiente.js']) vm.runInContext(fs.readFileSync(f, 'utf8'), ctx);
let falhas = 0; const ok = (c, m) => { if (!c) { falhas++; console.log('FALHOU:', m); } else console.log('ok:', m); };
const mod = ctx.__modernizar;
if (typeof mod !== 'function') { console.log('FALHOU: __modernizar não exposto'); process.exit(1); }
const roda = (src) => { const n = mod(src); return vm.runInContext('(function(){var __r=[];' + n + ';return __r})()', ctx); };
ok(mod('if(1)/(?<=a)b/.test("ab")').indexOf('__rx(') >= 0 && JSON.stringify(roda('if(1)/(?<=a)b/.test("ab")&&__r.push("depois-de-parenteses")')) === '["depois-de-parenteses"]', 'regex com lookbehind logo depois de ")" é trocado por __rx');
ok(mod('var s=`x${/(?<!a)b/.test("cb")?"t":"f"}y`').indexOf('__rx(') >= 0 && JSON.stringify(roda('var s=`x${/(?<!a)b/.test("cb")?"t":"f"}y`;__r.push(s)')) === '["xty"]', 'regex com lookbehind dentro de ${ } de template é trocado por __rx');
ok(JSON.stringify(roda('var s=`a${`b${/(?<=x)y/.test("xy")}`}`;__r.push(s)')) === '["abtrue"]', 'template dentro de template');
ok(mod('var a=8,b=2,c=2;a/b/c') === 'var a=8,b=2,c=2;a/b/c' && JSON.stringify(roda('var a=8,b=2,c=2;__r.push(a/b/c)')) === '[2]', 'divisão comum não é confundida com regex');
ok(JSON.stringify(roda('var f=(x)=>x/2;__r.push(f(8)/2)')) === '[2]', 'divisão depois de ")" continua divisão');
ok(JSON.stringify(roda('class A{static{A.v=5}}__r.push(A.v)')) === '[5]', 'bloco static continua funcionando');
ok(JSON.stringify(roda('var t=`${(()=>{class B{static{B.w=7}};return B.w})()}`;__r.push(t)')) === '["7"]', 'bloco static dentro de template');
console.log(falhas ? 'FALHAS: ' + falhas : 'TUDO OK'); process.exit(falhas ? 1 : 0);
