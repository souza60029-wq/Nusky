# Nusky

Navegador para iPhone feito do zero. Ele não usa o motor de desenho do WebKit (o motor que o Safari usa): tem um motor próprio, escrito em Rust, que lê o HTML, aplica o CSS e desenha a página. A tela do app é feita em Swift e SwiftUI.

Versão atual: **0.0.5**

## Instalação

1. Tenha um iPhone com iOS 15 ou mais novo e o [TrollStore](https://github.com/opa334/TrollStore) instalado.
2. Baixe o arquivo `Nusky-unsigned.ipa` na página de [versões](https://github.com/souza60029-wq/Nusky/releases) do repositório.
3. Abra o arquivo no TrollStore e instale.

Testado no iPhone 6s com iOS 15.8.8.

## Atualização

Em **Ajustes > Sobre** há duas opções, e nada é verificado sozinho:

- **Atualizar só a lista de sites**: baixa a lista nova e aplica depois da sua confirmação.
- **Atualizar o app (inclui a lista)**: procura a última versão publicada no GitHub e entrega o arquivo ao TrollStore. A lista de sites é atualizada junto.

## O que o Nusky faz

- Abre sites http e https, com links clicáveis, tabelas, imagens (PNG, JPEG, GIF e WebP), ícones e logotipos em SVG, e as cores, fundos, bordas, destaques de texto, fontes com serifa e disposições (flex) que a página define.
- Executa o JavaScript das páginas e **o mantém vivo**: a primeira exibição espera até 6 segundos, e depois disso o JavaScript continua rodando. Menus, abas, botões, carregamentos sob demanda e navegação de sites de página única respondem ao toque. Ele fecha sozinho ao sair da página ou quando a memória fica curta.
- Entende módulos ES (`<script type="module">`, `import()`, mapas de importação), que é o que sites feitos com Vite, Svelte e Astro usam.
- Pinta a página em duas fases: primeiro o HTML do servidor com o CSS (sem esperar o JavaScript), depois a versão que o JavaScript montou, mantendo a rolagem.
- Baixa os scripts de uma vez, em paralelo, e o CSS ao mesmo tempo que o JavaScript roda. HTML, CSS e scripts dividem uma conexão HTTP/2 e um cache em disco.
- Entende `@layer`, `@supports` e `@media` de tela de toque (orientação, hover, resolução, `prefers-color-scheme`, `width >= 40rem`).
- Página sem fundo próprio é branca, como no Safari, mesmo com o iPhone no escuro.
- O Diagnóstico mostra quanto tempo cada etapa do carregamento levou. Veja o `CHANGELOG.md` para tudo que mudou.
- Encontra sites pelo nome. A busca roda numa lista que fica no aparelho, aceita erro de digitação e não envia o que você pesquisa.
- Abas numa grade de cartões, cada um com o ícone e o nome do site.
- Favoritos e histórico, com o ícone de cada site.
- Compartilhar, recarregar, voltar e avançar.
- Barra de endereço que fica fina, encostada na borda da tela como a do Safari (em cima, ela se mistura com a barra de status), e se abre com um toque. Ao tocar no campo, o endereço fica todo selecionado.
- Diagnóstico da página aberta, com relatório de texto para copiar.

## Ajustes

- **Aparência:** tema automático ou noturno, forçar modo noturno nos sites (escurece páginas claras), barra em cima ou embaixo e efeito de desfoque.
- **Toque:** feedback luminoso, expansivo e tátil, cada um liga e desliga sozinho, com intensidade Leve, Padrão ou Extravagante.
- **Navegação:** versão desktop, mostrar imagens, executar JavaScript e Metal. O Metal desenha o texto, as imagens e os ícones na GPU; a etiqueta azul indica que ele ajuda no desempenho. Se o aparelho não aceitar, o desenho normal continua.
- **Privacidade:** limpar histórico, cookies e cache.
- **Sobre:** versão, lista de sites, atualizações, repositório do projeto, diagnóstico e termos de uso.

As opções que podem pesar no desempenho trazem a etiqueta **Desempenho**.

## Privacidade

Histórico, favoritos, pesquisas, miniaturas das abas, cookies e sessões ficam só no aparelho. O Nusky não tem conta, cadastro nem servidor próprio. Os sites que você abre, as imagens e os ícones são pedidos ao próprio site, e as atualizações são pedidas ao GitHub. Os termos de uso completos aparecem na primeira abertura e em Ajustes > Sobre.

## Limitações

- O Nusky ainda não é um navegador completo: nem todo site abre, e cada um precisa ser testado no aparelho.
- Não desenha gradientes e máscaras de SVG, campos de formulário, fontes próprias dos sites nem fileiras que rolam de lado (viram uma lista vertical).
- O JavaScript de páginas grandes usa bastante memória. Se ela ficar curta, o JavaScript vivo é fechado e a página fica como estava.
- Só dá para tocar onde há texto ou imagem: um botão feito só de ícone SVG ou de fundo CSS ainda não recebe o toque.
- Módulos ES com `await` no nível do arquivo (top-level await) não rodam, e dependências circulares de módulos podem ver valores ainda vazios.

## Para quem quer compilar

- Testes do motor: `cargo test --manifest-path engine/Cargo.toml`
- Testes do JavaScript (precisa de Node 18 ou mais novo): `cd testes/js && node rodar-tudo.js`
- O workflow `iOS` do GitHub Actions gera o `Nusky-unsigned.ipa`. Ao criar uma tag no formato `v0.0.5`, ele publica o arquivo nas versões do repositório.

Mais detalhes de arquitetura estão em `ARCHITECTURE.md`.

## Licença

Mozilla Public License 2.0. Veja o arquivo `LICENSE`.

Copyright (c) 2026 S7y1_e