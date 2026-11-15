const vm=require('vm'),fs=require('fs');
const base=fs.readFileSync('teste.js','utf8');
// reaproveita o mini parser do teste existente
const parseSrc=base.slice(base.indexOf('function parse(h)'),base.indexOf('function rodar('));
eval(parseSrc);
function montar(html,externos={},opts={}){
  const erros=[],reqs=[],eventos={acordar:[],aviso:0,fim:false};
  const ctx=vm.createContext({});
  ctx.__parse=h=>JSON.stringify(parse(h));
  ctx.__erro=m=>erros.push(m);
  ctx.__fim=()=>{eventos.fim=true};
  ctx.__acordar=ms=>{eventos.acordar.push(ms); clearTimeout(eventos.t); eventos.t=setTimeout(()=>{try{ctx.__tick()}catch(e){erros.push('tick '+e)}},ms)};
  ctx.__aviso=()=>{eventos.aviso++};
  ctx.__pagina={href:'https://exemplo.com/a/b',protocolo:'https:',host:'exemplo.com',agente:'UA',plataforma:'iPhone',toque:true,largura:375,altura:812,escala:2,escuro:false,vivo:true,bloquear:true,...opts};
  ctx.__pedir=(id,url,m,cab,corpo)=>{reqs.push({id,url,t:Date.now()});
    setTimeout(()=>{ if(url in externos){const r=externos[url];vm.runInContext(`__resposta(${id},${r.status||200},"{}",${JSON.stringify(r.texto)},"")`,ctx)} else vm.runInContext(`__resposta(${id},404,"{}","","")`,ctx)},(externos[url]||{}).atraso||1)};
  vm.runInContext(fs.readFileSync('ambiente.js','utf8'),ctx);
  ctx.__iniciar(JSON.stringify(parse(html)));
  return {ctx,erros,reqs,eventos};
}
const esperar=ms=>new Promise(r=>setTimeout(r,ms));
async function fimBoot(m){for(let i=0;i<400&&!m.eventos.fim;i++)await esperar(5);return m.eventos.fim}
let falhas=0;const ok=(c,msg)=>{if(!c){falhas++;console.log('FALHOU:',msg)}else console.log('ok:',msg)};
(async()=>{
 // 1. pré-carga paralela: os 3 pedidos saem antes de qualquer resposta
 let m=montar(`<html><head><script src="/a.js"></script><script src="/b.js"></script></head><body><script src="/c.js"></script></body></html>`,
   {'https://exemplo.com/a.js':{texto:'window.o=[1]'},'https://exemplo.com/b.js':{texto:'o.push(2)'},'https://exemplo.com/c.js':{texto:'o.push(3)'}});
 ok(m.reqs.length===3,'3 scripts pedidos em paralelo no início ('+m.reqs.length+')');
 await fimBoot(m); ok(m.ctx.o.join()==='1,2,3','execução segue na ordem: '+m.ctx.o);
 // 2. rastreadores bloqueados
 m=montar(`<html><body><script src="https://www.googletagmanager.com/gtm.js"></script><script src="https://cdn.site.com/x.js"></script><script>fetch('https://www.google-analytics.com/collect').then(r=>{window.st=r.status})</script></body></html>`,
   {'https://cdn.site.com/x.js':{texto:'window.x=1'}});
 await fimBoot(m);
 ok(!m.reqs.some(r=>/googletag|google-analytics/.test(r.url)),'nenhum pedido a rastreador');
 ok(m.ctx.x===1,'script normal roda'); ok(m.ctx.st===204,'fetch bloqueado responde 204 ('+m.ctx.st+')');
 ok(JSON.parse(m.ctx.__estatisticas()).bloqueados===2,'contagem de bloqueados');
 // 2b. sem bloqueio quando desligado
 m=montar(`<html><body><script src="https://www.googletagmanager.com/gtm.js"></script></body></html>`,{},{bloquear:false});
 ok(m.reqs.length===1,'bloqueio desligado deixa passar');
 // 3. modo vivo: setInterval e setTimeout longo continuam depois do boot
 m=montar(`<html><body><p id="c">0</p><script>var n=0;setInterval(function(){n++;document.getElementById('c').textContent=String(n)},150);setTimeout(function(){window.longo=1},12000);</script></body></html>`);
 await fimBoot(m); ok(m.eventos.fim,'boot termina mesmo com intervalo e timer longo');
 const n0=m.ctx.n; ok(n0===10,'intervalo roda 10x virtual no boot ('+n0+')');
 m.ctx.__vivo(); const ac=m.eventos.acordar[m.eventos.acordar.length-1];
 ok(ac>=0&&ac<=200,'despertador armado para o próximo intervalo ('+ac+'ms)');
 await esperar(700);
 ok(m.ctx.n>n0+2,'intervalo continua em tempo real ('+n0+' -> '+m.ctx.n+')');
 ok(m.eventos.aviso>=1,'avisa nativo quando o DOM muda');
 let h=m.ctx.__coletar(); ok(h&&h.includes('<p id="c">'+m.ctx.n),'coletar devolve HTML novo');
 ok(m.ctx.__coletar()===null,'sem mudança, coletar devolve null');
 ok(m.ctx.longo===undefined,'timer de 12s ainda não disparou');
 m.ctx.__pausar(); const antes=m.ctx.n; await esperar(400); ok(m.ctx.n===antes,'pausado: nada roda');
 m.ctx.__retomar(); await esperar(400); ok(m.ctx.n>antes,'retomado: volta a rodar');
 // 4. clique em botão com listener, onclick em atributo, delegação
 m=montar(`<html><body><button id="b">ok</button><div id="d" onclick="this.setAttribute('x','1')">div</div><span id="s">sem</span><ul id="l"><li id="i1">um</li></ul><a id="lk" href="/pag?x=1&y=2">link</a><a id="ext" href="https://outro.com/z">ext</a>
  <script>document.getElementById('b').addEventListener('click',function(){document.getElementById('b').textContent='clicado'});
  document.getElementById('l').addEventListener('click',function(e){var li=e.target.closest('li'); if(li) li.textContent='delegado'});
  document.getElementById('ext').addEventListener('click',function(e){e.preventDefault();window.cancelou=1});</script></body></html>`);
 await fimBoot(m); m.ctx.__vivo();
 const html=m.ctx.__serializar();
 const id=(re)=>{const x=re.exec(html);return x&&x[1]};
 console.log(html.replace(/<script>[\s\S]*?<\/script>/,''));
 ok(/<button[^>]*data-nusky-js="nusky-js:\d+\|"/.test(html),'botão com listener é marcado');
 ok(/<div id="d"[^>]*data-nusky-js/.test(html),'onclick em atributo é marcado');
 ok(!/<span id="s"[^>]*data-nusky-js/.test(html),'span sem clique não é marcado');
 const lid1=/<li id="i1"[^>]*nusky-js:(\d+)/.exec(html); if(lid1){m.ctx.__tocar(+lid1[1]); ok(m.ctx.__serializar().includes('delegado'),'toque no li chega com alvo li (delegação)');}
 ok(/<li id="i1"[^>]*data-nusky-js/.test(html),'filho de elemento com listener (delegação) com marca? '+ /<li id="i1"[^>]*>/.exec(html));
 const bid=/<button[^>]*data-nusky-js="nusky-js:(\d+)\|"/.exec(html)[1];
 let r=JSON.parse(m.ctx.__tocar(+bid)); ok(r.ok===1&&r.href==='','tocar botão ok');
 await esperar(60); h=m.ctx.__coletar(); ok(h&&h.includes('clicado'),'clique mudou o DOM e coletar vê');
 const did=/<div id="d"[^>]*data-nusky-js="nusky-js:(\d+)\|"/.exec(html)[1];
 m.ctx.__tocar(+did); ok(/<div id="d"[^>]*x="1"/.test(m.ctx.__serializar()),'onclick em atributo executou');
 // link: com ouvinte que cancela => sem navegação; sem cancelar => href
 const eid=/id="ext"[^>]*data-nusky-js="nusky-js:(\d+)\|https:\/\/outro.com\/z"/.exec(html); ok(!!eid,'a com listener marcado com href');
 r=JSON.parse(m.ctx.__tocar(+eid[1])); ok(m.ctx.cancelou===1&&r.href==='','preventDefault cancela navegação');
 // 5. delegação em document: todo <a> passa pelo JS e devolve o href resolvido
 m=montar(`<html><body><a id="lk" href="/pag?x=1&y=2">link</a><a href="#topo" id="an">âncora</a><script>document.addEventListener('click',function(e){window.vistos=(window.vistos||0)+1})</script></body></html>`);
 await fimBoot(m); m.ctx.__vivo();
 const h2=m.ctx.__serializar(); console.log(h2.replace(/<script>[\s\S]*?<\/script>/,''));
 const lid=/id="lk"[^>]*data-nusky-js="nusky-js:(\d+)\|https:\/\/exemplo.com\/pag\?x=1&amp;y=2"/.exec(h2); ok(!!lid,'a ganha marca com href absoluto sob delegação');
 ok(!/id="an"[^>]*data-nusky-js/.test(h2),'âncora #topo não é marcada');
 r=JSON.parse(m.ctx.__tocar(+lid[1])); ok(m.ctx.vistos===1&&r.href==='https://exemplo.com/pag?x=1&y=2','delegado viu o clique e href volta para navegar');
 // 6. checkbox/label e details
 m=montar(`<html><body><label id="lb" for="c1">x</label><input type="checkbox" id="c1"><details id="dt"><summary id="sm">t</summary>c</details><script>window.ch=0;document.getElementById('c1').addEventListener('change',function(){window.ch++})</script></body></html>`);
 await fimBoot(m); m.ctx.__vivo(); const h3=m.ctx.__serializar();
 const lb=/id="lb"[^>]*nusky-js:(\d+)/.exec(h3)[1], sm=/id="sm"[^>]*nusky-js:(\d+)/.exec(h3)[1];
 m.ctx.__tocar(+lb); ok(m.ctx.ch===1&&m.ctx.document.getElementById('c1').checked===true,'label alterna checkbox e dispara change');
 m.ctx.__tocar(+sm); ok(/<details id="dt" open/.test(m.ctx.__serializar()),'summary abre details');
 // 7. toque em elemento removido não quebra
 ok(JSON.parse(m.ctx.__tocar(99999)).ok===0,'id desconhecido devolve ok:0');
 console.log(m.erros.length?('ERROS: '+m.erros.join(' | ')):'sem erros JS');
 console.log(falhas?('FALHAS: '+falhas):'TUDO OK (vivo)'); process.exit(falhas?1:0);
})();
