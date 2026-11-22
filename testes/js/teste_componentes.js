// Elementos personalizados, sombra achatada, <slot>, folhas de estilo (insertRule, adoptedStyleSheets).
const vm = require('vm'), fs = require('fs');
const base = fs.readFileSync('teste.js', 'utf8'); eval(base.slice(base.indexOf('function parse(h)'), base.indexOf('function rodar(')));
function nova(html, opts = {}) {
  const erros = []; const ctx = vm.createContext({});
  ctx.__parse = h => JSON.stringify(parse(h)); ctx.__erro = m => erros.push(m); ctx.__fim = () => {}; ctx.__acordar = () => {}; ctx.__aviso = () => {};
  ctx.__pagina = { href: 'https://site.com/', protocolo: 'https:', host: 'site.com', agente: 'UA', plataforma: 'iPhone', toque: true, largura: 375, altura: 812, escala: 2, escuro: false, ...opts };
  ctx.__pedir = () => {};
  vm.runInContext(fs.readFileSync('ambiente.js', 'utf8'), ctx);
  vm.runInContext(fs.readFileSync('extra.js', 'utf8'), ctx);
  ctx.__iniciar(JSON.stringify(parse(html)));
  return { ctx, erros };
}
const ev = (c, s) => vm.runInContext(s, c);
const esperar = ms => new Promise(r => setTimeout(r, ms));
let falhas = 0; const ok = (c, m) => { if (!c) { falhas++; console.log('FALHOU:', m); } else console.log('ok:', m); };
(async () => {
  // 1. upgrade de elemento que já estava na página
  let { ctx, erros } = nova('<html><body><x-a nome="um"></x-a><div id="d"><x-a nome="dois"></x-a></div></body></html>');
  ev(ctx, `window.log=[];class XA extends HTMLElement{static get observedAttributes(){return['nome']}constructor(){super();log.push('ctor:'+this.getAttribute('nome'))}connectedCallback(){log.push('conn:'+this.getAttribute('nome'));this.textContent='oi '+this.getAttribute('nome')}disconnectedCallback(){log.push('desc:'+this.getAttribute('nome'))}attributeChangedCallback(n,a,b){log.push('attr:'+n+':'+a+'>'+b)}};customElements.define('x-a',XA)`);
  await esperar(5);
  let log = ev(ctx, 'log.join("|")');
  ok(log === 'ctor:um|attr:nome:null>um|conn:um|ctor:dois|attr:nome:null>dois|conn:dois', 'upgrade dos que já estavam na página, na ordem do documento (' + log + ')');
  ok(ev(ctx, '__serializar()').includes('<x-a nome="um">oi um</x-a>'), 'o conteúdo feito no connectedCallback aparece no HTML');
  ok(ev(ctx, 'document.querySelector("x-a") instanceof XA') === true, 'instanceof da classe depois do upgrade');
  // 2. criar, conectar, mudar atributo, remover
  ev(ctx, 'log.length=0;var e=document.createElement("x-a");log.push("criado");e.setAttribute("nome","tres");document.body.appendChild(e);e.setAttribute("nome","quatro");e.removeAttribute("nome");e.remove()');
  log = ev(ctx, 'log.join("|")');
  ok(log === 'ctor:null|criado|attr:nome:null>tres|conn:tres|attr:nome:tres>quatro|attr:nome:quatro>null|desc:null', 'createElement + setAttribute + connected/disconnected (' + log + ')');
  // 3. new direto, innerHTML, cloneNode
  ev(ctx, 'log.length=0;var n=new XA();log.push(n.localName);document.getElementById("d").innerHTML="<x-a nome=\\"i\\"></x-a>"');
  log = ev(ctx, 'log.join("|")');
  ok(log === 'ctor:null|x-a|desc:dois|ctor:i|attr:nome:null>i|conn:i', 'new XA() e innerHTML com elemento personalizado (' + log + ')');
  // 4. whenDefined e erros de registro
  let r = await ev(ctx, '(async()=>{var p=customElements.whenDefined("x-b");customElements.define("x-b",class extends HTMLElement{});await p;return "definido"})()');
  ok(r === 'definido', 'whenDefined espera o define');
  ok(ev(ctx, 'try{customElements.define("x-a",class extends HTMLElement{});"sem erro"}catch(e){e.name}') === 'NotSupportedError', 'nome repetido dá NotSupportedError');
  ok(ev(ctx, 'try{customElements.define("semtraco",class extends HTMLElement{});"sem erro"}catch(e){e.name}') === 'SyntaxError', 'nome sem hífen dá SyntaxError');
  ok(erros.length === 0, 'nenhum erro registrado' + (erros.length ? ': ' + erros.join(' / ') : ''));
  // 5. sombra achatada com slot
  ({ ctx, erros } = nova('<html><body><x-s><b slot="t">titulo</b><i>corpo</i></x-s></body></html>'));
  ev(ctx, `customElements.define('x-s',class extends HTMLElement{constructor(){super();var r=this.attachShadow({mode:'open'});r.innerHTML='<h1><slot name="t"></slot></h1><p><slot>vazio</slot></p>'}})`);
  await esperar(5);
  let h = ev(ctx, '__serializar()');
  ok(h.includes('<x-s><h1><b slot="t">titulo</b></h1><p><i>corpo</i></p></x-s>'), 'sombra achatada com <slot> nomeado e padrão (' + h.match(/<x-s>.*<\/x-s>/) + ')');
  ok(ev(ctx, 'document.querySelector("x-s h1")') === null && ev(ctx, 'document.querySelector("x-s").shadowRoot.querySelector("h1") !== null'), 'a sombra não aparece no querySelector do documento, mas aparece no shadowRoot');
  ev(ctx, 'var v=document.createElement("x-s");document.body.appendChild(v)');
  h = ev(ctx, '__serializar()');
  ok(h.includes('<x-s><h1></h1><p>vazio</p></x-s>'), 'slot sem filhos usa o conteúdo reserva');
  // evento sobe da sombra para o hospedeiro
  r = ev(ctx, '(function(){var x=document.querySelector("x-s"),got="";x.addEventListener("click",function(e){got="host"});x.shadowRoot.querySelector("h1").dispatchEvent(new MouseEvent("click",{bubbles:true}));return got})()');
  ok(r === 'host', 'clique dentro da sombra chega ao hospedeiro');
  // 6. folhas de estilo
  ({ ctx, erros } = nova('<html><head><style id="s">a{color:red}</style></head><body></body></html>'));
  ev(ctx, 'var st=document.createElement("style");document.head.appendChild(st);st.sheet.insertRule(".x{color:blue}",0);st.sheet.insertRule(".y{margin:0}",1)');
  h = ev(ctx, '__serializar()');
  ok(h.includes('<style>.x{color:blue}\n.y{margin:0}</style>'), 'insertRule vira texto do <style> (' + h.match(/<style>.*?<\/style>/s) + ')');
  ok(ev(ctx, 'document.getElementById("s").sheet.cssRules.length') === 1, '.sheet.cssRules lê as regras que já estavam no <style>');
  ev(ctx, 'document.getElementById("s").sheet.insertRule("@media (min-width:1px){b{x:y}}", 1);document.getElementById("s").sheet.deleteRule(0)');
  ok(ev(ctx, '__serializar()').includes('<style id="s">@media (min-width:1px){b{x:y}}</style>'), 'deleteRule e regra com @media');
  ev(ctx, 'var f=new CSSStyleSheet();f.replaceSync("p{color:green}");document.adoptedStyleSheets=[f]');
  ok(ev(ctx, '__serializar()').includes('p{color:green}'), 'document.adoptedStyleSheets chega à página');
  ev(ctx, 'f.replaceSync("p{color:pink}")');
  ok(/p\{color:pink\}/.test(ev(ctx, '__serializar()')) && !ev(ctx, '__serializar()').includes('p{color:green}'), 'replaceSync atualiza a folha adotada');
  ({ ctx } = nova('<html><body><x-t></x-t></body></html>'));
  ev(ctx, `customElements.define('x-t',class extends HTMLElement{constructor(){super();var r=this.attachShadow({mode:'open'});var f=new CSSStyleSheet();f.replaceSync('.k{color:red}');r.adoptedStyleSheets=[f];r.innerHTML+='<span class="k">z</span>'}})`);
  await esperar(5);
  ok(ev(ctx, '__serializar()').includes('<x-t><style>.k{color:red}</style><span class="k">z</span></x-t>'), 'adoptedStyleSheets na sombra vira <style> dentro do componente');
  console.log(falhas ? 'FALHAS: ' + falhas : 'TUDO OK');
  process.exit(falhas ? 1 : 0);
})();
