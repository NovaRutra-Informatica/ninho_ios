# Ninho para iPhone

Aplicativo nativo em Swift e SwiftUI para iPhone, com iOS 26 ou posterior. Mantém o catálogo do Senado Federal e o espaço Mauá, materiais por aula, revisão espaçada, calendário e uma assistente local chamada Íris.

**Estado da entrega:** código e projeto Xcode implementados. O núcleo foi compilado e testado em Swift/Linux. A compilação com SDK iOS, os testes de interface e a instalação no iPhone ainda exigem um Mac com Xcode; não há IPA validado nesta entrega. Os resultados exatos ficam em [VALIDACAO.md](VALIDACAO.md).

## O que está implementado

- Hoje: meta diária, revisões, próximos compromissos e acesso ao calendário pela data.
- Meus estudos: cursos → matérias → módulos → aulas. Criação e edição de conteúdo, anotações, progresso e links para o Estratégia.
- Materiais: cópia local de PDF, imagem, texto, Office, áudio e vídeo; vínculo explícito com matéria e aula; notas, compartilhamento e remoção da biblioteca.
- Leitura de PDF com PDFKit. Vídeos e áudios compatíveis usam AVKit; outros formatos usam a visualização do sistema ou podem ser compartilhados com outro leitor. A compatibilidade de codecs depende do iOS.
- Cartões: criação, edição, quatro avaliações, limite diário de novos cartões, suspensão e marcações para atualizar ou reaprender.
- Agenda: provas e tarefas, edição, conclusão e exclusão, com navegação pelo calendário.
- Foco: relógio por instantes, pausa, retomada após reabrir e tempo vinculado à aula. Finalização persistente evita duplicar uma sessão após interrupção.
- Progresso: tempo, constância, aulas e sinais de necessidade de revisão. O app não apresenta prática de cartões como medida de domínio de uma disciplina.
- Íris: modelo local da Apple, criado sob demanda, com contexto limitado aos registros de estudo; disponibilidade, cancelamento e novas tentativas explícitos.
- Sons originais curtos ao salvar, revisar e concluir. Respeitam a preferência e o modo silencioso do iPhone.
- Temas claro, escuro e do sistema, texto nativo escalável e redução de animações.
- Backup ZIP compatível com Ninho no Windows, com verificação de arquivos e preservação da coleção anterior antes de restaurar.

## Rodar no Mac e no iPhone

O Xcode e o SDK do iOS são ferramentas de macOS. Instalar Swift ou Docker no Windows permite testar o núcleo, mas não substitui o Xcode. Consulte os [requisitos oficiais do Xcode](https://developer.apple.com/xcode/system-requirements).

1. Copie ou clone este repositório `Ninho-iOS` para um Mac e instale Xcode 26 ou posterior compatível com esse Mac.
2. Abra `Ninho.xcodeproj`. O pacote local NinhoCore e suas dependências são resolvidos pelo Xcode; não é necessário gerar o projeto novamente.
3. Selecione o scheme **Ninho** e um simulador de iPhone com iOS 26 ou posterior. Execute **Product → Test** para os testes nativos/UI.
4. Em **Ninho → Signing & Capabilities**, escolha sua equipe Apple. Conecte e selecione seu iPhone 15 Pro Max, conclua no aparelho as solicitações de confiança e modo de desenvolvedor apresentadas pela Apple e execute **Run**.

A instalação física exige assinatura e provisionamento da sua conta Apple. Nenhuma conta, certificado ou Team ID está incluído no repositório. Não foi feita publicação na App Store ou envio dos seus materiais para serviços externos.

Os scripts abaixo validam seus pré-requisitos antes de executar:

```bash
# Núcleo + testes nativos e de interface; resultados em TestResults/*.xcresult
bash scripts/test-macos.sh

# Compilação de simulador
bash scripts/build-macos.sh

# Archive assinado, depois de configurar a equipe no Mac
export NINHO_DEVELOPMENT_TEAM=SEU_TEAM_ID
bash scripts/archive-macos.sh

# Instalação de um .app já assinado para o aparelho provisionado
export NINHO_DEVICE_ID=IDENTIFICADOR_DO_IPHONE
bash scripts/install-iphone.sh /caminho/Ninho.xcarchive/Products/Applications/Ninho.app
```

`NINHO_ALLOW_PROVISIONING_UPDATES=1` permite ao Xcode atualizar o provisionamento quando você decidir habilitar isso. O script de archive preserva destinos existentes. O script de instalação confere a assinatura e o identificador `com.aless.ninho.ios`.

## IA no aparelho

O iPhone 15 Pro Max é um aparelho compatível com Apple Intelligence, conforme os [requisitos da Apple](https://support.apple.com/en-gb/121115). A disponibilidade depende também da versão do sistema, configuração, idioma e disponibilidade dos arquivos do modelo. A Íris informa a condição retornada pelo sistema; não se passa por uma IA generativa se o modelo estiver indisponível. Veja a [documentação do Foundation Models](https://developer.apple.com/documentation/foundationmodels/generating-content-and-performing-tasks-with-foundation-models).

Não há dependência de LM Studio, servidor no PC ou download de um modelo de 32 bilhões de parâmetros. A sessão é criada quando você envia uma pergunta. O app encerra suas referências e cancela a geração ao sair ou interromper; a memória do modelo é administrada pelo iOS. Os PDFs não são enviados ao modelo nem lidos automaticamente pela assistente. Ela usa um resumo limitado de progresso, pendências e provas para orientar a conversa.

## Levar a coleção e os PDFs

No Ninho do Windows, exporte o backup ZIP completo. Leve esse arquivo ao iPhone pelo aplicativo Arquivos, AirDrop ou outro meio escolhido por você. Em **Mais → Ajustes e backup → Restaurar backup do Ninho**, selecione o ZIP e confirme a substituição.

O ZIP transporta arquivos e identificadores. Não há sincronização contínua entre os aparelhos: exportar e restaurar é uma troca explícita de coleção. Para um PDF avulso, abra a aula no iPhone e escolha **Adicionar arquivos à aula**.

Por decisão do usuário, os downloads do Estratégia serão feitos por ele. A estrutura de 14 matérias e 271 pastas de aulas/extras foi criada no Windows em `Downloads/PDFs/Senado Federal`; os módulos Passo Estratégico e João Trindade estão separados. A importação desse conjunto ficará para quando a pasta preenchida for indicada. O catálogo incluído no app não significa que os PDFs estejam embutidos.

## Desenvolvimento e testes

- `Sources/NinhoCore`: modelos, regras, biblioteca, backups, foco, contexto da assistente e sons.
- `Ninho`: interface e integrações Apple; `NinhoTests` e `NinhoUITests` exigem Xcode.
- `Tests/NinhoCoreTests`: testes portáteis, com diretórios temporários e documentos sintéticos.
- `scripts/generate_project.py`: gerador determinístico do projeto já incluído.
- `.github/workflows/ios.yml` na raiz do repositório: execução manual em macOS, se o projeto for futuramente colocado num repositório autorizado. Não foi publicada nem executada nesta entrega.

No Linux/Swift 6:

```bash
swift test --enable-code-coverage
python3 scripts/test_scaffold.py
```

Os argumentos de UI `--uitesting --disable-ai` usam perfil separado, identificado por `NINHO_TEST_PROFILE`. `--reset-test-data` limpa somente esse perfil na primeira execução do teste. Os testes preservam o perfil ao relançar. `--with-test-material` importa uma fixture sintética pela biblioteca real. Nenhum desses testes modifica o perfil pessoal do Windows.

O ícone reutiliza a coruja vetorial original do Ninho, renderizada como PNG RGB opaco de 1024 px. As melodias são sintetizadas por código, sem arquivos de áudio do Duolingo.
