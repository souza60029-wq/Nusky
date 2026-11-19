const vm=require('vm'),fs=require('fs'),nodecrypto=require('crypto');
const base=fs.readFileSync('teste.js','utf8');eval(base.slice(base.indexOf('function parse(h)'),base.indexOf('function rodar(')));
function nova(opts={},externos={}){
  const erros=[];const ctx=vm.createContext({});
  ctx.__parse=h=>JSON.stringify(parse(h));ctx.__erro=m=>erros.push(m);ctx.__fim=()=>{};let tm;ctx.__acordar=ms=>{clearTimeout(tm);tm=setTimeout(()=>{try{ctx.__tick()}catch(e){}},ms)};ctx.__aviso=()=>{};
  ctx.__pagina={href:'https://site.com/',protocolo:'https:',host:'site.com',agente:'UA',plataforma:'iPhone',toque:true,largura:375,altura:812,escala:2,escuro:false,...opts};
  ctx.__pedir=(id,u)=>{setTimeout(()=>{const t=externos[u.replace('https://site.com','')];vm.runInContext(t===undefined?`__resposta(${id},404,"{}","","")`:`__resposta(${id},200,"{}",${JSON.stringify(t)},"")`,ctx)},1)};
  vm.runInContext(fs.readFileSync('ambiente.js','utf8'),ctx);
  vm.runInContext(fs.readFileSync('extra.js','utf8'),ctx);
  ctx.__iniciar(JSON.stringify(parse('<html><body><div id="a"><p>um</p><span>dois</span>texto</div></body></html>')));
  ctx.__vivo();   // como o app faz depois da primeira exibição: temporizadores em tempo real
  return {ctx,erros};
}
const esperar=ms=>new Promise(r=>setTimeout(r,ms));
let falhas=0;const ok=(c,m)=>{if(!c){falhas++;console.log('FALHOU:',m)}else console.log('ok:',m)};
const ev=(c,s)=>vm.runInContext(s,c);
(async()=>{
 const {ctx,erros}=nova();
 // 1. nada do que faltava continua faltando (exceto o que deve faltar de propósito)
 const devem='MessageChannel MessagePort BroadcastChannel FileReader indexedDB Notification customElements XMLSerializer Audio WheelEvent UIEvent PromiseRejectionEvent Range Selection DOMRect DOMRectReadOnly NodeFilter TreeWalker NodeList HTMLCollection DOMTokenList CSSStyleDeclaration isSecureContext origin ReadableStream WritableStream TransformStream TextDecoderStream TextEncoderStream'.split(' ');
 const faltam=devem.filter(k=>ev(ctx,'typeof '+k)==='undefined');
 ok(faltam.length===0,'todos os recursos que faltavam agora existem'+(faltam.length?': '+faltam:''));
 ok(ev(ctx,'typeof navigator.geolocation')==='object'&&ev(ctx,'typeof crypto.subtle.digest')==='function','geolocation e crypto.subtle.digest');
 // 2. CSS.supports
 const sup=(q)=>ev(ctx,`CSS.supports(${JSON.stringify(q)})`);
 const casos=[['display:grid',true],['(display: grid)',true],['(display: grid) and (gap: 1px)',true],['not (display: grid)',false],['(display:grid) or (foo-bar:1)',true],
  ['selector(:has(*))',true],['(container-type: inline-size)',false],['(color: color-mix(in srgb, red, blue))',false],['(backdrop-filter: blur(1px)) and (not (text-wrap: balance))',true],['not (text-wrap: balance)',true],['(-webkit-touch-callout: none)',true],['selector(:popover-open)',false]];
 let bad=casos.filter(([q,e])=>sup(q)!==e).map(([q,e])=>q+' esperava '+e);
 bad=bad.concat(ev(ctx,"CSS.supports('display','grid')")!==true?['2 args']:[],ev(ctx,"CSS.supports('container-type','inline-size')")!==false?['2 args container']:[]);
 ok(bad.length===0,'CSS.supports ('+casos.length+' casos)'+(bad.length?': '+bad.join(' | '):''));
 // 3. matchMedia (mesma tabela dos testes do Rust)
 const mm=(q,c=ctx)=>ev(c,`matchMedia(${JSON.stringify(q)}).matches`);
 const tab=[['(orientation: portrait)',true],['(orientation: landscape)',false],['(hover: hover)',false],['(hover: none) and (pointer: coarse)',true],['(min-resolution: 2dppx)',true],['(-webkit-min-device-pixel-ratio: 3)',false],
  ['(prefers-reduced-motion: reduce)',false],['(min-width: 300px) and (hover: none)',true],['(foo: bar)',false],['(width >= 40rem)',false],['(width < 640px)',true],['(width<640px)',true],['(300px <= width <= 400px)',true],['(400px <= width <= 700px)',false],
  ['(prefers-color-scheme: light)',true],['(prefers-color-scheme: dark)',false],['screen and (max-width: 600px)',true],['print',false],['not all and (min-width: 600px)',true],['(min-width: 1000px), (max-width: 400px)',true],['only screen and (max-width:374px)',false],['(min-aspect-ratio: 1/2)',true],['(max-aspect-ratio: 1/2)',false],['(display-mode: browser)',true],['(any-hover: none)',true]];
 bad=tab.filter(([q,e])=>mm(q)!==e).map(([q,e])=>q+' esperava '+e);
 ok(bad.length===0,'matchMedia ('+tab.length+' casos, iguais ao motor)'+(bad.length?': '+bad.join(' | '):''));
 const esc=nova({escuro:true}).ctx;
 ok(mm('(prefers-color-scheme: dark)',esc)===true&&mm('(prefers-color-scheme: light)',esc)===false,'matchMedia segue o tema escuro');
 // 4. streams
 let r=await ev(ctx,`(async()=>{var s=new ReadableStream({start(c){c.enqueue(1);c.enqueue(2);c.close()}});var rd=s.getReader(),o=[];for(;;){var x=await rd.read();if(x.done)break;o.push(x.value)}return o.join()+'|'+s.locked})()`);
 ok(r==='1,2|true','ReadableStream: ordem, close e locked ('+r+')');
 r=await ev(ctx,`(async()=>{var n=0;var s=new ReadableStream({pull(c){n++;if(n>3)c.close();else c.enqueue('p'+n)}});var o=[];for await(var v of s)o.push(v);return o.join()})()`);
 ok(r==='p1,p2,p3','ReadableStream com pull + for await ('+r+')');
 r=await ev(ctx,`(async()=>{var s=new ReadableStream({start(c){c.enqueue(new TextEncoder().encode('olá, '));c.enqueue(new TextEncoder().encode('mundo'));c.close()}}).pipeThrough(new TextDecoderStream());var o='';var rd=s.getReader();for(;;){var x=await rd.read();if(x.done)break;o+=x.value}return o})()`);
 ok(r==='olá, mundo','pipeThrough(TextDecoderStream) ('+r+')');
 r=await ev(ctx,`(async()=>{var s=new ReadableStream({start(c){c.enqueue('a');c.enqueue('b');c.close()}});var t=s.tee();async function ler(x){var o='',rd=x.getReader();for(;;){var y=await rd.read();if(y.done)break;o+=y.value}return o}return (await ler(t[0]))+(await ler(t[1]))})()`);
 ok(r==='abab','tee() ('+r+')');
 r=await ev(ctx,`(async()=>{var s=new ReadableStream({start(c){c.error(new Error('boom'))}});try{await s.getReader().read();return 'sem erro'}catch(e){return e.message}})()`);
 ok(r==='boom','erro no stream rejeita a leitura');
 r=await ev(ctx,`(async()=>{var t=new TransformStream({transform(c,k){k.enqueue(c*2)}});var w=t.writable.getWriter();w.write(2);w.write(5);w.close();var rd=t.readable.getReader(),o=[];for(;;){var x=await rd.read();if(x.done)break;o.push(x.value)}return o.join()})()`);
 ok(r==='4,10','TransformStream('+r+')');
 r=await ev(ctx,`(async()=>{var got=[];var ws=new WritableStream({write(c){got.push(c)}});await new ReadableStream({start(c){c.enqueue('x');c.enqueue('y');c.close()}}).pipeTo(ws);return got.join()})()`);
 ok(r==='x,y','pipeTo(WritableStream)');
 // fetch: response.body é um stream
 const m2=nova({},{'/dados':'{"ok":true,"n":42}'});
 r=await ev(m2.ctx,`(async()=>{var res=await fetch('/dados');var rd=res.body.getReader();var x=await rd.read();var t=new TextDecoder().decode(x.value);var y=await rd.read();return t+'|'+y.done})()`);
 ok(r==='{"ok":true,"n":42}|true','fetch().body é ReadableStream legível ('+r+')');
 // 5. mensagens e elementos personalizados
 r=await ev(ctx,`new Promise(function(ok){var c=new MessageChannel();c.port1.onmessage=function(e){ok('recebeu '+e.data)};c.port2.postMessage('oi')})`);
 ok(r==='recebeu oi','MessageChannel entrega a mensagem');
 r=await ev(ctx,`new Promise(function(ok){var a=new BroadcastChannel('x'),b=new BroadcastChannel('x');b.onmessage=function(e){ok(e.data)};a.postMessage('bc')})`);
 ok(r==='bc','BroadcastChannel');
 r=await ev(ctx,`(function(){customElements.define('meu-el',function(){});return typeof customElements.get('meu-el')+'/'+typeof customElements.get('nao')})()`);
 ok(r==='function/undefined','customElements.define/get');
 r=await ev(ctx,`customElements.whenDefined('tardio').then(function(){return 'ok'}).then(function(v){return v}) && (function(){var p=customElements.whenDefined('t2');customElements.define('t2',function(){});return p.then(function(){return 'resolveu'})})()`);
 ok(r==='resolveu','customElements.whenDefined resolve após define');
 // 6. árvore, geometria, instanceof
 r=ev(ctx,`(function(){var tw=document.createTreeWalker(document.getElementById('a'),NodeFilter.SHOW_TEXT,null);var o=[],n;while(n=tw.nextNode())o.push(n.data);return o.join('|')})()`);
 ok(r==='um|dois|texto','TreeWalker SHOW_TEXT em ordem ('+r+')');
 r=ev(ctx,`(function(){var tw=document.createTreeWalker(document.getElementById('a'),NodeFilter.SHOW_ELEMENT,{acceptNode:function(n){return n.localName==='span'?NodeFilter.FILTER_ACCEPT:NodeFilter.FILTER_SKIP}});var o=[],n;while(n=tw.nextNode())o.push(n.localName);return o.join()})()`);
 ok(r==='span','TreeWalker com filtro');
 r=ev(ctx,`(function(){var r=new DOMRect(10,20,30,40);return [r.top,r.left,r.right,r.bottom,DOMRect.fromRect({x:1,width:2}).width].join()})()`);
 ok(r==='20,10,40,60,2','DOMRect ('+r+')');
 r=ev(ctx,`[document.querySelectorAll('p') instanceof NodeList, document.getElementById('a').classList instanceof DOMTokenList, document.getElementById('a').style instanceof CSSStyleDeclaration, document.createRange() instanceof Range, new WheelEvent('wheel',{deltaY:5}).deltaY, new UIEvent('x') instanceof Event].join()`);
 ok(r==='true,true,true,true,5,true','instanceof e eventos novos ('+r+')');
 // 7. SHA contra o crypto do Node
 for(const [alg,nome] of [['SHA-256','sha256'],['SHA-1','sha1']]){
   let todosOk=true;
   for(const txt of ['', 'a','abc','The quick brown fox jumps over the lazy dog','x'.repeat(55),'x'.repeat(56),'x'.repeat(64),'ç'.repeat(300),'z'.repeat(10000)]){
     const meu=await ev(ctx,`crypto.subtle.digest(${JSON.stringify(alg)}, new TextEncoder().encode(${JSON.stringify(txt)})).then(function(b){return Array.prototype.map.call(new Uint8Array(b),function(x){return ('0'+x.toString(16)).slice(-2)}).join('')})`);
     if(meu!==nodecrypto.createHash(nome).update(txt,'utf8').digest('hex'))todosOk=false;
   }
   ok(todosOk,alg+' igual ao crypto do Node (9 entradas, incluindo bordas de bloco)');
 }
 r=await ev(ctx,`crypto.subtle.digest('SHA-512',new Uint8Array(1)).then(function(){return 'passou'},function(e){return e.name||e.message})`);
 ok(/NotSupported/.test(r),'algoritmo não suportado rejeita com NotSupportedError ('+r+')');
 // 8. structuredClone
 r=ev(ctx,`(function(){var o={d:new Date(5),m:new Map([[1,{a:1}]]),s:new Set([1,2]),u:undefined,n:null,arr:[1,[2]]};o.self=o;var c=structuredClone(o);return [c!==o,c.d instanceof Date&&c.d.getTime()===5,c.m.get(1).a,c.s.size,'u' in c,c.self===c,c.arr[1][0]].join()})()`);
 ok(r==='true,true,1,2,true,true,2','structuredClone (Date, Map, Set, undefined, ciclo) ('+r+')');
 r=ev(ctx,`(function(){try{structuredClone({f:function(){}});return 'nao lançou'}catch(e){return e.name}})()`);
 ok(r==='DataCloneError','structuredClone de função lança DataCloneError ('+r+')');
 // 9. FileReader
 r=await ev(ctx,`new Promise(function(ok){var fr=new FileReader();fr.onload=function(){ok(fr.result)};fr.readAsDataURL(new Blob(['olá'],{type:'text/plain'}))})`);
 ok(r==='data:text/plain;base64,'+Buffer.from('olá').toString('base64'),'FileReader.readAsDataURL ('+r+')');
 r=await ev(ctx,`new Promise(function(ok){var fr=new FileReader();fr.addEventListener('loadend',function(){ok(fr.result)});fr.readAsText(new Blob(['abc']))})`);
 ok(r==='abc','FileReader.readAsText + addEventListener');
 // 10. indexedDB falha de forma graciosa e geolocation recusa
 r=await ev(ctx,`new Promise(function(ok){var q=indexedDB.open('x');q.onerror=function(){ok('erro tratado')}})`);
 ok(r==='erro tratado','indexedDB.open dispara onerror (os sites caem para outro armazenamento)');
 r=await ev(ctx,`new Promise(function(ok){navigator.geolocation.getCurrentPosition(function(){ok('sim')},function(e){ok('negado '+e.code)})})`);
 ok(r==='negado 1','geolocation recusa de forma graciosa');
 ok(erros.length===0,'nenhum erro registrado durante os testes'+(erros.length?': '+erros.slice(0,3):''));
 console.log(falhas?'FALHAS: '+falhas:'TUDO OK (extra)');process.exit(falhas?1:0);
})();
