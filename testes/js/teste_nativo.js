const vm=require('vm'),fs=require('fs');
const base=fs.readFileSync('teste.js','utf8');eval(base.slice(base.indexOf('function parse(h)'),base.indexOf('function rodar(')));
function montar(html,externos){
  const erros=[],guardados=new Map(),reqs=[],ev={fim:false,avaliados:[]};const ctx=vm.createContext({});
  ctx.__parse=h=>JSON.stringify(parse(h));ctx.__erro=m=>erros.push(m);ctx.__fim=()=>{ev.fim=true};ctx.__acordar=()=>{};ctx.__aviso=()=>{};
  ctx.__pagina={href:'https://site.com/',protocolo:'https:',host:'site.com',agente:'UA',plataforma:'iPhone',toque:true,largura:375,altura:812,escala:2,escuro:false};
  const aval=(o,c)=>{ev.avaliados.push(o);try{vm.runInContext(c,ctx,{filename:o});return ''}catch(e){return o+': '+(e&&e.message)}};
  ctx.__avaliar=aval;
  ctx.__avaliarGuardado=u=>{const t=guardados.get(u);return t===undefined?'ausente: '+u:aval(u,t)};
  ctx.__pedir=(id,u,m,cab,corpo,guardar)=>{reqs.push({u,guardar});const k=u.replace('https://site.com','');setTimeout(()=>{const t=externos[k];
    if(t===undefined)return vm.runInContext(`__resposta(${id},404,"{}","","")`,ctx);
    if(guardar){guardados.set(u,t);vm.runInContext(`__resposta(${id},200,"{}","","")`,ctx)}
    else vm.runInContext(`__resposta(${id},200,"{}",${JSON.stringify(t)},"")`,ctx)},Math.random()*6)};
  vm.runInContext(fs.readFileSync(process.argv[2]||'ambiente.js','utf8'),ctx);ctx.__iniciar(JSON.stringify(parse(html)));return {ctx,erros,ev,reqs};
}
const esperar=ms=>new Promise(r=>setTimeout(r,ms));
let falhas=0;const ok=(c,m)=>{if(!c){falhas++;console.log('FALHOU:',m)}else console.log('ok:',m)};
(async()=>{
 // 1. let/const/class compartilhados entre inline e externo (o bug confirmado antes)
 let m=montar(`<html><body><script>const app={n:41}; let fila=[]; class W{x(){return 1}}</script><script src="/a.js"></script><script>window.r3=typeof app+'/'+typeof W+'/'+app.n</script></body></html>`,
   {'/a.js':'window.r2=typeof app+"/"+typeof fila+"/"+typeof W; app.n++; const soDoExterno=7;'});
 await esperar(120);
 ok(m.ctx.r2==='object/object/function','script externo enxerga const/let/class do inline ('+m.ctx.r2+')');
 ok(m.ctx.r3==='object/function/42','inline seguinte enxerga as alterações ('+m.ctx.r3+')');
 ok(m.reqs.every(r=>r.guardar===true),'externos pedidos em modo guardar (texto fica no nativo)');
 // 2. erro de sintaxe em externo vira mensagem, não derruba o resto
 m=montar(`<html><body><script src="/ruim.js"></script><script src="/bom.js"></script></body></html>`,{'/ruim.js':'var x = ;','/bom.js':'window.bom=1'});
 await esperar(120);
 ok(m.ctx.bom===1&&m.erros.some(e=>/ruim\.js/.test(e)),'erro isolado e reportado: '+m.erros[0]);
 // 3. ordem preservada com respostas fora de ordem
 m=montar(`<html><body><script src="/1.js"></script><script src="/2.js"></script><script src="/3.js"></script></body></html>`,{'/1.js':'window.o=[1]','/2.js':'o.push(2)','/3.js':'o.push(3)'});
 await esperar(150);ok(m.ctx.o.join()==='1,2,3','ordem 1,2,3 mesmo com downloads em paralelo');
 // 4. script inserido dinamicamente também usa o escopo global
 m=montar(`<html><body><script>const base=10;setTimeout(function(){var s=document.createElement('script');s.src='/d.js';document.body.appendChild(s)},20)</script></body></html>`,{'/d.js':'window.dd=base*2'});
 await esperar(200);ok(m.ctx.dd===20,'script dinâmico enxerga const do topo');
 // 5. módulo + clássico com escopo global ainda ok
 m=montar(`<html><body><script>var g1=5</script><script type="module">window.mm=g1+1</script></body></html>`,{});
 await esperar(120);ok(m.ctx.mm===6,'módulo enxerga globais var');
 console.log(falhas?'FALHAS: '+falhas:'TUDO OK (nativo)');process.exit(falhas?1:0);
})();
