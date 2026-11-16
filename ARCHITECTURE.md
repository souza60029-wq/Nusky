# Arquitetura do Nusky

## Visão geral

O Nusky é dividido em duas partes com uma fronteira clara entre elas:

```
┌──────────────────────────────┐
│  app/ (Swift + SwiftUI)      │  janela, abas, barra de endereço,
│                              │  rede (URLSession), desenho final
└──────────────┬───────────────┘
               │ chamada C (FFI)
┌──────────────▼───────────────┐
│  engine/ (Rust)              │  HTML → DOM → estilo → layout
│                              │  → lista de comandos de desenho
└──────────────────────────────┘
```

## Regras de dependência

- O **motor não conhece telas, UIKit ou SwiftUI.** Ele só recebe texto e devolve dados. Por isso, todos os testes rodam no Linux.
- A **casca nunca interpreta HTML ou CSS.** Ela apenas entrega o texto ao motor e desenha o que o motor devolve.
- A rede fica na casca. O motor recebe o conteúdo já baixado.

## Fluxo de dados

1. A casca baixa a página com `URLSession`.
2. O texto HTML é entregue ao motor.
3. O **parser** transforma o HTML numa árvore (DOM).
4. O **estilo** aplica as regras CSS a cada nó (no v0.1, valores padrão).
5. O **layout** calcula posição e tamanho de cada elemento.
6. O motor devolve uma **lista de comandos de desenho**: texto, posição, tamanho.
7. A casca desenha essa lista na tela.

## Decisões técnicas

| Área | Escolha | Motivo |
|---|---|---|
| Motor | Rust | Sem coletor de lixo, desempenho de C++, segurança de memória em tempo de compilação. |
| Casca | Swift + SwiftUI | Linguagem nativa, interface leve. |
| Desenho | Core Graphics e CoreText no v0.1 | Suficiente para conteúdo simples. |
| Desenho futuro | Metal | Entra quando medições mostrarem necessidade. |
| Rede | URLSession | Já vem no sistema, sem criptografia própria. |
| JavaScript | JavaScriptCore + DOM próprio em JS (`AmbienteJS`) | JIT via TrollStore. Uma máquina virtual para todas as páginas (o código compilado é reaproveitado), scripts avaliados como Script (não eval) pelo lado nativo, módulos ES por reescrita de tokens, e sessão viva que recebe toques e redesenha o motor só quando o DOM muda. |

## Princípio de otimização

Medir antes de otimizar. Nenhuma otimização entra sem uma medição que mostre o gargalo.

## Testes

- **Motor:** testes unitários com `cargo test`, rodando no Linux.
- **Casca:** testes manuais no iPhone 6s até existirem testes automatizados de interface.
## JavaScript vivo

1. **Primeira exibição.** O motor (Rust) entrega a árvore do HTML. O `AmbienteJS` monta o `document`, baixa todos os scripts de uma vez e roda na ordem da página, com os temporizadores em tempo virtual (nada espera de verdade). O orçamento é de 6 s.
2. **Sessão viva.** O contexto não é destruído. Temporizadores seguem em tempo real, fetch/XHR continuam e o `JSRodador` recebe toques. O DOM conta as próprias mudanças; quando o contador anda, o HTML novo volta para o motor, no máximo a cada 0,15 s (mais, se desenhar for caro: a cadência é medida, não fixa).
3. **Toque.** O serializador marca com `data-nusky-js="nusky-js:<id>|<link de reserva>"` os elementos que a página escuta (listener próprio, `onclick`, delegação em ancestral ou no `document`). O motor devolve o toque nesse formato, o `BrowserModel` o entrega ao `__tocar` e o JavaScript recebe pointer, touch, mouse e click de verdade, com as ações padrão (link, label, checkbox, details). Sem sessão viva, o toque cai no link de reserva.
4. **Scripts.** Scripts externos ficam no lado nativo, em UTF-8, e são avaliados como Script pelo JavaScriptCore: `let`, `const` e `class` do topo são compartilhados entre scripts, como num navegador, e o texto nunca vira string do JS. Todas as páginas usam a mesma `JSVirtualMachine`, então o JavaScriptCore reaproveita o código já compilado entre páginas.
5. **Módulos ES.** O JavaScriptCore não expõe carregador de módulos. O `AmbienteJS` reescreve cada módulo, por tokens, numa função (import vira leitura do módulo já executado, export vira getter, `import()` vira o carregador), carrega o grafo inteiro em paralelo e executa na ordem das dependências.
6. **Memória.** Menos de 90 MB livres ou alerta do sistema: coleta de lixo, descarte da máquina virtual compartilhada e, se continuar apertado, fecha a sessão viva.

## Carregamento de uma página

1. **HTML.** `DownloadPagina` baixa pela sessão compartilhada (`RedeNusky`), com prioridade alta e progresso por delegate. O `RoteadorDeRede` entrega os pedaços a cada download.
2. **Em paralelo.** `FolhasExternas.bloco` baixa o CSS externo e o `JSRodador` roda o JavaScript. Nenhum espera o outro.
3. **1ª pintura.** Quando o CSS chega, o app desenha o HTML do servidor com o CSS. Sem scripts, é a única pintura.
4. **2ª pintura.** Quando o JavaScript termina, o HTML novo entra pelo mesmo caminho das atualizações do modo vivo (`desenharVivo`), que preserva a rolagem. O bloco de CSS é guardado à parte (`cssDaPagina`) e reaplicado em cada desenho.
5. **Tema.** Antes de cada layout o Swift informa ao motor se o aparelho está no escuro (`nusky_definir_escuro`), para que `prefers-color-scheme` responda o mesmo que o `matchMedia` do JavaScript. Página sem fundo próprio é branca, a menos que o "forçar modo noturno" esteja ligado.
6. **Medição.** Cada etapa é cronometrada e aparece no relatório do Diagnóstico.
