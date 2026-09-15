# Abrir, testar e instalar no iPhone

O projeto Xcode está entregue em `Ninho.xcodeproj`, com o scheme compartilhado **Ninho**. O app usa o pacote Swift local nesta pasta. É necessário um Mac com Xcode 26 ou posterior e um runtime iOS 26+ instalado. A execução no iPhone exige Developer Mode, confiança no Mac e assinatura Apple compatível com o aparelho.

No Mac, a partir da pasta `iOS`:

```bash
bash scripts/build-macos.sh
bash scripts/test-macos.sh
```

O primeiro comando compila para o simulador. O segundo executa o pacote Swift, os testes nativos e os testes de interface, usando um simulador separado chamado **Ninho QA iPhone 15 Pro Max**. Os resultados do Xcode ficam em `TestResults/*.xcresult`. O script não baixa runtimes automaticamente. `NINHO_SIMULATOR_UDID` permite selecionar explicitamente outro simulador disponível do mesmo modelo, com iOS 26+.

Para gerar um arquivo assinado e instalar no aparelho conectado:

```bash
export NINHO_DEVELOPMENT_TEAM="SEU_TEAM_ID"
bash scripts/archive-macos.sh
xcrun devicectl list devices
export NINHO_DEVICE_ID="IDENTIFICADOR_DO_IPHONE"
bash scripts/install-iphone.sh "/caminho/Ninho.xcarchive/Products/Applications/Ninho.app"
```

O Team ID real tem dez caracteres. O repositório não contém certificado, credencial ou Team ID pessoal. Caso queira autorizar o Xcode a atualizar o provisionamento usando a conta já configurada no Mac, defina `NINHO_ALLOW_PROVISIONING_UPDATES=1` antes do archive. A instalação exige um `.app` assinado para esse aparelho; um build de simulador não serve. O script verifica a assinatura e o identificador do app antes de instalar e abrir.

O workflow `.github/workflows/ios.yml` é manual (`workflow_dispatch`) e testa somente o simulador. Nenhum workflow foi publicado ou executado durante o desenvolvimento local. Autorize a publicação do repositório e a execução antes de usá-lo em uma conta GitHub. O catálogo contém títulos de aulas, mas não distribua PDFs privados junto do código.

## O que cada conjunto verifica

| Conjunto | Execução | Abrangência |
| --- | --- | --- |
| `Tests/NinhoCoreTests` | `swift test` no Linux/macOS | Regras, revisão, foco, contexto da Íris, sons e biblioteca/ZIP |
| `NinhoTests` | Xcode/iOS | Recursos, biblioteca real com PDFKit e raster colorido, som com AVAudioPlayer, assistente indisponível e persistência do NinhoStore |
| `NinhoUITests` | Xcode/iOS Simulator | Navegação, hierarquia, notas, revisões, cartões, agenda, foco, materiais, ajustes e backup |
| `scripts/test_scaffold.py` | Python 3 | Referências do projeto/scheme, isolamento do simulador e workflow manual |

Os testes de interface usam `NINHO_TEST_PROFILE` com UUID por método. Só o primeiro launch recebe `--reset-test-data`; reabrir o aplicativo preserva o perfil. A IA fica explicitamente indisponível com `--uitesting --disable-ai`, sem respostas inventadas. O PDF de teste é sintético e passa pela importação real; não há dados pessoais no perfil de QA.

O XCTest preparado não substitui a avaliação no iPhone físico: teste Apple Intelligence habilitada/desabilitada, geração/cancelamento, tamanho de texto ampliado, modo silencioso, vídeos, seleção em Arquivos/iCloud e transferência de um backup entre Windows e iPhone. A disponibilidade do modelo depende do estado real do Apple Intelligence no aparelho.

## Verificações portáveis

```bash
python3 scripts/generate_project.py --check
python3 scripts/test_scaffold.py
```

O projeto é gerado deterministicamente por `generate_project.py`. Adicionar arquivos Swift ou recursos às pastas sincronizadas `Ninho`, `NinhoTests` e `NinhoUITests` não exige editar o `.pbxproj`. Para regenerar a estrutura do projeto, execute o gerador sem `--check`.

No Windows com Docker, use sempre o mesmo ponto de montagem para o cache Swift:

```powershell
docker run --rm --mount "type=bind,source=C:/Users/aless/Ninho-iOS,target=/workspace" -w /workspace swift:6.2 swift test --jobs 2
```

Esse comando executa **apenas o pacote Swift no Linux**. Não compila o app SwiftUI nem executa PDFKit, FoundationModels, XCUITest ou o simulador. O `plutil` verifica o formato do projeto; análise sintática Swift também não substitui typecheck/link do SDK Apple.

Referências: [testes no Xcode](https://developer.apple.com/documentation/xcode/running-tests-and-interpreting-results), [pacotes locais](https://developer.apple.com/documentation/xcode/organizing-your-code-with-local-packages), [ferramentas de linha de comando](https://developer.apple.com/documentation/xcode/xcode-command-line-tool-reference) e [instalação em dispositivos registrados](https://developer.apple.com/documentation/xcode/distributing-your-app-to-registered-devices).
