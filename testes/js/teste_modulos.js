const vm=require('vm'),fs=require('fs'),path=require('path'),url=require('url');
const base=fs.readFileSync('teste.js','utf8');eval(base.slice(base.indexOf('function parse(h)'),base.indexOf('function rodar(')));
const ARQ=process.argv[2]||'ambiente.js';
function montar(html,externos,opts={}){
  const erros=[];const ctx=vm.createContext({});
  const ev={fim:false};
  ctx.__parse=h=>JSON.stringify(parse(h));ctx.__erro=m=>erros.push(m);ctx.__fim=()=>{ev.fim=true};ctx.__acordar=()=>{};ctx.__aviso=()=>{};
  ctx.__pagina={href:'https://site.com/app/',protocolo:'https:',host:'site.com',agente:'UA',plataforma:'iPhone',toque:true,largura:375,altura:812,escala:2,escuro:false,...opts};
  ctx.__pedir=(id,u)=>{const k=u.replace('https://site.com','');setTimeout(()=>{const t=externos[k];
    vm.runInContext(t===undefined?`__resposta(${id},404,"{}","","")`:`__resposta(${id},200,"{}",${JSON.stringify(t)},"")`,ctx)},Math.random()*4)};
  vm.runInContext('var __log=[];',ctx);
  vm.runInContext(fs.readFileSync(ARQ,'utf8'),ctx);ctx.__iniciar(JSON.stringify(parse(html)));
  return {ctx,erros,ev};
}
const esperar=ms=>new Promise(r=>setTimeout(r,ms));
async function ate(m,ms=2000){for(let i=0;i<ms/5&&!m.ev.fim;i++)await esperar(5);await esperar(30)}
async function nativo(entrada){ // referência: ESM de verdade do Node, num processo limpo por caso
  const r=require('child_process').spawnSync(process.execPath,['-e',`globalThis.__log=[];import(${JSON.stringify(url.pathToFileURL(path.resolve('fx',entrada)).href)}).then(()=>new Promise(r=>setTimeout(r,60))).then(()=>console.log(JSON.stringify(globalThis.__log)))`],{encoding:'utf8'});
  if(r.status!==0)throw new Error('node ref falhou: '+r.stderr);return JSON.parse(r.stdout);
}
const fxs={};for(const f of fs.readdirSync('fx'))fxs['/fx/'+f]=fs.readFileSync('fx/'+f,'utf8');
let falhas=0;
async function caso(nome,entrada){
  const ref=await nativo(entrada);
  const m=montar(`<html><body><script type="module" src="/fx/${entrada}"></script></body></html>`,fxs);
  await ate(m);
  const meu=JSON.parse(vm.runInContext('JSON.stringify(__log)',m.ctx));
  const a=JSON.stringify(ref),b=JSON.stringify(meu);
  if(a===b)console.log('ok:',nome,'=',b.slice(0,110));else{falhas++;console.log('FALHOU:',nome,'\n  nativo:',a,'\n  meu   :',b,'\n  erros :',m.erros.join(' | '))}
}
(async()=>{
 await caso('import default/nomeado/namespace/efeito + exports','basic.js');
 await caso('strings, templates aninhados, regex, comentários','tricky.js');
 await caso('export * / export {x as y} from / export * as ns','usore.js');
 await caso('import() dinâmico + import.meta.url','dyn.js');
 await caso('export com desestruturação e vários declaradores','destr.js');
 await caso('estilo sem ponto-e-vírgula + export default class','useasi.js');
 await caso('await no topo dentro de parênteses, listas, blocos e for await (padrão do ChatGPT)','tlaparen.js');
 await caso('await só dentro de funções não torna o módulo assíncrono','semtla.js');
 // importmap (especificador "nu")
 let m=montar(`<html><head><script type="importmap">{"imports":{"lib":"/fx/dep.js","pre/":"/fx/"}}</script></head><body><script type="module">import {a} from 'lib'; import d from 'pre/dep.js'; __log.push(['map',a,d]);</script></body></html>`,fxs);
 await ate(m);let l=vm.runInContext('JSON.stringify(__log)',m.ctx);
 if(l==='["dep executa",["map","A","D"]]')console.log('ok: importmap (nu e prefixo) + módulo inline');else{falhas++;console.log('FALHOU importmap',l,m.erros)}
 // ordem: script comum -> módulos -> DOMContentLoaded -> load
 m=montar(`<html><body><script type="module" src="/fx/efeito.js"></script><script>__log.push('classico');document.addEventListener('DOMContentLoaded',function(){__log.push('DCL')})</script></body></html>`,fxs);
 await ate(m);l=vm.runInContext('JSON.stringify(__log)',m.ctx);
 if(l==='["classico","efeito","DCL"]')console.log('ok: ordem clássico → módulo → DOMContentLoaded');else{falhas++;console.log('FALHOU ordem',l)}
 // módulo com erro não derruba os demais; nomodule é ignorado
 m=montar(`<html><body><script type="module" src="/fx/erro.js"></script><script type="module" src="/fx/efeito.js"></script><script nomodule>__log.push('NOMODULE')</script><script type="module" src="/fx/naoexiste.js"></script></body></html>`,fxs);
 await ate(m);l=vm.runInContext('JSON.stringify(__log)',m.ctx);
 if(l==='["efeito"]'&&m.erros.length>=2)console.log('ok: erro/404 isolados, nomodule ignorado ('+m.erros.length+' erros registrados)');else{falhas++;console.log('FALHOU isolamento',l,m.erros)}
 // módulo inserido depois (framework carregando pedaço sob demanda)
 m=montar(`<html><body><script>setTimeout(function(){var s=document.createElement('script');s.type='module';s.src='/fx/efeito.js';document.body.appendChild(s)},50)</script></body></html>`,fxs);
 await ate(m,1500);await esperar(200);l=vm.runInContext('JSON.stringify(__log)',m.ctx);
 if(l==='["efeito"]')console.log('ok: módulo inserido dinamicamente');else{falhas++;console.log('FALHOU dinâmico',l,m.erros)}
 console.log(falhas?'FALHAS: '+falhas:'TUDO OK (módulos)');process.exit(falhas?1:0);
})();
