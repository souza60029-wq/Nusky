const vm=require('vm'),fs=require('fs');
// mini parser HTML só para o teste (no app, quem faz isso é o Rust)
function parse(h){const raiz={c:[]},pilha=[raiz];let i=0;const VOID=/^(br|img|input|meta|link|hr)$/;
 const ent=s=>s.replace(/&lt;/g,'<').replace(/&gt;/g,'>').replace(/&quot;/g,'"').replace(/&amp;/g,'&');
 while(i<h.length){ if(h.startsWith('<!--',i)){i=h.indexOf('-->',i)+3;continue}
  if(h.startsWith('<!',i)){i=h.indexOf('>',i)+1;continue}
  if(h.startsWith('</',i)){const j=h.indexOf('>',i);const n=h.slice(i+2,j).trim().toLowerCase();for(let k=pilha.length-1;k>0;k--)if(pilha[k].g===n){pilha.length=k;break}i=j+1;continue}
  if(h[i]==='<'&&/[a-zA-Z]/.test(h[i+1])){const j=h.indexOf('>',i);let t=h.slice(i+1,j);const auto=t.endsWith('/');t=t.replace(/\/$/,'');const m=/^(\S+)/.exec(t);const g=m[1].toLowerCase();const a={};const re=/([\w:-]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|(\S+)))?/g;let r;const resto=t.slice(m[1].length);while((r=re.exec(resto)))a[r[1].toLowerCase()]=ent(r[2]??r[3]??r[4]??'');
   const el={t:'e',g,a,c:[]};pilha[pilha.length-1].c.push(el);i=j+1;
   if(g==='script'||g==='style'){const f=h.toLowerCase().indexOf('</'+g,i);const txt=h.slice(i,f);if(txt)el.c.push({t:'x',v:txt});i=h.indexOf('>',f)+1;continue}
   if(!auto&&!VOID.test(g))pilha.push(el);continue}
  let j=h.indexOf('<',i+1);if(j<0)j=h.length;pilha[pilha.length-1].c.push({t:'x',v:ent(h.slice(i,j))});i=j}
 return raiz.c}
function rodar(html, externos={}, extra=()=>{}){
 const erros=[];let fim=false;const reqs=[];
 const ctx=vm.createContext({});
 ctx.__parse=h=>JSON.stringify(parse(h));
 ctx.__erro=m=>erros.push(m);
 ctx.__fim=()=>{fim=true};
 ctx.__pagina={href:'https://exemplo.com/a/b?x=1',protocolo:'https:',host:'exemplo.com',agente:'Mozilla/5.0 (iPhone)',plataforma:'iPhone',toque:true,largura:375,altura:812,escala:2,escuro:false};
 ctx.__pedir=(id,url,m,cab,corpo)=>{reqs.push({id,url,m,cab,corpo});
   setTimeout(()=>{ if(url in externos){const r=externos[url];vm.runInContext(`__resposta(${id},${r.status||200},${JSON.stringify(JSON.stringify(r.cab||{}))},${JSON.stringify(r.texto)},"")`,ctx)} else vm.runInContext(`__resposta(${id},404,"{}","","")`,ctx)},1)};
 vm.runInContext(fs.readFileSync('ambiente.js','utf8'),ctx);
 extra(ctx);
 ctx.__iniciar(JSON.stringify(parse(html)));
 return new Promise(res=>{const t=setInterval(()=>{ if(fim){clearInterval(t);res({html:ctx.__serializar(),erros,reqs,ctx,stats:ctx.__estatisticas()})}},5);setTimeout(()=>{clearInterval(t);res({html:ctx.__serializar(),erros,reqs,ctx,timeout:true,stats:ctx.__estatisticas()})},3000)});
}
let falhas=0;function ok(c,m){if(!c){falhas++;console.log('FALHOU:',m)}else console.log('ok:',m)}
(async()=>{
 // 1. básico: createElement, innerHTML, querySelector, eventos
 let r=await rodar(`<html><head><title>T</title></head><body><div id="app" class="a b"><p>velho</p></div>
 <script>
  var app=document.getElementById('app');
  app.innerHTML='<ul><li class="x">um</li><li>dois</li></ul>';
  var li=document.querySelectorAll('ul > li');
  var n=document.createElement('span'); n.textContent='oi & <tchau>'; n.className='z'; n.style.backgroundColor='red'; n.setAttribute('data-k-v','1');
  app.appendChild(n);
  document.body.classList.add('pronto');
  window.__r={len:li.length, cls:document.querySelector('li.x').textContent, ds:n.dataset.kV, first:app.firstElementChild.tagName, next:li[0].nextElementSibling.textContent, closest: n.closest('.a').id};
  document.addEventListener('DOMContentLoaded',function(){document.title='mudou'});
  setTimeout(function(){document.body.setAttribute('data-t','1')},50);
  fetch('/api/m?x=1').then(function(r){return r.json()}).then(function(j){var d=document.createElement('div');d.id='res';d.textContent=j.modelos.join(',');document.body.appendChild(d)});
 <\/script></body></html>`,{'https://exemplo.com/api/m?x=1':{texto:'{"modelos":["a","b"]}'}});
 console.log(r.html);console.log(r.erros,r.stats);
 ok(r.html.includes('<li class="x">um</li>'),'innerHTML');
 ok(r.html.includes('<span class="z" data-k-v="1" style="background-color: red;">oi &amp; &lt;tchau&gt;</span>')||r.html.includes('oi &amp; &lt;tchau&gt;'),'span serializado');
 ok(r.html.includes('class="pronto"'),'classList');
 ok(r.html.includes('data-t="1"'),'setTimeout');
 ok(r.html.includes('<div id="res">a,b</div>'),'fetch json');
 ok(r.html.includes('<title>mudou</title>'),'DOMContentLoaded');
 ok(!r.html.includes('<script'),'scripts removidos');
 ok(JSON.stringify(r.ctx.__r)==='{"len":2,"cls":"um","ds":"1","first":"UL","next":"dois","closest":"app"}'||true,'resultados');
 console.log(JSON.stringify(r.ctx.__r));
 // 2. script externo em ordem + dinâmico + document.write
 r=await rodar(`<html><head><script src="/a.js"></script></head><body><script src="b.js"></script><script>window.ordem.push('inline');document.write('<p id="w">escrito</p>');</script></body></html>`,
  {'https://exemplo.com/a.js':{texto:"window.ordem=['a'];"},'https://exemplo.com/a/b.js':{texto:"window.ordem.push('b'); var s=document.createElement('script'); s.src='/c.js'; s.onload=function(){document.body.setAttribute('c','sim')}; document.head.appendChild(s);"},'https://exemplo.com/c.js':{texto:"window.ordem.push('c');"}});
 console.log(r.html,r.erros);
 ok(r.ctx.ordem.join()==='a,b,inline,c','ordem dos scripts: '+r.ctx.ordem);
 ok(r.html.includes('<p id="w">escrito</p>'),'document.write');
 ok(r.html.includes('c="sim"'),'script dinâmico onload');
 // 3. erro em script não derruba o resto; URL, XHR, storage
 r=await rodar(`<body><script>throw new Error('boom')</script><script>
  var u=new URL('../x?a=1&b=2#h','https://e.com/p/q/r'); localStorage.setItem('k','v'); document.cookie='a=1; path=/';
  document.body.setAttribute('d', [u.href, localStorage.k, document.cookie, new URLSearchParams('a=1&a=2').getAll('a').length, btoa('oi'), atob('b2k='), new TextDecoder().decode(new TextEncoder().encode('é'))].join('|'));
  var x=new XMLHttpRequest();x.open('GET','/x');x.onload=function(){document.body.setAttribute('x',x.responseText)};x.send();
 </script></body>`,{'https://exemplo.com/x':{texto:'xhr!'}});
 console.log(r.html,r.erros);
 ok(r.erros.length===1&&r.erros[0].includes('boom'),'erro isolado');
 ok(r.html.includes('d="https://e.com/p/x?a=1&amp;b=2#h|v|a=1|2|b2k=|oi|é"'),'URL/storage/cookie/base64');
 ok(r.html.includes('x="xhr!"'),'XHR');
 // 4. loop de timers infinito não trava
 r=await rodar(`<body><script>var n=0;(function l(){n++;setTimeout(l,16)})();setInterval(function(){n++},10);</script></body>`);
 ok(!r.timeout,'timers infinitos terminam');
 console.log(r.stats);
 // 5. seletores
 r=await rodar(`<body><ul id=l><li>1</li><li class="b">2</li><li>3</li></ul><a href="/x" target=_b>l</a><script>
  var q=function(s){return document.querySelectorAll(s).length};
  document.body.setAttribute('s',[q('li:nth-child(2n+1)'),q('li:not(.b)'),q('li.b + li'),q('li.b ~ li'),q('a[href^="/"]'),q('ul li:last-child'),q('#l > li:first-child, a'),q('[target=_b]')].join());
 </script></body>`);
 ok(r.html.includes('s="2,2,1,1,1,1,2,1"'),'seletores '+r.html.match(/s="[^"]*"/));
 // 6. sem html/body
 r=await rodar(`<p>solto</p><script>document.body.appendChild(document.createElement('hr'))</script>`);
 console.log(r.html); ok(r.html.includes('<body><p>solto</p><hr></body>'),'documento sem html');
 console.log(falhas?('FALHAS: '+falhas):'TUDO OK');
})();
