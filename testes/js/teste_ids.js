// confere corretude do índice de ids contra a busca ingênua, com mutações aleatórias
const vm=require('vm'),fs=require('fs');
const base=fs.readFileSync('teste.js','utf8');eval(base.slice(base.indexOf('function parse(h)'),base.indexOf('function rodar(')));
const ctx=vm.createContext({});ctx.__parse=h=>JSON.stringify(parse(h));ctx.__erro=()=>{};ctx.__fim=()=>{};ctx.__acordar=()=>{};ctx.__aviso=()=>{};
ctx.__pagina={href:'https://x.com/',protocolo:'https:',host:'x.com',agente:'UA',plataforma:'iPhone',toque:true,largura:375,altura:812,escala:2,escuro:false};ctx.__pedir=()=>{};
vm.runInContext(fs.readFileSync('ambiente.js','utf8'),ctx);ctx.__iniciar(JSON.stringify(parse('<html><body><div id="r"></div></body></html>')));
const r=vm.runInContext(`
(function(){function rnd(n){return Math.floor(Math.random()*n)}
 var raiz=document.getElementById('r'),els=[],erros=0,ops=0;
 function ingenuo(id){var a=document.querySelectorAll('[id="'+id+'"]');return a[0]||null}
 for(var it=0;it<4000;it++){var op=rnd(8);
  if(op<2){var e=document.createElement('div');if(rnd(3))e.id='k'+rnd(40);(els.length&&rnd(2)?els[rnd(els.length)]:raiz).appendChild(e);els.push(e)}
  else if(op===2&&els.length){var e=els[rnd(els.length)];e.id='k'+rnd(40)}
  else if(op===3&&els.length){var e=els[rnd(els.length)];e.removeAttribute('id')}
  else if(op===4&&els.length){var e=els.splice(rnd(els.length),1)[0];if(e.parentNode)e.parentNode.removeChild(e)}
  else if(op===5){raiz.innerHTML='';els=[]}
  else {var id='k'+rnd(45);var a=document.getElementById(id),b=ingenuo(id);ops++;if(a!==b){ // duplicados: aceita qualquer um dos que têm o id
     var todos=document.querySelectorAll('[id="'+id+'"]');var ok=a&&todos.indexOf(a)>=0;if(!ok&&!(a===null&&b===null)){erros++}}}
 } return ops+' consultas, '+erros+' divergências'})()`,ctx);
console.log(r);
