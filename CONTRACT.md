# Contrato de implementação

## Organização

- `Sources/NinhoCore`: modelos Codable/Sendable, regras, persistência, ZIP e contexto da assistente; testável em Linux.
- `Ninho`: SwiftUI app `@main NinhoApp`, `NinhoStore` ObservableObject/Observable no MainActor, recursos e integrações iOS.
- `Ninho/AI/AssistantView.swift`: `AssistantView(state: AppState)`; disponibilidade real, sem depender de LM Studio.
- Pacote local NinhoCore; iOS 26.0, Swift 6. JSON compatível com o AppState v2 do Windows; datas/IDs permanecem strings.

## Modelos e comandos

Tipos públicos: Settings, StudyProgram, Subject, Course, Lesson, ReviewCard, Exam, Material, StudySession, StudyTask, AppState. Propriedades `var`; inicializadores públicos com defaults. Enums Track, LessonStatus, Rating, CardFlag, Theme, SessionKind. O nome `Course` representa um módulo; StudyProgram representa Senado/Mauá.

`StudyEngine.validate(_:) throws`, `StudyEngine.apply(_:to:now:) throws -> AppState`, `StudyEngine.dueCards(in:at:limit:subjectId:)`, `StudyEngine.overview(in:at:)`. Todos estáticos. Comandos saveProgram/saveSubject/saveCourse/saveLesson/updateLesson/saveCard/reviewCard/flagCard/suspendCard/deleteCard/saveExam/deleteExam/saveTask/deleteTask/addSession/updateMaterial/removeMaterial/addMaterial/updateSettings.

Root implementa `StudyLibrary` actor (load/apply/importMaterial/materialURL/exportBackup/restoreBackup), `FocusTimer` persistível e suas regressões. Interface usa NinhoStore e não altera arquivos diretamente. O cronômetro é baseado em instantes, preserva pausa e vínculo com a aula, registra somente tempo efetivo, sem marcar aula concluída.

## Navegação e identificadores de interface

Tab bar: Hoje (`tab.today`), Estudos (`tab.studies`), Revisões (`tab.reviews`), Agenda (`tab.agenda`), Mais (`tab.more`). Tela Mais contém Materiais, Foco, Progresso, Íris e Ajustes.

- Cabeçalho/scroll: `screen.today`, `screen.studies`, `screen.reviews`, `screen.agenda`, `screen.more`, `screen.materials`, `screen.focus`, `screen.progress`, `screen.settings`, `screen.assistant`.
- Hoje: `today.calendar`, `today.study`, `today.review`, `today.focus`.
- Listas: `program.<id>`, `subject.<id>`, `course.<id>`, `lesson.<id>`, `material.<id>`, `card.<id>`, `exam.<id>`, `task.<id>`.
- Criar: `add.program`, `add.subject`, `add.course`, `add.lesson`, `add.card`, `add.exam`, `add.task`, `add.material`.
- Formulários: `form.name`, `form.title`, `form.description`, `form.question`, `form.answer`, `form.url`, `form.notes`, `form.save`, `form.cancel`.
- Aula: `lesson.status`, `lesson.notes`, `lesson.saveNotes`, `lesson.timer`, `lesson.addMaterial`, `lesson.addCard`.
- Revisão: `review.reveal`, `review.again`, `review.hard`, `review.good`, `review.easy`.
- Foco: `focus.start`, `focus.pause`, `focus.resume`, `focus.finish`, `focus.reset`, `focus.elapsed`.
- Preferências: `settings.name`, `settings.dailyMinutes`, `settings.theme`, `settings.reducedMotion`, `settings.save`, `settings.export`, `settings.restore`.
- Mais: `more.materials`, `more.focus`, `more.progress`, `more.assistant`, `more.settings`.
- Erros: `app.error`; aviso sucesso opcional `app.notice`.

Argumentos `--uitesting --disable-ai` usam ApplicationSupport separado com estado sintético, não o catálogo/progresso pessoal. A variável `NINHO_TEST_PROFILE` recebe um UUID exclusivo por teste e permanece igual ao terminar/reabrir o aplicativo. `--reset-test-data` limpa somente esse perfil de teste e é passado apenas no primeiro launch; `--uitesting` sozinho nunca reseta dados automaticamente. Testes de foco podem usar `--test-focus-seconds 2`, alterando apenas duração sugerida de teste, nunca registros de tempo falsos no perfil pessoal. O scheme XCTest usa o perfil separado `unit-host`; o target UI gera seus próprios UUIDs.

## Cronômetro portável

`FocusTimer` é um valor Codable/Sendable, com `snapshot: FocusSnapshot` (private set), `phase` e `isRunning`. Campos do snapshot: `sessionId`, `subjectId`, `lessonId`, `targetSeconds`, `accumulatedSeconds`, `startedAt: Date?`, `targetReachedAt: Date?`, `pendingSession: StudySession?`, `completed`. API mutante: `configure(subjectId:lessonId:minutes:)`, `start(at:)`, `pause(at:)`, `resume(at:)`, `reset()`, `finish(at:) -> StudySession?`, `acknowledgeCompletion(sessionID:)`; essas operações lançam erros compreensíveis. Consultas `elapsedSeconds(at:)` e `remainingSeconds(at:)` são puras.

`finish` conserva o mesmo UUID, duração e instante em `pendingSession` até confirmação. Persistir esse snapshot, aplicar `addSession` apenas se o ID ainda não estiver no estado, confirmar e persistir novamente. Depois da confirmação, `finish` retorna nil e `start` pode iniciar nova sessão. `reset` recusa descartar uma conclusão pendente; descarte do foco ainda ativo/pausado exige confirmação na interface. O limite é o alvo escolhido, no máximo 1440 minutos, e o tempo em pausa não conta. Alterar o vínculo/duração durante execução ou após tempo acumulado é recusado.

Root fornecerá UI fixture inicial com programa `test-program`, matéria `test-subject`, módulo `test-course`, aula `test-lesson`, cartão `test-card`, todos sintéticos, e preferência name `Teste`. Materiais PDF sintéticos ficam no bundle de testes se usados; seleção de arquivos externa deve ser tratada como integração nativa não demonstrada sem execução iOS.

`--with-test-material`, apenas junto de `--uitesting`, importa o recurso sintético `test-material.pdf` pelo método real `StudyLibrary.importMaterial`, vinculado a `test-subject`/`test-lesson`. O argumento não insere material diretamente no JSON e nunca é passado no relaunch de persistência/remoção. O arquivo não contém conteúdo pessoal ou do Estratégia. A linha `lesson.time` informa segundos abaixo de um minuto e a contagem de sessões, inclusive depois de reabrir o app.

`--test-review-due-seconds 15`, apenas no seed de `--uitesting`, coloca `dueAt` do cartão sintético no futuro próximo. O relógio do sistema, a regra real de revisão e o perfil pessoal permanecem inalterados. Os testes aguardam o tempo real para verificar que a fila vazia se atualiza sozinha e ao voltar do segundo plano. Os seletores `material.subject` e `material.lesson` permitem verificar que alterações ainda não salvas sobrevivem a abrir/fechar a prévia.
