# Auditoria de segurança — 15/09/2026

Escopo: dependências resolvidas do NinhoCore, workflow iOS e entradas de arquivos/backup do aplicativo. A revisão foi feita em Windows 11 com Swift 6.2.4 em Docker/Linux. Não houve publicação, execução do workflow remoto, acesso a dados pessoais nem mudança de Git.

Os pinos Swift consultados já contêm as correções conhecidas encontradas. O workflow recebeu correções de configuração e versões oficiais mais recentes, mas ainda há avisos nas dependências transitivas dessas Actions. Isso não constitui uma declaração de ausência de vulnerabilidades.

## Dependências Swift

| Dependência resolvida | Aviso consultado | Resultado |
| --- | --- | --- |
| swift-crypto 4.5.2 | [GHSA-8q93-f6xh-4f6f / CVE-2026-43823](https://github.com/apple/swift-crypto/security/advisories/GHSA-8q93-f6xh-4f6f): double-free ao rejeitar chave pública RSA | A versão corrigida é 4.5.1; o pino atual já inclui a correção. |
| swift-crypto 4.5.2 | [GHSA-9m44-rr2w-ppp7 / CVE-2026-28815](https://github.com/apple/swift-crypto/security/advisories/GHSA-9m44-rr2w-ppp7): tamanho inválido de ciphertext X-Wing HPKE | Corrigido em 4.3.1; o pino atual já inclui a correção. |
| swift-asn1 1.7.2 | [GHSA-w8xv-rwgf-4fwh / CVE-2025-0343](https://github.com/apple/swift-asn1/security/advisories/GHSA-w8xv-rwgf-4fwh): falha ao analisar BER/DER malformado | A versão corrigida indicada pelo mantenedor é 1.3.1; o pino atual já inclui a correção. |
| ZIPFoundation 0.9.20 | [GHSA-c2cc-3569-6jh2 / CVE-2023-39138](https://github.com/advisories/GHSA-c2cc-3569-6jh2): path traversal | Afeta versões até 0.9.17; corrigido em 0.9.18. O pino atual já inclui a correção. |

Não houve atualização de pacotes sem justificativa de segurança. `Package.swift` fixa as duas dependências diretas e `Package.resolved` registra também o ASN.1 transitivo com as respectivas revisões.

O produto `Crypto` é dependência do núcleo somente no Linux/Windows. No iPhone, o código usa CryptoKit do sistema. O uso no Ninho se limita a SHA-256; não há chamadas RSA, HPKE ou ASN.1. O pacote swift-asn1 está resolvido no grafo do swift-crypto, mas o target upstream que o utiliza é CryptoExtras, que o Ninho não usa. Essa observação restringe o alcance das falhas consultadas; não avalia vulnerabilidades do próprio sistema operacional.

A consulta OSV com o ecossistema `SwiftURL` não retornou avisos para os três pinos atuais. Foram usadas versões antigas como controles. Houve uma lacuna do catálogo: o aviso de RSA publicado pelo mantenedor do swift-crypto estava disponível no repositório oficial e não apareceu no OSV nem no endpoint global de advisories consultado. Por isso a conclusão considera também os avisos oficiais dos mantenedores; um retorno vazio do scanner sozinho não foi tratado como prova.

## Workflow preservado e endurecido

| Action | Versão e revisão oficial fixadas |
| --- | --- |
| actions/checkout | v7.0.1 — `3d3c42e5aac5ba805825da76410c181273ba90b1` |
| actions/upload-artifact | v7.0.1 — `043fb46d1a93c77aae656e7c1c64a875d1fc6a0a` |

As versões e SHAs foram conferidos nas APIs oficiais de releases e tags dos repositórios. Fontes: [releases do checkout](https://github.com/actions/checkout/releases), [releases do upload-artifact](https://github.com/actions/upload-artifact/releases).

Foram substituídas referências móveis `@v4` por SHAs completos. A permissão permanece `contents: read`; o checkout agora usa `persist-credentials: false`. A publicação de resultados se limita ao glob constante `TestResults/*.xcresult`, exclui arquivos ocultos e expira em sete dias. O acionamento manual, a execução dos testes Apple e a coleta dos resultados foram preservados. Isso segue a orientação de [segurança de uso do GitHub Actions](https://docs.github.com/en/actions/reference/security/secure-use). Não foram adicionados tokens, certificados ou permissões de escrita no repositório.

## Avisos ainda presentes nos Actions oficiais

Foram consultados os `package-lock.json` públicos nas revisões exatas, excluindo entradas marcadas como desenvolvimento e consultando pares únicos de pacote/versão no OSV. **Essas são dependências de execução das Actions, não dependências npm do aplicativo Ninho.** A inspeção dos metadados não é uma análise completa de alcançabilidade nem uma SBOM atestada do bundle compilado.

| Action | Entradas de pacote/versão consultadas | Entradas com avisos |
| --- | --- | --- |
| checkout v4, revisão da tag no momento da consulta | 30 | 4 |
| checkout v7.0.1 fixado | 24 | 1 |
| upload-artifact v4, revisão da tag no momento da consulta | 159 | 17 |
| upload-artifact v7.0.1 fixado | 149 | 7 |

O checkout v7.0.1 registra `undici@6.27.0`, que corresponde a estes avisos, corrigidos no ramo 6 em 6.28.0:

- [GHSA-8xcm-r25x-g524](https://osv.dev/vulnerability/GHSA-8xcm-r25x-g524): dessincronização de resposta em uma combinação de retry interceptor e encaminhamento de resposta por proxy.
- [GHSA-m8rv-5g2x-5cg5](https://osv.dev/vulnerability/GHSA-m8rv-5g2x-5cg5): injeção de CRLF pelo tipo de um corpo Blob simulado controlado pelo chamador.
- [GHSA-v3r7-h72x-cjcm](https://osv.dev/vulnerability/GHSA-v3r7-h72x-cjcm): injeção de atributos ao construir cookies com campos não confiáveis.

O bundle oficial do checkout contém código do Undici; a versão acima foi obtida do lockfile. Não foi demonstrado que este workflow forneça entradas controladas por atacante aos caminhos vulneráveis. A presença de uma função no bundle não prova que seja chamada no fluxo, e a ausência de reprodução também não prova que seja inalcançável.

O upload-artifact v7.0.1 ainda registra as seguintes correspondências no OSV:

| Pacote/versão | IDs dos avisos |
| --- | --- |
| brace-expansion 1.1.12 e 2.0.2 | GHSA-3jxr-9vmj-r5cp; GHSA-f886-m6hf-6m8v; GHSA-mh99-v99m-4gvg; GHSA-rgw5-rvv9-x895 |
| brace-expansion 5.0.3 | Os quatro anteriores; GHSA-jxxr-4gwj-5jf2 |
| fast-xml-builder 1.0.0 | GHSA-5wm8-gmm8-39j9 |
| fast-xml-parser 5.4.1 | GHSA-8gc5-j5rx-235r; GHSA-gh4j-gqv2-49f6; GHSA-jp2q-39xq-3w4g |
| lodash 4.17.23 | GHSA-f23m-r3pf-42rh; GHSA-r5fr-rjxr-66jc |
| undici 6.23.0 | GHSA-2mjp-6q6p-2qxm; GHSA-35p6-xmwp-9g52; GHSA-4992-7rv2-5pvq; GHSA-8xcm-r25x-g524; GHSA-f269-vfmq-vjvj; GHSA-g8m3-5g58-fq7m; GHSA-m8rv-5g2x-5cg5; GHSA-p88m-4jfj-68fv; GHSA-v3r7-h72x-cjcm; GHSA-v9p9-hfj2-hcw8; GHSA-vrm6-8vpv-qv8q; GHSA-vxpw-j846-p89q |

Os avisos incluem processamento de glob, XML, caminhos/objetos e HTTP. O glob deste workflow é constante; não foi encontrado um caminho que entregue entrada externa aos usos vulneráveis de XML ou Lodash. A análise não demonstra ausência de todos os caminhos possíveis nas Actions. Exemplos de fontes primárias consultadas: [brace-expansion](https://osv.dev/vulnerability/GHSA-3jxr-9vmj-r5cp), [fast-xml-builder](https://osv.dev/vulnerability/GHSA-5wm8-gmm8-39j9), [fast-xml-parser](https://osv.dev/vulnerability/GHSA-gh4j-gqv2-49f6), [Lodash](https://osv.dev/vulnerability/GHSA-f23m-r3pf-42rh).

Na data da consulta, os releases oficiais mais recentes conferidos ainda continham essas correspondências. O workflow não foi removido ou desabilitado para esconder os resultados, nem os bundles dos mantenedores foram substituídos por uma cópia local. A remoção desses resíduos depende de um release upstream corrigido ou de uma substituição funcional avaliada separadamente. É necessário repetir a consulta ao atualizar os SHAs.

O arquivo `.github/dependabot.yml` prepara propostas semanais de atualização dos pacotes Swift e das GitHub Actions, sem fusão automática. Ele terá efeito depois de ser publicado na branch padrão do repositório e o serviço estar disponível no GitHub; não houve ativação remota nesta revisão.

## Entradas e armazenamento examinados

A revisão do código conferiu validação de IDs, referências e URLs; nomes de material restritos a UUID/extensão; rejeição de links simbólicos; limites por arquivo e por backup; leitura em blocos; tamanho realmente extraído; CRC e SHA-256; correspondência entre manifesto e arquivos; restauração em nova geração com troca do índice somente depois da validação. O ZIP não é extraído diretamente em caminhos fornecidos pelo arquivo. A revisão não encontrou outro defeito concreto que exigisse alteração de comportamento nesta rodada.

Os testes reais da biblioteca cobrem ZIP com caminhos/entradas inválidas, arquivos truncados ou adulterados, CRC/hash inválidos, links, limites, recuperação de arquivos ausentes e preservação do perfil anterior. O processamento por PDFKit, AVKit, QuickLook e FoundationModels ainda exige SDK Apple e testes no dispositivo; o Linux não executou esses frameworks.

## Verificação e evidências

- Núcleo compilado em Swift 6.2.4/Linux; **23 testes StudyLibrary, zero falhas**. Log: `TestResults/security-library-20260915.log`.
- **14 testes Python da estrutura, zero falhas**, incluindo regressão para SHAs imutáveis e checkout sem persistência de credenciais. Log: `TestResults/security-scaffold-20260915.log`.
- Geração do projeto Xcode conferida com `python scripts/generate_project.py --check`: três arquivos sem diferenças.
- Os 94 testes completos e a cobertura previamente registrados em `VALIDACAO.md` não foram repetidos nesta auditoria; não houve mudança em fontes Swift nem em pinos Swift.
- Sem compilação Apple, simulador, iPhone ou execução remota do workflow nesta rodada.

As respostas brutas locais estão em `.cache/security-audit-20260915/`, com URL pública, data UTC, consulta e resultado. `summary.json` reúne os pinos e correspondências dos dois Actions usados pelo iOS. Os metadados enviados às APIs foram exclusivamente nomes, versões e URLs de pacotes públicos. Os originais dos arquivos alterados estão no subdiretório `before/`. A cópia local dessas evidências não é adicionada ao Git.
