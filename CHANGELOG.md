# Changelog do Nusky

## Próxima versão (a partir da 0.0.5)

### Rodada 8: o que os relatórios do claude.ai e do arena.ai mostraram

Os relatórios novos ainda eram do build da rodada 6 (sem as seções da rodada 7), mas já dizem bastante:

- **arena.ai:** o tema escuro agora chega (`<html class="dark" style="color-scheme: dark">`) e as cores do texto saem
  certas (claro sobre escuro). Com isso o diagnóstico das cores do arena.ai está limpo; o que sobra nele é layout
  (botões que quebram linha, campo de texto desalinhado), não cor.
- **claude.ai: o app demora para iniciar, e o aviso é só a tela de espera.** O JavaScript roda sem erros, mas o `#root`
  ainda está vazio quando a primeira exibição termina. O app monta a tela depois, no modo vivo, e é isso que aparece
  "do nada". O aviso "navegador desatualizado" é o `#js-cannot-start`, que a página mostra enquanto o app não iniciou.
  Agora o perfil do claude.ai o esconde (`css` no perfil), então a primeira pintura fica em branco em vez de mostrar um
  aviso errado.
- **Diagnóstico espera o modo vivo.** Antes, o relatório fechava a sessão logo na primeira exibição e mostrava o
  `#root` vazio. Agora espera até 10 s (ou 2 s sem mudança) e usa o último HTML que o app montou, que é a página que você vê,
  e usa o `tempoJS` do perfil do site. O relatório ganhou a linha "Espera no modo vivo".
- **Diagnóstico:** a contagem de elementos não conta mais `<length>`, `<color>` etc. de dentro de `<style>`.

### Rodada 7: claude.ai abre; faltam cores e tema escuro

Com a rodada 6, o claude.ai passou a abrir no Nusky (era a correção do `await`/regex), mas sem estilo: todo o texto sai
azul, como o texto de link. O arena.ai tem o mesmo sintoma em menor grau. Sem ver o CSS do site, a causa mais provável é um
valor de cor que o motor não lê. Em vez de apostar de novo:

- **Diagnóstico: "CORES QUE O MOTOR NÃO ENTENDEU".** O motor agora anota cada função de cor (`rgb`, `hsl`, `oklch`,
  `color-mix`, `light-dark`...) que não conseguiu ler e lista as 15 mais frequentes, com a contagem. Isso mostra, site a
  site, exatamente qual sintaxe de cor falta (`cor_alfa` em `css.rs`; teste em `css::testes`).
- **Diagnóstico: tema.** O relatório traz "Tema dos sites: automático ligado/desligado, noturno manual..." e "Tema entregue
  aos sites: claro/escuro". Os sites aparecem claros no Nusky e escuros no Safari porque o Nusky só entrega
  `prefers-color-scheme: dark` com "Automático" ligado em Ajustes e o iPhone no escuro, ou com "Forçar modo noturno".
  O relatório do arena.ai mostrou `color-scheme: light`, então o site recebeu tema claro. Nada foi mudado no
  comportamento; falta saber o valor dos ajustes.

### Rodada 6: relatórios do Diagnóstico (ChatGPT, claude.ai, GitHub, YouTube)

Os relatórios mostraram o que estava acontecendo de verdade. O CSS do GitHub agora carrega (20 folhas, 2,5 MB) e a
Wikipédia, o arena.ai e o GitHub renderizam estilo. O que faltava:

- **ChatGPT em branco: causa achada.** O módulo `538990.f894669a06.js` termina com `A=(z=await z).a`: um `await` no
  nível do arquivo, mas dentro de parênteses. A detecção de "módulo assíncrono" só reconhecia `await` com profundidade
  zero (contando parênteses), então o módulo ficava síncrono e o `await` virava nome de variável: `Unexpected
  identifier 'z'. Expected ')' to end a compound expression`. Agora a detecção conta só a profundidade de *corpos de
  função*: `await` dentro de parênteses, listas, `try`, `if` e `for await` conta como topo; `await` dentro de funções,
  não. Testado contra o ESM nativo do Node com o mesmo padrão do chunk (auto-importação incluída).
- **GitHub: `Can't find variable: HTMLMetaElement` / `HTMLLIElement`.** O ambiente só tinha 18 interfaces `HTML*Element`,
  todas apelidos de `HTMLElement` (então `div instanceof HTMLLIElement` dava `true`). Agora há todas as ~70, cada uma
  conferindo a tag no `instanceof`. A mensagem "Error / Looks like something went wrong!" do GitHub é o erro de React #185
  (laço de atualização), que **não** está resolvido; o relatório agora mostra mais para investigar.
- **claude.ai: o modo honesto piorou e foi desligado.** O relatório mostra que o `index-*.js` falha com `Invalid regular
  expression: invalid group specifier name` (regex com lookbehind), e o modo honesto tirava o motor de reserva de regex.
  O perfil do claude.ai ficou só com o tempo de espera maior, e o modo honesto não mexe mais no `RegExp`. Também
  endureci a reescrita de regex com lookbehind: agora ela acha o regex logo depois de `)` ou `}` e dentro de `${ }` de
  templates (antes só achava depois de operadores). Se o erro do claude.ai continuar, o novo relatório diz qual é.
- **YouTube: causa ainda desconhecida.** O JavaScript roda sem erros (21 scripts, `body.loading` vira `body`) mas só 3
  pedidos de rede acontecem, e nada é desenhado. O Diagnóstico agora lista os elementos que o app deixou na página
  (total, tags mais comuns e os personalizados, como `ytm-app`) e corta imagens embutidas do trecho do corpo, que
  ocupavam o espaço todo.

### Rodada 5: comparação com o Safari do mesmo iPhone 6s (claude.ai, arena.ai, GitHub, YouTube, ChatGPT)

Os prints do Safari mostram os cinco sites funcionando no mesmo aparelho, inclusive o claude.ai. Isso corrige a rodada
anterior, que dava o claude.ai como impossível: se o Safari abre, o bloqueio não é só "iOS 15 é velho demais", e sim algo
que o Nusky diz ter (ou deixa de ter) e o Safari não.

**Nada desta rodada foi compilado nem rodou no aparelho** (o ambiente de trabalho não tem Rust nem Swift). O que está
marcado *Testado* rodou no Node, contra o mesmo JavaScript que o app carrega. O resto depende do CI e do iPhone.

- **GitHub sem estilo (a causa mais provável).** O carregador de CSS aceitava no máximo 8 folhas, 400 KB cada e 1 MB no
  total. O GitHub manda mais de 10 folhas e a principal passa de 400 KB, então a página chegava ao motor quase sem CSS:
  "Skip to content" e "Navigation Menu" visíveis, menu aberto, caixas cinzas de carregamento. Os limites agora são 40
  folhas, 3 MB cada e 6 MB no total (`FolhasExternas.swift`). Também passam a valer: `<link>` sem aspas
  (`href=/a.css`), `rel="preload" as="style"`, folhas com `media` que não combina com a tela (impressão, tema escuro
  quando o site está claro, `min-width` maior que a tela) são puladas, `<noscript>` e comentários são ignorados, folha
  com byte fora do UTF-8 não é mais descartada, e há uma segunda tentativa quando a rede falha.
- **`PodaCSS`.** Antes de entregar o CSS ao motor, tira comentários, `@font-face`, `@keyframes`, `@media print` e
  espaços repetidos (o motor já ignorava essas regras). Na amostra sintética de 2,3 MB, 24% a menos em ~100 ms no Node.
  A lógica foi testada em JavaScript (`testes/js/poda_css.js`, 16 casos) e transcrita para Swift. Números reais de
  sites ainda não foram medidos.
- **Cores modernas (arena.ai).** O leitor de cores só entendia `#hex`, `rgb()`, `hsl()` e 17 nomes. O Tailwind 4, que o
  arena.ai usa, escreve cores em `oklch()` e `color-mix()`: elas eram descartadas e o texto caía na cor padrão do link
  (o "Sign up for free" azul do print). Novo módulo `engine/src/cores.rs`: os 148 nomes do CSS, `hwb()`, `lab()`, `lch()`,
  `oklab()`, `oklch()`, `color()`, `color-mix()` e `light-dark()`. Cor fora da gama perde saturação até caber, como no
  Safari. As contas foram conferidas em JavaScript contra valores conhecidos (red-500 do Tailwind = 251, 44, 54);
  os testes em Rust (`cargo test`) usam esses valores. **Ainda não compilado.**
- **Elementos personalizados de verdade (YouTube).** `customElements.define` só guardava o nome e nenhum componente era
  criado: é a explicação mais provável para o `m.youtube.com` mostrar só um quadrado preto, e também afeta Polymer, Lit e
  os componentes do GitHub. Agora há construtor, `attributeChangedCallback`, `connectedCallback`, `disconnectedCallback`,
  upgrade de elementos que já estavam na página, `whenDefined`, `upgrade` e `attachInternals`. Os ganchos só são
  instalados no primeiro `define`. *Testado* (`teste_componentes.js`). **Não garante** que o YouTube abra: pode haver
  outras causas.
- **Sombra (Shadow DOM) e `<slot>`.** `attachShadow` devolvia um fragmento solto que nunca aparecia na página. Agora a
  sombra é "achatada" na hora de montar o HTML (a sombra, com os filhos do hospedeiro nos `<slot>`), o clique sobe da
  sombra para o hospedeiro e `shadowRoot.innerHTML` funciona. *Testado.*
- **Folhas de estilo.** `insertRule`, `deleteRule`, `replaceSync`, `new CSSStyleSheet()`, `<style>.sheet.cssRules`,
  `document.styleSheets` e `adoptedStyleSheets` (na página e na sombra) agora chegam à página. Antes o `insertRule`
  não fazia nada, e bibliotecas de CSS-em-JS (que deixam o `<style>` vazio) perdiam todo o estilo. *Testado.*
- **JavaScript novo que o iOS 15 não tem.** `Promise.withResolvers`, `Array.fromAsync`, `Object.groupBy`,
  `Map.groupBy`, `toSorted`/`toReversed`/`toSpliced`/`with`, métodos de `Set` (`union`...), `isWellFormed`,
  `URL.canParse`, `AbortSignal.any`, `Symbol.dispose`, `ArrayBuffer.transfer` e helpers de `Iterator`. Cada um só
  entra se o motor não tiver. A flag `v` de regex tenta a `u` quando a expressão serve para as duas. *Testado.*
- **Perfis por site (`PerfisDeSite.swift`).** Até agora **não existia** um lugar para ajuste de um site só (a lista de
  sites serve para a busca, não guarda correções). Criei um: cada perfil vale só para o domínio dele e seus subdomínios.
  Campos: `agente` (mobile / ios17 / desktop / texto), `css`, `js`, `honesto`, `semJS`, `tempoJS`, `maxFolhas`,
  `ignorarScripts`. A tabela de fábrica está no arquivo; um campo `"perfis"` na lista de sites baixada vale por cima, então
  um conserto novo pode chegar pelo botão "Atualizar só a lista de sites".
- **Modo honesto (experimento para o claude.ai).** O Nusky empresta ao site recursos que o iOS 15 não tem
  (`TextDecoderStream`, `AbortSignal.timeout`, regex com lookbehind...). Se o claude.ai escolhe a versão do código pelo
  que existe, ele manda ao Nusky o código novo demais, e o Safari, sem esses recursos, recebe o código antigo que
  funciona. No perfil `claude.ai` o modo honesto esconde esses recursos. É uma hipótese que bate com o print do
  Safari, **não uma certeza**. Se não resolver, o próximo diagnóstico do claude.ai diz o que ele consulta.
- **Primeira pintura protegida.** Se a versão que o JavaScript monta fica sem texto e a do servidor tinha conteúdo, o
  app mantém a do servidor e anota "2ª pintura descartada" no diagnóstico, em vez de trocar por uma tela em branco.
- **Tempo de espera por site.** YouTube, ChatGPT e arena.ai esperam mais pela primeira exibição (8 a 10 s, em vez de 6).
- **Diagnóstico.** A linha de cada página no relatório agora traz o resumo do CSS (folhas pedidas e recebidas, KB) e o
  perfil usado.

**ChatGPT em branco:** não achei causa com certeza. As mudanças acima (componentes, folhas, JavaScript novo, tempo)
podem resolver, mas se continuar em branco, mande o relatório do Diagnóstico desse site: a lista de erros diz o que
falta.

### Rodada 4: o que os diagnósticos de claude.ai, arena.ai, chatgpt.com, github.com e youtube mostraram

**Correção de uma hipótese minha.** Eu tinha dito que o claude.ai falhava por causa do `CSS.supports`. Os diagnósticos
mostraram outra coisa: o `<html>` do site declara `data-browser-floor="…safari:17,ios:17"` (iOS 17 como mínimo) e 20 dos
pacotes dele usam regex com *lookbehind*, que o JavaScriptCore só entende a partir do Safari 16.4. Isso não tem conserto
dentro do app. O mesmo vale para o Safari do iPhone 6s. Os ajustes de `CSS.supports` e `matchMedia` continuam valendo
para outros sites, mas não eram a causa.

- **Observadores de verdade.** `ResizeObserver`, `IntersectionObserver` e `PerformanceObserver` eram apelidos do
  `MutationObserver`, e ele era um objeto vazio que nunca avisava ninguém. Agora o `MutationObserver` registra
  `childList`, `attributes` (com `attributeFilter` e `oldValue`), `characterData` e `subtree`. O `IntersectionObserver`
  e o `ResizeObserver` avisam uma vez que o elemento está visível e com a largura da tela, com trava contra
  "carregar mais" em laço. Era a causa mais provável do YouTube abrir vazio sem nenhum erro. *Testado.*
- **`<template>.content`.** O GitHub falhava com `undefined is not an object (evaluating 'f.content.appendChild')` nos
  três pacotes principais. *Testado.*
- **`await` no nível do arquivo nos módulos.** O ChatGPT usa; o motor não aceitava (`Unexpected identifier`). O módulo
  passa a rodar como função assíncrona, quem depende dele espera, e a ordem entre módulos e scripts se mantém.
  Comparado com o ESM do Node em 5 casos, mais o caso de erro e o de ordem. *Testado.*
- **`static { }` de classe** (arena.ai e o `vendor-intl` do claude.ai). O iOS 15 não lê esse bloco. Quando um script falha
  ao ler, o app o reescreve (cada bloco vira um campo estático com os mesmos comandos) e tenta de novo. Só roda
  nos scripts que falharam, então os outros não pagam nada. Cobre script inline, externo e módulo. *Testado com um iOS 15
  simulado; confirmação no aparelho pendente.*
- **Regex com lookbehind** (`(?<=…)`, `(?<!…)`), que o iOS 15 não lê e que derrubava 20 pacotes do claude.ai. Há um motor de
  regex próprio em JavaScript (`AmbienteJSModerno.swift`). O `RegExp` global recorre a ele quando o nativo recusa uma expressão
  com lookbehind, e as regex literais dos scripts que falham ao ler são reescritas para usá-lo. As demais continuam nativas.
  Comparado com o regex do Node em ~1.900 padrões escritos à mão (0 diferenças) e 40.000 aleatórios (7 diferenças, todas em
  regex com um grupo de captura *dentro* do lookbehind: o trecho capturado ali pode diferir). *Testado.*
  Isso remove um bloqueio do claude.ai, mas **não garante** que ele abra: o site também declara iOS 17 como mínimo e pode usar
  outros recursos que ainda faltam.
- **Mensagem de erro com o trecho.** Quando um script não chega a rodar, o erro agora mostra o código perto do ponto
  da falha. Assim o próximo diagnóstico aponta a causa em vez de uma coluna.
- **`CryptoKey`, `SubtleCrypto` e `Crypto`** (o ChatGPT falhava com `Can't find variable: CryptoKey`).

### Páginas que abriam erradas, continuação

- Sublinhado dos links: o motor não lê `text-decoration`, então só páginas **sem CSS** sublinham links. Nova função
  `Apresentacao.paginaTemCSS`.
- `position: fixed` passa a ocupar o lugar dele no fluxo da página (antes ficava solto, sem espaço, e o menu do globo
  se empilhava na lateral por cima do texto). Ele ainda não vai para o fim da página.


Esta entrega junta tudo que foi feito em três rodadas de trabalho. Cada item diz se foi **medido**, **testado**
(teste automático que roda no CI) ou **só revisado** (escrito e lido com cuidado, mas ainda não compilado nem
rodado no iPhone: o CI do GitHub é quem confirma).

### Carregamento de páginas

- **Pintura em duas fases.** O app deixou de esperar o JavaScript para mostrar a página. Assim que o HTML e o CSS
  chegam, ele desenha o HTML que o servidor mandou (1ª pintura). O JavaScript termina depois e o app troca pela
  versão dele (2ª pintura), mantendo a posição da rolagem. Sites que já vêm prontos (notícias) aparecem logo;
  os que dependem de JavaScript ganham o conteúdo na troca. *Só revisado.*
- **CSS e JavaScript ao mesmo tempo.** Antes: baixava o HTML, depois todo o CSS, e só então rodava o JavaScript.
  Agora o CSS e o JavaScript começam juntos. *Só revisado.*
- **Uma sessão de rede para HTML, CSS e scripts.** Antes cada página criava uma sessão nova (refazendo DNS, TCP e
  TLS) e o CSS usava outra. Agora é uma só, com conexão HTTP/2 reaproveitada, cache em disco de 96 MB e prioridade
  alta para a página que você pediu. Sair da página antes de terminar cancela o download. *Só revisado.*
- **Scripts em paralelo.** Antes um script só começava a baixar quando o anterior terminava. Agora todos (até 64)
  são pedidos de uma vez, e a execução continua na ordem da página. *Testado.*
- **Tempos por etapa no Diagnóstico.** O relatório de desempenho mostra, por página, quanto levou o HTML, o CSS,
  a 1ª pintura, o JavaScript e a 2ª pintura. Serve para ver onde o tempo vai de verdade. *Só revisado.*

### Páginas que abriam erradas (globo.com, arena.ai)

- **Fundo e texto ilegíveis no modo escuro.** Com o iPhone no escuro, páginas sem fundo próprio ficavam com fundo
  preto mas o texto que o site colorira (cinza escuro) continuava escuro. Agora a página sem fundo próprio é
  branca, como no Safari. O conteúdo só escurece com "forçar modo noturno" ou quando o próprio site tem tema
  escuro. *Só revisado.*
- **`@layer` e `@supports`.** O motor jogava fora o bloco inteiro de qualquer regra que não fosse `@media`. Sites
  modernos (Tailwind 4, entre outros) colocam quase todo o CSS dentro de `@layer`. Agora o conteúdo vale.
  `@supports not (...)` continua de fora. *Teste unitário escrito; roda no CI.*
- **`@media` além da largura.** Antes qualquer outra condição fazia o bloco inteiro ser ignorado. Agora o motor
  entende orientação (em pé), toque (sem hover, ponteiro grosso), resolução 2x, sem redução de movimento,
  altura da tela, a sintaxe de faixa `(width >= 40rem)` e `(400px <= width <= 700px)` do Tailwind 4, e
  `prefers-color-scheme`, que segue o tema real do aparelho (o mesmo valor que o JavaScript recebe).
  *Testes unitários escritos; rodam no CI.*
- **Tema do aparelho chega ao motor.** Nova função `nusky_definir_escuro` na ponte entre Swift e Rust.

### JavaScript

- **JavaScript vivo.** O contexto não é mais destruído depois dos 6 segundos. Os 6 s viram só o orçamento da
  primeira exibição. Depois, temporizadores seguem em tempo real, fetch/XHR continuam e o toque vira clique de
  verdade (pointer, touch, mouse, click, com as ações padrão de link, label, checkbox e details). O DOM conta as
  próprias mudanças e a tela só é redesenhada quando algo mudou. *JavaScript testado; Swift só revisado.*
- **Cadência adaptativa.** Os temporizadores não têm piso artificial (mínimo de 4 ms, como num navegador). Só os
  quadros de animação que a tela não conseguiria mostrar deixam de ser calculados, de acordo com o custo medido
  de desenhar a página. *Só revisado.*
- **Módulos ES.** `<script type="module">`, `import()` dinâmico, mapas de importação e `modulepreload`. Antes eram
  ignorados, então sites feitos com Vite, Svelte e Astro abriam sem JavaScript. O módulo é reescrito por tokens
  (strings, templates, regex e comentários não confundem a leitura). Dez casos conferem com o ESM nativo do Node;
  o transformador passou por 961 arquivos CommonJS reais (nenhum alterado) e 100 módulos ESM reais (98 válidos,
  2 fora do escopo: um `#!` e um `await` no nível do arquivo). *Testado.*
- **Scripts como Script, não como `eval`.** Corrige um bug do motor original: `const`, `let` e `class` do topo
  de um script ficavam invisíveis para o seguinte. Agora são compartilhados, como num navegador. O texto dos
  scripts externos fica no lado nativo e nunca vira string do JavaScript (antes eram várias cópias de pacotes de
  megabytes). Aceita pacotes de até 8 MB (antes 3 MB). *JavaScript testado; Swift só revisado.*
- **Uma máquina virtual de JavaScript para todas as páginas.** O JavaScriptCore guarda o código já compilado
  dentro dela, então o mesmo script em outra página pode não precisar ser compilado de novo. *É uma aposta: não
  confirmei que o cache de código funciona nesse caminho.*
- **DOM mais rápido** (medido no Node, tempo relativo, mesma máquina):
  - `getElementById` com ids diferentes (5000 chamadas): de 1946 ms para 17 ms.
  - `getElementById` repetido: de 3123 ms para 3,7 ms.
  - `querySelectorAll('.x')`: 12 vezes mais rápido.
  - `firstElementChild` e `childElementCount`: 9 vezes mais rápido.
  - Montar 5000 elementos: sem diferença (mediana 48 ms antes, 44 ms depois).
  O índice de ids é conferido a cada acerto e foi testado com ~8000 consultas e mutações aleatórias sem nenhuma
  divergência. *Testado.*
- **Menos redesenho à toa.** Escrever o mesmo valor num atributo, numa classe ou num texto não conta mais como
  mudança. *Testado.*
- **Handlers `onclick="..."` em atributo** passam a executar. *Testado.*
- **Memória.** Menos de 90 MB livres ou alerta do sistema: coleta de lixo, descarte da máquina virtual e, se
  continuar apertado, fecha o JavaScript vivo. Segundo plano pausa os temporizadores. *Só revisado.*

### Ajustes

- Novo: **JavaScript interativo** (liga/desliga o modo vivo).
- Novo: **Bloquear rastreadores** (Google Analytics, Meta Pixel, Hotjar e outros). **Desligado por padrão**, porque
  bloquear é cortar, não otimizar, e alguns sites dependem desses scripts.

### Testes e CI

- Os testes de JavaScript agora rodam sobre o código que o app realmente usa (`testes/js/extrair.js` gera o
  `ambiente.js` a partir do `AmbienteJS.swift`). O arquivo `testes/js/ambiente.js` do repositório era um trecho
  de Swift com extensão errada, então o teste nunca rodou nele.
- Novo job `test-js` no CI. Suíte com 5 arquivos: motor do DOM, modo vivo, avaliação nativa, módulos ES (com
  comparação contra o ESM do Node) e índice de ids com mutações aleatórias.
- Testes unitários novos no motor Rust para o toque do JavaScript, `@layer`, `@supports` e `@media`.

### Bugs meus encontrados e corrigidos durante o trabalho

- Contagem dupla de scripts bloqueados (a pré-carga e a execução contavam o mesmo script).
- Toque em lista com clique delegado chegava com o alvo errado (o `ul`, não o `li`).
- Listener de clique adicionado depois do primeiro desenho não avisava que a página mudou, então o elemento nunca
  era marcado como clicável.
- O limite de tempo virtual deixava timers órfãos em vez de entregá-los ao modo vivo.

### Limitações conhecidas

- **Barra fixa embaixo** (como a Destaques/Vídeos/Jogos do globo) aparece no topo: o motor ignora `bottom` em
  `position: fixed` e desenha o elemento onde ele está no HTML. Corrigir exige mexer no layout do Rust e não
  quis arriscar o seu build sem poder compilar.
- Ícones e logos em SVG complexos, fontes próprias do site, bordas arredondadas em imagens e selos sobrepostos
  seguem diferentes do Safari.
- Só dá para tocar onde há texto ou imagem; botão só de ícone SVG ou de fundo CSS não recebe o toque.
- Dependências circulares de módulos podem ler valores ainda vazios.
- Regex com *lookbehind* e outras sintaxes do Safari 16.4 em diante não têm como rodar no iOS 15.
- Sites que têm tema escuro só por JavaScript e não por CSS podem ficar com tema misturado.
