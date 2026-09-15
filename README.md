# Ninho para iPhone

Repositório independente do aplicativo Swift/SwiftUI, com o projeto `Ninho.xcodeproj` e o pacote local `NinhoCore` na raiz. O código existente foi separado da versão Windows, sem criar commit ou staging.

## Ambiente

No Mac, instale Xcode 26 ou posterior e abra `Ninho.xcodeproj`. O projeto resolve as dependências fixadas em `Package.resolved`.

```bash
bash scripts/build-macos.sh
bash scripts/test-macos.sh
```

No Windows deste computador, Docker e Swift/Linux permitem testar somente o núcleo:

```powershell
docker run --rm --mount "type=bind,source=$($PWD.Path),target=/workspace" -w /workspace swift:6.2 swift test --jobs 2
```

O Windows não dispõe do SDK Apple: compilação nativa, testes no simulador, assinatura e instalação no iPhone permanecem pendentes de Mac/Xcode. O workflow em `.github/workflows/ios.yml` é manual e não foi publicado nem executado.

## Git

O `.gitignore` exclui caches Swift/Xcode, resultados, arquivos locais, certificados, provisionamento e dados pessoais. O scheme compartilhado, `Package.resolved`, os assets e as fixtures sintéticas permanecem versionáveis. Nenhum remote foi configurado.

```bash
git status
git add .
git commit -m "Prepara Ninho para iPhone"
```

Consulte [LEIA-ME.md](LEIA-ME.md), [BUILD-AND-TEST.md](BUILD-AND-TEST.md) e [VALIDACAO.md](VALIDACAO.md) para uso, recursos existentes e limites dos testes.
