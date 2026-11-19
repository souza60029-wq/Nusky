const vm=require('vm'),fs=require('fs'),path=require('path'),url=require('url');
const base=fs.readFileSync('teste.js','utf8');eval(base.slice(base.indexOf('function parse(h)'),base.indexOf('function rodar(')));
const COMEXTRA=!process.argv.includes('--sem-extra');
function montar(html,externos={},opts={}){
  const erros=[],guardados=new Map(),ev={fim:false,aval:[]};const ctx=vm.createContext({});let tm;
  ctx.__parse=h=>JSON.stringify(parse(h));ctx.__erro=m=>erros.push(m);ctx.__fim=()=>{ev.fim=true};
  ctx.__acordar=ms=>{clearTimeout(tm);tm=setTimeout(()=>{try{ctx.__tick()}catch(e){}},ms)};ctx.__aviso=()=>{};
  ctx.__pagina={href:'https://site.com/app/',protocolo:'https:',host:'site.com',agente:'UA',plataforma:'iPhone',toque:true,largura:375,altura:812,escala:2,escuro:false};
  // JavaScriptCore do iOS 15 não lê "static {": simulado aqui
  function semLiterais(c){let o='',i=0,n=c.length,prev='';while(i<n){const ch=c[i];
    if(ch==='/'&&c[i+1]==='/'){while(i<n&&c[i]!=='\n')i++;continue}
    if(ch==='/'&&c[i+1]==='*'){i=c.indexOf('*/',i+2);i=i<0?n:i+2;continue}
    if(ch==='"'||ch==="'"){const q=ch;i++;while(i<n&&c[i]!==q){if(c[i]==='\\')i++;i++}i++;o+='""';prev='"';continue}
    if(ch==='`'){i++;while(i<n&&c[i]!=='`'){if(c[i]==='\\')i++;i++}i++;o+='""';prev='"';continue}
    if(ch==='/'&&/[=(,:;!&|?{}[]/.test(prev||'=')){i++;let dentro=false;while(i<n&&(c[i]!=='/'||dentro)){if(c[i]==='\\')i++;else if(c[i]==='[')dentro=true;else if(c[i]===']')dentro=false;i++}i++;while(/[a-z]/.test(c[i]||''))i++;o+='/r/';prev='r';continue}
    if(!/\s/.test(ch))prev=ch;o+=ch;i++}return o}
  const velho={test:c=>/static\s*\{/.test(semLiterais(String(c)))};
  const aval=(o,c)=>{ev.aval.push(o);if(opts.jsc15&&velho.test(c))return "Unexpected token '{' ("+o+":1:32)";try{vm.runInContext(c,ctx,{filename:o});return ''}catch(e){return (e&&e.message)+' ('+o+':1:1)'}};
  ctx.__avaliar=aval;
  ctx.__avaliarGuardado=u=>{const t=guardados.get(u);return t===undefined?'ausente: '+u:aval(u,t)};
  if(!opts.semFonte)ctx.__fonteGuardada=u=>guardados.get(u)||'';
  ctx.__pedir=(id,u,m,cab,corpo,guardar)=>{const k=u.replace('https://site.com','');setTimeout(()=>{const t=externos[k];
    if(t===undefined)return vm.runInContext(`__resposta(${id},404,"{}","","")`,ctx);
    if(guardar){guardados.set(u,t);vm.runInContext(`__resposta(${id},200,"{}","","")`,ctx)}
    else vm.runInContext(`__resposta(${id},200,"{}",${JSON.stringify(t)},"")`,ctx)},Math.random()*4)};
  if(opts.jsc15){ // eval também não lê static blocks no JSC 15
    const real=vm.runInContext('eval',ctx);ctx.eval=function(c){if(velho.test(String(c)))throw new (vm.runInContext('SyntaxError',ctx))("Unexpected token '{'");return real(c)};
  }
  vm.runInContext('var __log=[];',ctx);
  vm.runInContext(fs.readFileSync('ambiente.js','utf8'),ctx);
  if(COMEXTRA)vm.runInContext(fs.readFileSync('extra.js','utf8'),ctx);
  ctx.__iniciar(JSON.stringify(parse(html)));
  if(opts.vivo)ctx.__vivo();
  return {ctx,erros,ev};
}
const esperar=ms=>new Promise(r=>setTimeout(r,ms));
let falhas=0;const ok=(c,m)=>{if(!c){falhas++;console.log('FALHOU:',m)}else console.log('ok:',m)};
const ev=(c,s)=>vm.runInContext(s,c);
const log=m=>JSON.parse(ev(m.ctx,'JSON.stringify(__log)'));
async function nativo(entrada){
  const r=require('child_process').spawnSync(process.execPath,['-e',`globalThis.__log=[];import(${JSON.stringify(url.pathToFileURL(path.resolve('fx',entrada)).href)}).then(()=>new Promise(r=>setTimeout(r,80))).catch(e=>globalThis.__log.push(['ERRO',e.message])).then(()=>console.log(JSON.stringify(globalThis.__log)))`],{encoding:'utf8'});
  if(r.status!==0)throw new Error('ref: '+r.stderr);return JSON.parse(r.stdout);
}
const fxs={};for(const f of fs.readdirSync('fx'))fxs['/fx/'+f]=fs.readFileSync('fx/'+f,'utf8');
(async()=>{
 // ===== MutationObserver =====
 let m=montar('<html><body><div id="a"><p id="p">x</p></div></body></html>',{},{vivo:true});
 const c=m.ctx;
 let r=await ev(c,`new Promise(function(ok){var out=[];var mo=new MutationObserver(function(rs){out=out.concat(rs.map(function(x){return x.type+':'+(x.addedNodes.length)+'/'+(x.removedNodes.length)+(x.attributeName?':'+x.attributeName+'='+x.oldValue:'')}));});
  var a=document.getElementById('a');mo.observe(a,{childList:true,attributes:true,attributeOldValue:true,characterData:true,subtree:true});
  var d=document.createElement('span');a.appendChild(d);a.setAttribute('class','k');a.setAttribute('class','k2');d.textContent='t';a.removeChild(d);
  Promise.resolve().then(function(){Promise.resolve().then(function(){ok(out.join(' | '))})})})`);
 ok(r==='childList:1/0 | attributes:0/0:class=null | attributes:0/0:class=k | childList:1/0 | childList:0/1','MutationObserver: childList, attributes (oldValue) e subtree ('+r+')');
 r=await ev(c,`new Promise(function(ok){var n=0;var t=document.getElementById('p').firstChild;var mo=new MutationObserver(function(rs){n+=rs.length;ok(n+':'+rs[0].type+':'+rs[0].oldValue)});mo.observe(t,{characterData:true,characterDataOldValue:true});t.data='novo'})`);
 ok(r==='1:characterData:x','MutationObserver: characterData com oldValue ('+r+')');
 r=await ev(c,`new Promise(function(ok){var n=0;var mo=new MutationObserver(function(){n++});var a=document.getElementById('a');mo.observe(a,{attributes:true,attributeFilter:['data-x']});a.setAttribute('id2','1');a.setAttribute('data-x','1');Promise.resolve().then(function(){Promise.resolve().then(function(){ok(n)})})})`);
 ok(r===1,'MutationObserver: attributeFilter só avisa o atributo pedido');
 r=await ev(c,`new Promise(function(ok){var n=0;var mo=new MutationObserver(function(){n++});var a=document.getElementById('a');mo.observe(a,{childList:true});a.appendChild(document.createElement('b'));var t=mo.takeRecords().length;mo.disconnect();a.appendChild(document.createElement('i'));Promise.resolve().then(function(){Promise.resolve().then(function(){ok(t+'/'+n)})})})`);
 ok(r==='1/0','MutationObserver: takeRecords esvazia e disconnect para de avisar ('+r+')');
 r=await ev(c,`new Promise(function(ok){var tipos=[];var mo=new MutationObserver(function(rs){rs.forEach(function(x){tipos.push(x.type+x.addedNodes.length+x.removedNodes.length)})});var a=document.getElementById('a');mo.observe(a,{childList:true});a.innerHTML='<i></i><b></b>';Promise.resolve().then(function(){Promise.resolve().then(function(){ok(tipos.join())})})})`);
 ok(/childList0\d/.test(r)&&r.indexOf('childList10')>=0,'MutationObserver: innerHTML gera remoções e adições ('+r+')');
 // ===== IntersectionObserver / ResizeObserver / PerformanceObserver =====
 r=await ev(c,`new Promise(function(ok){var el=document.getElementById('a');var io=new IntersectionObserver(function(es,o){ok(es.length+':'+es[0].isIntersecting+':'+es[0].intersectionRatio+':'+(es[0].target===el)+':'+(o===io))});io.observe(el)})`);
 ok(r==='1:true:1:true:true','IntersectionObserver avisa que o elemento está visível ('+r+')');
 r=await ev(c,`new Promise(function(ok){var el=document.getElementById('p');var n=0;var io=new IntersectionObserver(function(){n++});for(var i=0;i<8;i++){io.observe(el);io.unobserve(el)}io.observe(el);setTimeout(function(){ok(n)},30)})`);
 ok(r<=3,'IntersectionObserver: trava contra carregar-mais em laço ('+r+' avisos em 9 observe)');
 r=await ev(c,`new Promise(function(ok){var el=document.getElementById('a');var ro=new ResizeObserver(function(es){ok(es[0].contentRect.width+':'+(es[0].target===el)+':'+es[0].contentBoxSize[0].inlineSize)});ro.observe(el)})`);
 ok(r==='375:true:375','ResizeObserver avisa o tamanho inicial ('+r+')');
 ok(ev(c,'PerformanceObserver.supportedEntryTypes.indexOf("mark")>=0&&typeof new PerformanceObserver(function(){}).observe==="function"'),'PerformanceObserver tem supportedEntryTypes');
 // ===== template.content =====
 const mt=montar('<html><body><template id="t"><li class="a">um</li><li>dois</li></template><div id="d"></div></body></html>',{},{vivo:true});
 r=ev(mt.ctx,`(function(){var t=document.getElementById('t');var f=t.content;var a=[f===t.content,f.childNodes.length,f.firstChild.className,f.cloneNode(true).childNodes.length,t.content instanceof DocumentFragment||f.nodeType===11];f.appendChild(document.createElement('li'));a.push(t.content.childNodes.length);document.getElementById('d').appendChild(f.cloneNode(true));a.push(document.getElementById('d').childNodes.length);return a.join()})()`);
 ok(r==='true,2,a,2,true,3,3','template.content: fragmento estável, clonável e que aceita appendChild ('+r+')');
 r=ev(mt.ctx,`(function(){var t=document.createElement('template');t.innerHTML='<b>x</b>';var a=t.content.childNodes.length;t.innerHTML='<b>1</b><i>2</i>';return a+','+t.content.childNodes.length+','+document.createElement('div').content})()`);
 ok(r==='1,2,undefined','template.content acompanha mudança do innerHTML e só existe em <template> ('+r+')');
 // ===== CryptoKey & cia =====
 ok(ev(c,'typeof CryptoKey')==='function'&&ev(c,'typeof SubtleCrypto')==='function'&&ev(c,'crypto instanceof Crypto'),'CryptoKey, SubtleCrypto e Crypto existem (ChatGPT)');
 // ===== await no nível do arquivo (comparado com o ESM do Node) =====
 for(const [nome,ent] of [['TLA simples + export','usetla.js'],['TLA aguardando timer; dependente espera','usa_espera.js'],['TLA com import() dinâmico','tla_dyn.js'],['for await no topo','tla_for.js'],['async arrow sem TLA real','sem_tla_async.js']]){
   const ref=await nativo(ent);
   const mm=montar(`<html><body><script type="module" src="/fx/${ent}"></script></body></html>`,fxs);
   await esperar(260);
   const meu=log(mm);
   ok(JSON.stringify(ref)===JSON.stringify(meu),'módulo '+nome+' = ESM do Node ('+JSON.stringify(meu)+')'+(JSON.stringify(ref)===JSON.stringify(meu)?'':' ref='+JSON.stringify(ref)+' erros='+mm.erros));
 }
 let mm=montar(`<html><body><script type="module" src="/fx/tla_erro.js"></script><script type="module" src="/fx/efeito.js"></script></body></html>`,fxs);
 await esperar(200);
 ok(JSON.stringify(log(mm))==='["efeito"]'&&mm.erros.some(e=>/falhou/.test(e)),'TLA que rejeita: erro registrado e os outros módulos seguem ('+mm.erros[0]+')');
 mm=montar(`<html><body><script type="module" src="/fx/tla_espera.js"></script><script>__log.push('classico')</script><script type="module" src="/fx/efeito.js"></script></body></html>`,fxs);
 await esperar(220);
 ok(JSON.stringify(log(mm))==='["classico","antes","depois","efeito"]','ordem: clássico → módulo com TLA (espera) → módulo seguinte → '+JSON.stringify(log(mm)));
 // ===== static { } de classe (JavaScriptCore do iOS 15 não lê) =====
 const SB=`class A{static x=1;static{this.y=this.x+1;var tmp=5;this.z=tmp*2}static w=A.y+100}
globalThis.__log.push([A.x,A.y,A.z,A.w,typeof tmp]);
const B=class extends A{static{this.nome='B'}static{this.dobro=this.z*2}};
globalThis.__log.push([B.nome,B.dobro,B.y]);
class C{static{ const s="static { nao mexe }"; this.s=s; /* static { comentario } */ this.r=/static\\s*\\{/.test('static {'); }}
globalThis.__log.push([C.s,C.r]);
class D{#p=3;static{D.ler=o=>o.#p}static t=\`a\${'b'}static{\`}
globalThis.__log.push([D.ler(new D),typeof D.t]);
class E{static{class F{static{E.dentro='interno'}}}}
globalThis.__log.push(E.dentro);`;
 const esperado=await new Promise(res=>{const r=require('child_process').spawnSync(process.execPath,['-e','globalThis.__log=[];'+SB+';console.log(JSON.stringify(__log))'],{encoding:'utf8'});res(JSON.parse(r.stdout))});
 m=montar(`<html><body><script>${SB}</script></body></html>`,{},{jsc15:true});
 await esperar(60);
 ok(JSON.stringify(log(m))===JSON.stringify(esperado),'static { }: script inline falha no "JSC 15", é reescrito e dá o mesmo resultado do Node ('+JSON.stringify(log(m))+')'+(JSON.stringify(log(m))===JSON.stringify(esperado)?'':' esperado='+JSON.stringify(esperado)+' erros='+m.erros));
 m=montar(`<html><body><script src="/a.js"></script></body></html>`,{'/a.js':SB},{jsc15:true});
 await esperar(100);
 ok(JSON.stringify(log(m))===JSON.stringify(esperado)&&m.erros.length===0,'static { }: script externo guardado no nativo é lido de volta, reescrito e roda ('+m.erros+')');
 m=montar(`<html><body><script type="module" src="/mod.js"></script></body></html>`,{'/mod.js':SB.replace(/globalThis\./g,'globalThis.')+';export const ok=1;'},{jsc15:true});
 await esperar(120);
 ok(JSON.stringify(log(m))===JSON.stringify(esperado),'static { }: módulo também ('+JSON.stringify(log(m)).slice(0,60)+')');
 // não mexe em script que não tem o problema, nem repete script com erro de outro tipo
 m=montar(`<html><body><script>var __n=(typeof __n==='undefined'?0:__n)+1; globalThis.__log.push('uma vez'); foo.bar.baz();</script></body></html>`,{},{jsc15:true});
 await esperar(60);
 ok(JSON.stringify(log(m))==='["uma vez"]','erro de execução (não de leitura) não repete o script');
 m=montar(`<html><body><script src="/ruim.js"></script></body></html>`,{'/ruim.js':'var x = ;  // 1:32 de verdade'},{jsc15:true});
 await esperar(60);
 ok(m.erros.length===1&&/perto de: «/.test(m.erros[0]),'erro de leitura sem static { }: a mensagem agora mostra o trecho perto do problema ('+m.erros[0]+')');
 console.log(falhas?'FALHAS: '+falhas:'TUDO OK (compat)');process.exit(falhas?1:0);
})();
