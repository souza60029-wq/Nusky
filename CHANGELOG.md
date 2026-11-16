# Changelog do Nusky

## Próxima versão (a partir da 0.0.5)

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
- Módulos ES com `await` no nível do arquivo não rodam; dependências circulares de módulos podem ler valores
  ainda vazios.
- Sites que têm tema escuro só por JavaScript e não por CSS podem ficar com tema misturado.
