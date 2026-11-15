const vm=require('vm'),fs=require('fs');
const base=fs.readFileSync('teste.js','utf8');
eval(base.slice(base.indexOf('function parse(h)'),base.indexOf('function rodar(')));
const arq=process.argv[2]||'ambiente.js';
function nova(html){
  const ctx=vm.createContext({console});
  ctx.__parse=h=>JSON.stringify(parse(h)); ctx.__erro=m=>{}; ctx.__fim=()=>{}; ctx.__acordar=()=>{}; ctx.__aviso=()=>{};
  ctx.__pagina={href:'https://x.com/',protocolo:'https:',host:'x.com',agente:'UA',plataforma:'iPhone',toque:true,largura:375,altura:812,escala:2,escuro:false};
  ctx.__pedir=()=>{};
  vm.runInContext(fs.readFileSync(arq,'utf8'),ctx);
  ctx.__iniciar(JSON.stringify(parse(html)));
  return ctx;
}
function t(nome,fn){const a=process.hrtime.bigint();fn();const b=process.hrtime.bigint();console.log(nome.padEnd(46),(Number(b-a)/1e6).toFixed(1)+' ms')}
const ctx=nova('<html><body><ul id="l"></ul><div id="app"></div></body></html>');
const run=s=>vm.runInContext(s,ctx);
t('1. 5000 createElement+appendChild (conectado)',()=>run(`var ul=document.getElementById('l');for(var i=0;i<5000;i++){var li=document.createElement('li');li.id='i'+i;li.className='x';li.textContent='item '+i;ul.appendChild(li)}`));
t('2. 5000 getElementById (ids diferentes)',()=>run(`for(var i=0;i<5000;i++)document.getElementById('i'+i)`));
t('3. 5000 getElementById (mesmo id, 2º elemento)',()=>run(`for(var i=0;i<5000;i++)document.getElementById('i4000')`));
t('4. nextSibling percorrendo 5000 filhos',()=>run(`var c=ul.firstChild,n=0;while(c){n++;c=c.nextSibling}`));
t('5. querySelectorAll(".x") x50',()=>run(`for(var i=0;i<50;i++)document.querySelectorAll('.x')`));
t('6. removeChild do início x2000',()=>run(`for(var i=0;i<2000;i++)ul.removeChild(ul.firstChild)`));
t('7. insertBefore no meio x1000',()=>run(`for(var i=0;i<1000;i++){var e=document.createElement('li');ul.insertBefore(e,ul.childNodes[1500])}`));
t('8. innerHTML 2000 nós',()=>run(`var h='';for(var i=0;i<2000;i++)h+='<li class="a"><span>t'+i+'</span></li>';document.getElementById('app').innerHTML=h`));
t('9. firstElementChild/childElementCount x3000',()=>run(`for(var i=0;i<3000;i++){ul.firstElementChild;ul.childElementCount}`));
t('10. serializar documento (~9k nós)',()=>{for(let i=0;i<5;i++)ctx.__serializar()});
t('11. setAttribute x20000',()=>run(`var f=ul.firstChild;for(var i=0;i<20000;i++)f.setAttribute('data-a',i)`));
t('12. classList.add/remove x5000',()=>run(`var f=ul.childNodes[10];for(var i=0;i<5000;i++){f.classList.add('k'+(i%5));f.classList.remove('k'+((i+2)%5))}`));
t('13. style.color=... x5000',()=>run(`var f=ul.childNodes[10];for(var i=0;i<5000;i++){f.style.color='rgb('+(i%255)+',0,0)'}`));
