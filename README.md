# Ninho para iPhone

Repositório independente do aplicativo Swift/SwiftUI, com o projeto `Ninho.xcodeproj` e o pacote local `NinhoCore` na raiz. O código existente foi separado da versão Windows, sem criar commit ou staging.

## Ambiente

### Backup diário leve e recuperação

Em **Perfil → Preferências e backup → Backup leve**, o aplicativo mantém os últimos sete dias de cópias compactas de perfil, configurações, tutoriais, estudos e planos/análises salvas. Preserva nomes e vínculos dos materiais, mas exclui anexos e modelos pesados. O iCloud Drive é opcional, começa desligado e usa o container próprio do aplicativo; também há exportação/importação por Arquivos. Uma cópia externa disponível permite recuperar após reinstalar; somente a cópia interna não sobrevive à exclusão do aplicativo. Veja [BACKUP-LEVE.md](devdocs/BACKUP-LEVE.md) para uso, limites e configuração de `NINHO_ICLOUD_CONTAINER`/iCloud Documents no Xcode. O iOS controla trabalho e transferências em segundo plano; não há promessa de execução diária com o app fechado.

### Foguinho, perfil e assistente

O cabeçalho mostra **foguinho + número** ao lado do perfil, sem card na Home. Toque para abrir o calendário mensal dos dias estudados, navegar pelos meses e voltar para hoje. Só contam dias com estudo ou revisão registrados; abrir o aplicativo não aumenta a sequência. **Perfil** e **Ajuda** usam ícones no cabeçalho, com nomes acessíveis e áreas de toque de pelo menos 44 pontos. Em **Perfil → Widgets e atalhos**, há instruções para personalizar as telas de início e bloqueio.

Em **Minha assistente → Conhecer ou trocar o modelo**, você vê a Íris, o motor estatístico incluído **Ninho Adaptativo v1** e as opções de linguagem. A importação opcional aceita **Qwen2.5 0.5B ou 1.5B Instruct em GGUF Q4_K_M**, um arquivo de até 1,2 GiB. O guia explica formato, cópia, validação e uso; o acompanhamento incluído funciona sem importar nada. Veja [MODELOS-LOCAIS.md](devdocs/MODELOS-LOCAIS.md).

### Widgets e atalhos nativos — 23/09/2026

O target **NinhoWidgets** entrega três widgets: **Seu foguinho**, **Seu dia de estudos** e **Hora de focar**. Todos oferecem tamanhos pequeno e médio na Tela de Início; a Tela Bloqueada oferece versões retangulares dos três e circulares de foguinho/foco. O tamanho médio de Seu dia permite abrir revisões ou foco. A sequência segue dias locais de estudo registrado, preserva a de ontem até o fim de hoje e não conta visitas nem um timer ainda não salvo. A coruja é o mesmo asset do app.

Abra o Ninho uma vez, finalize o perfil e mantenha pressionado um espaço da Tela de Início → **Editar → Adicionar Widget → Ninho**. Na Tela Bloqueada, mantenha pressionado → **Personalizar → Adicionar Widgets**. Os atalhos **Hora de focar** e **Minhas revisões** aparecem no aplicativo **Atalhos**; abrem a respectiva tela, sem iniciar o cronômetro nem registrar estudo por conta própria. Não é necessária integração com HealthKit para registrar estudos.

O resumo compartilhado contém apenas contagens, meta numérica e estado do cronômetro, em arquivo atômico de até 64 KiB. A extensão usa somente `NinhoWidgetSupport` (Foundation), sem biblioteca pessoal, ZIP, textos de perfil ou modelo de IA. A timeline prevê viradas de dia, próximos vencimentos e fim visual do foco; WidgetKit controla quando recarrega. O foco só é registrado pelo aplicativo ao reconciliar sua sessão. Se o resumo expirar ou o fuso mudar, o widget pede para abrir o Ninho. A aparência em tela bloqueada respeita a proteção de dados e a renderização do sistema. [Atualizações do WidgetKit](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date).

**Assinatura no Mac:** em **Signing & Capabilities**, selecione o mesmo Team no app e no target `NinhoWidgets`, e registre/habilite **App Groups** nos dois com `group.com.aless.ninho.ios`. O identificador vem do build setting compartilhado `NINHO_APP_GROUP`. Caso sua conta use outro grupo, atualize esse setting nos dois targets; no archive por script, passe `export NINHO_APP_GROUP="group.seu.identificador"`. App e extensão precisam estar provisionados para o mesmo grupo, e a extensão deve continuar embutida em `Ninho.app/PlugIns/NinhoWidgets.appex`. O gerador já define dependência, embedding, entitlements e URL scheme `ninho`. Este ambiente não registra grupos nem emite certificados. [App Groups da Apple](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.application-groups).

No Mac, execute os scripts abaixo e confira adicionar/remover widgets, claro/escuro/tintado, tamanhos de fonte, retomada após reiniciar, virada de data/fuso, pausa e conclusão do foco, abertura por Atalhos com app fechado e perfil ainda incompleto. A execução Swift/Linux não substitui essa validação do SDK e do aparelho.

No Mac, instale Xcode 26 ou posterior e abra `Ninho.xcodeproj`. O projeto resolve as dependências fixadas em `Package.resolved`.

```bash
bash scripts/build-macos.sh
bash scripts/test-macos.sh
```

No Windows, com o Docker Desktop iniciado, é possível testar somente o núcleo em Swift/Linux:

```powershell
docker run --rm --mount "type=bind,source=$($PWD.Path),target=/workspace" -w /workspace swift:6.2 swift test --jobs 2
```

O Windows não dispõe do SDK Apple: compilação nativa, testes no simulador, assinatura e instalação no iPhone permanecem pendentes de Mac/Xcode. O workflow em `.github/workflows/ios.yml` é manual e não foi publicado nem executado.

## Git

O `.gitignore` exclui caches Swift/Xcode, resultados, arquivos locais, certificados, provisionamento e dados pessoais. O scheme compartilhado, `Package.resolved`, os assets e as fixtures sintéticas permanecem versionáveis. A branch de trabalho é `dev`, com o remote `origin` do repositório iOS. Antes de atualizar no Mac, confira as alterações locais; a sincronização realizada nesta entrega está registrada em `devdocs/VALIDACAO.md`.

```bash
git status
git add .
git commit -m "Prepara Ninho para iPhone"
```

Consulte [LEIA-ME.md](devdocs/LEIA-ME.md), [BUILD-AND-TEST.md](devdocs/BUILD-AND-TEST.md) e [VALIDACAO.md](devdocs/VALIDACAO.md) para uso, recursos existentes e limites dos testes.


### Perfil e primeira abertura

Na primeira abertura, a coruja conduz dez telas de perguntas sobre seu nome, objetivos, prazos, rotina, tempo disponível e preferências de estudo. Essa recepção ocupa uma tela própria, sem os menus do aplicativo, e retoma do passo em que você parou. Depois há uma revisão final; a tela Hoje aparece somente após concluir e salvar o perfil. Tudo fica localmente e pode ser editado em **ícone de perfil no cabeçalho → Meu perfil e objetivos**. Ajustes e perfil são salvos automaticamente; o indicador confirma a gravação. O backup ZIP inclui o perfil e a conclusão dos tutoriais.

**Preparar meu plano local** organiza dias e blocos de estudo usando o perfil canônico e os registros atuais. O processamento é real, cancelável e leve, feito no aparelho. A assistente já vem no aplicativo: não exige Apple Intelligence, importação de modelos, servidor ou chat. É um motor analítico estatístico, sem treinamento ou geração de linguagem inventados. Ao editar o perfil, as sugestões usam as novas respostas; o plano salvo pode ser atualizado no mesmo local.

Cada tela apresenta dicas na primeira visita. O botão de interrogação permite rever seu tutorial; **Meu perfil → Rever tutoriais do aplicativo** reúne todos eles e permite reativá-los. A aparência escura usa superfícies neutras e as animações respeitam a preferência de movimento reduzido.

A validação desta entrega e as verificações ainda necessárias no Mac/iPhone estão em [VALIDACAO.md](devdocs/VALIDACAO.md).

### Acompanhamento e uso em segundo plano

O menu inferior abre **Hoje, Estudos, Foco, Revisões e Assistente**. O perfil no cabeçalho reúne objetivos, preferências, materiais, agenda e progresso. **Hoje** e **Minha assistente** mostram próximos passos com evidências e limites: revisões previstas, marcações suas, falta de prática registrada, dificuldade autoavaliada, horários habituais e pausas. Nenhum desses sinais é apresentado como atenção, domínio ou nota.

As visitas e o tempo ativo por tela ficam em `activity.json`, com até 90 dias de agregados e limite de 256 KiB. O tempo para em segundo plano e após 60 segundos sem interação; nunca é somado às sessões de estudo. No perfil você pode desligar a navegação local ou apagar os agregados. O backup compacto preserva esses agregados e a preferência de acompanhamento para reconstruir as análises; o formato completo antigo continua transferindo somente estudos, perfil, tutoriais e anexos.

No foco, **Avisar quando o foco terminar** pede autorização para um aviso silencioso. A contagem usa horários persistidos; o iOS pode suspender o processo e o tempo é reconciliado ao reabrir. Não há inferência contínua, áudio de manutenção ou promessa de execução permanente em segundo plano. A entrega do aviso depende dos ajustes de notificações e Foco do iPhone. Sons curtos não tocam quando outro áudio está ativo, e os materiais usam mistura de áudio. Ver [suspensão no iOS](https://developer.apple.com/documentation/uikit/extending-your-app-s-background-execution-time), [notificações locais](https://developer.apple.com/library/archive/documentation/NetworkingInternet/Conceptual/RemoteNotificationsPG/SchedulingandHandlingLocalNotifications.html) e [áudio ambiente](https://developer.apple.com/documentation/avfaudio/avaudiosession/category-swift.struct/ambient).

Os resultados atuais de Core, infraestrutura e runtime opcional estão em [VALIDACAO.md](devdocs/VALIDACAO.md). A compilação iOS e a avaliação real de widgets, notificações, áudio/PiP, memória e gestos exigem Mac/Xcode e iPhone.
