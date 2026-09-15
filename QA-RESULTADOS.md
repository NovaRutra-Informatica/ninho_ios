# Verificações de QA — iOS

Verificado em 14/09/2026 no Windows, com Docker Swift 6.2.4/Linux:

- Pacote integrado: **94 testes passaram**, incluindo **16 do cronômetro**; cobertura de linhas NinhoCore **95,35%**. Relatórios em `TestResults/SwiftCore-final.log` e `SwiftCore-coverage-summary.json`.
- Scaffold: **13 testes Python passaram**; projeto gerado idêntico ao gerador, referências/schemes consistentes e perfis de simulador separados. `plutil -lint` aprovou o formato do `.pbxproj`; `bash -n` aprovou os scripts.
- Fontes dos testes Apple: análise de sintaxe Swift passou. **15 testes nativos e 20 testes de interface foram escritos, mas não executados.** Não houve build/link com o SDK Apple, execução do simulador, assinatura, instalação ou uso no iPhone.
- PDFs sintéticos de **644 B** e **3.300.730 B**: leitura estrita com pypdf e rasterização com PyMuPDF passaram; o retângulo verde ocupa **30,47%** da imagem. Evidência em `TestResults/pdf-fixtures`. Isso valida as fixtures; os testes separados de PDFKit ainda exigem Xcode.

Os testes nativos preparados cobrem a importação real e raster colorido do PDF, erro legível de PDF ausente, decodificação dos sons sem reprodução, assistente explicitamente indisponível e recuperação do cronômetro. O caso de escrita falha usa uma falha real no arquivo temporário; o caso pós-gravação/pré-confirmação reconstrói o estado durável de um encerramento nessa janela, verificando que a sessão não duplica.

A interface preparada cobre navegação, hierarquia, notas/status, quatro avaliações de revisão, cartões, agenda, foco/reabertura, prévia/remoção de material, ajustes/sons, IA indisponível e erros de formulário. Backup na interface cobre preparação do ZIP e cancelamento do seletor; a seleção/confirmação de restauração pelo aplicativo Arquivos e os cenários de Apple Intelligence real precisam ser exercitados no Mac/iPhone.

Quatro regressões adicionais foram preparadas após revisão de código: rascunho da aula preservado ao visitar cronômetro/PDF, notas e associação do material preservadas ao voltar do PDF, entrada automática de cartão que venceu com a tela aberta e atualização ao retornar do segundo plano. O caso temporal usa somente `dueAt` futuro de um cartão sintético, sem alterar o relógio do aparelho nem a regra de dez minutos do botão “Não lembrei”.

Não existem skips nesses testes Apple. Ainda podem surgir problemas de typecheck, integração de SDK, seletores ou layout ao executá-los; análise sintática e testes Linux não oferecem essa garantia. O workflow é somente manual e não foi publicado nem executado. Os comandos estão em `BUILD-AND-TEST.md`.
