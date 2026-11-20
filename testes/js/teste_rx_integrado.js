const vm=require('vm'),fs=require('fs');
let falhas=0;const ok=(c,m)=>{if(!c){falhas++;console.log('FALHOU:',m)}else console.log('ok:',m)};
// 1) o RegExp trocado continua se comportando como o nativo
const ctx=vm.createContext({});vm.runInContext(fs.readFileSync('moderno.js','utf8'),ctx);
const r=s=>vm.runInContext(s,ctx);
ok(r(`(function(){var a=new RegExp('a(b)','g'),b=RegExp('x'),c=new RegExp(/q/gi),d=RegExp(a);class E extends RegExp{};var e=new E('z','g');return [a instanceof RegExp,b.test('x'),c.flags,d===a,e instanceof E,e.test('zz'),'aXbab'.replace(a,'[$1]'),RegExp.prototype.constructor===RegExp,Object.prototype.toString.call(a)].join()})()`)==='true,true,gi,true,true,true,aXb[b],true,[object RegExp]','RegExp trocado: new, chamada simples, cópia, subclasse, instanceof, replace');
// 2) regex com lookbehind via new RegExp (o nativo daqui aceita, então simulo um que recusa)
const ctx2=vm.createContext({});
vm.runInContext(`var real=RegExp;RegExp=function RegExp(p,f){if(/\\(\\?<[=!]/.test(String(p)))throw new SyntaxError('Invalid regular expression: invalid group specifier name');return new.target?Reflect.construct(real,[p,f],new.target):real(p,f)};RegExp.prototype=real.prototype;`,ctx2);
vm.runInContext(fs.readFileSync('moderno.js','utf8'),ctx2);
ok(vm.runInContext(`(function(){var a=new RegExp('(?<=\\\\$)\\\\d+','g'),b=RegExp('(?<!a)b');return ['cost $12 and $3'.match(a).join('|'),b.test('ab'),b.test('cb'),'1234567'.replace(new RegExp('(?<=\\\\d)(?=(\\\\d{3})+$)','g'),','),'a1b2'.split(new RegExp('(?<=\\\\d)')).join('|'),a instanceof RegExp].join()})()`,ctx2)==='12|3,false,true,1,234,567,a1|b2|,true'.replace('|,',','),'new RegExp com lookbehind cai no motor do app: match, test, replace, split');
// 3) regex literal com lookbehind em script/módulo que o "JSC 15" recusa: o ambiente reescreve e roda
const base=fs.readFileSync('teste.js','utf8');eval(base.slice(base.indexOf('function parse(h)'),base.indexOf('function rodar(')));
function montar(html){const erros=[];const c=vm.createContext({});
  c.__parse=h=>JSON.stringify(parse(h));c.__erro=m=>erros.push(m);c.__fim=()=>{};c.__acordar=()=>{};c.__aviso=()=>{};c.__pedir=()=>{};
  c.__pagina={href:'https://s.com/',protocolo:'https:',host:'s.com',agente:'UA',plataforma:'iPhone',toque:true,largura:375,altura:812,escala:2,escuro:false};
  const ruim=t=>/\/[^\/\n]*\(\?<[=!][^\/\n]*\//.test(t.replace(/"[^"\n]*"|'[^'\n]*'/g,'""'));
  c.__avaliar=(o,t)=>{if(ruim(t)&&!/__rx\(/.test(t))return "Invalid regular expression: invalid group specifier name ("+o+":1:5)";try{vm.runInContext(t,c);return ''}catch(e){return e.message+' ('+o+':1:1)'}};
  vm.runInContext(fs.readFileSync('moderno.js','utf8'),c);vm.runInContext(fs.readFileSync('ambiente.js','utf8'),c);
  c.__iniciar(JSON.stringify(parse(html)));return {c,erros}}
let m=montar(`<html><body><script>var __r=[ 'a1,b22'.replace(/(?<=\\d)(?=\\d)/g,'.'), /(?<!x)y/.test('xy'), /(?<=^|\\s)@\\w+/g.exec('hi @ana')[0], 'cost $5'.match(/(?<=\\$)\\d/)[0] ].join('|');</script></body></html>`);
ok(m.c.__r==='a1,b2.2|false|@ana|5'&&m.erros.length===0,'script com regex /(?<=…)/ literal: reescrito e roda certo ('+m.c.__r+' '+m.erros+')');
console.log(falhas?'FALHAS: '+falhas:'TUDO OK (rx integrado)');process.exit(falhas?1:0);
