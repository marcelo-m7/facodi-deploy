# Aceite e próximos passos — FACODI API, 2026-10-07

## Estado pos-merge e autorizacao de producao

- O responsavel confirmou o backup de producao concluido e autorizou promover
	o codigo operacional validado em 2026-10-07. O backup deixa de ser pendencia
	de autorizacao; nao houve inspeccao independente dos seus artefatos nesta
	sessao. Continuam aplicaveis o par PostgreSQL/filestore e o recurso Coolify
	existente do [runbook](../operations.md).
- API [#22](https://github.com/marcelo-m7/facodi-api/pull/22), Learning
	[#200](https://github.com/marcelo-m7/facodi-learning/pull/200) e deploy
	[#264](https://github.com/marcelo-m7/facodi-deploy/pull/264) foram mesclados.
	A composicao aceita e `407cf44cef3960a0b0fe7985aebaf75cbadf0096`, com API
	`4671ceeab158b9a54f359196156d43372ed146a1` e Learning
	`2a3a83cf1f518bee1edff7bf4de15ed423255117`. Deploy #263 foi fechado;
	nao deve originar rebuild separado.
- CI pos-merge passou nesse SHA: [API/native Learning](https://github.com/marcelo-m7/facodi-deploy/actions/runs/37687855264)
	e [runtime/browser/restore](https://github.com/marcelo-m7/facodi-deploy/actions/runs/37687855440).
	A suite pura API tem 112 testes passando e 1 skip; as suites nativas
	passaram com 29 testes API e 425 Learning. Codoo #46 integra o gitlink
	aceito e a correcao de identidade, com 22 testes e CodeQL passando.
- Releitura guardada de `https://facodi.com` / `facodi` confirmou API
	`19.0.3.2.0`, Learning `19.0.2.1.0` e health publico `19.0.3.2.0`.
	Jobs Learning 1/2 estao `completed`, provider `supabase_edge`, com resultados
	associados. Esses estados nao comprovam nova aquisicao YouTube ou o
	conteudo/provider de cada resultado.
	- Smoke publico em browser apos a autorizacao: HTTP 200 em `/web/login`, `/`,
	  `/pt/`, `/es/`, `/fr/`, `/courses`, `/forum` e `/facodi/api/v1/health`;
	  health `status=ok`, versao `19.0.3.2.0`. Isso nao substitui o aceite
	  autenticado de `/odoo` nem identifica a imagem produtiva.
- Gate Python permanece `false`. O cron resolvido por
	`facodi_api.ir_cron_facodi_pipeline_process` e o ID 26: a leitura com
	`active_test=False` confirmou `active=False`. Crons 20/25 permanecem ativos.
	Promover codigo nao ativa automaticamente provider, gate, cron ou publicacao.
- Nao ha acesso Coolify configurado nesta sessao nem deployment registrado
	no GitHub do deploy. Nao foi iniciado novo rollout nem comprovado digest
	da imagem produtiva. O canary Python continua **NOT_EXECUTED**, aguardando
	identidade da imagem e execucao operacional guardada; backup e autorizacao
	nao devem continuar listados como bloqueios.
- Limpeza deve remover somente branches desta entrega cujo conteudo esteja
	integrado. Preservar historico, workspaces principais, alteracoes locais,
	snapshots privados e volumes produtivos; nao fechar criterios de backlog
	que continuam sem implementacao ou prova.

## Supabase FACODI — mecanismos mínimos atuais

Após a separação definitiva do Open2, o projeto Supabase FACODI
`bhfywztfyidvrlarebmg` possui uma superfície Edge mínima e explícita:

- `v3_analyze_learning_resource`: análise educacional idempotente com revisão
  humana posterior no Odoo;
- `v3_discover_resource_metadata`: descoberta de metadata sem publicação;
- `v3_ingest_youtube_video`: ingestão canônica de identidade/metadata do
  YouTube, persistindo evidência em `public.facodi_processing_jobs`;
- `v2_ingest_youtube_video`: alias temporário de compatibilidade que executa
  o mesmo handler FACODI v3, sem depender de schema ou RPC do Open2.

As funções Open2 `v2_process_video_pipeline`,
`v2_sync_object_to_odoo`, `v2_push_odoo_learning_object` e a restante
topologia v2 histórica não fazem parte do runtime FACODI. Os antigos helpers de
fila/RPC/pipeline foram removidos da árvore deployável do repositório
`facodi-supabase`; as evidências Open2 permanecem apenas no histórico Git.

A fonte Supabase consolidada está em
`c63f94ac2f11394d35343324bceb05a7b5edf30f`. O código Odoo candidato usa API
`b830811cb2d4bd408e1811d5d5de3ab9d181b82c` (`19.0.3.3.0`) e Learning
`1a4bb096dbc96f800732d50f1892dfa69f3f74ed` (`19.0.2.2.0`). A API resolve
`video.ingest` para `v3_ingest_youtube_video` por padrão; o override
`FACODI_SUPABASE_VIDEO_INGEST_FUNCTION` fica reservado à compatibilidade
explícita. O hook automático de create/write do Learning continua desligado sem
esse override, portanto esta mudança não reativa silenciosamente o export legado.

No Supabase, as quatro funções foram recompiladas/deployadas contra os helpers
atuais: analysis v9, metadata v7, ingest v3 e alias v2 v3. Não houve mudança de
schema nesta etapa. A publicação editorial continua exclusivamente no Odoo.

<details>
<summary>Historico integral: todas as secoes abaixo registram rodadas anteriores</summary>

Todo o conteudo deste bloco, ate o final do documento, e historico. Inclui as
secoes posteriores de bloqueadores, proximos passos e gates locais: nao use
esses estados antigos para inferir pendencias atuais de backup, autorizacao,
merge ou rollout. O estado pos-merge acima e o registro atual desta entrega.

## Auditoria inicial: estado observado e candidata local

Esta seção registra a descoberta inicial; o estado pos-merge acima prevalece.
PRs API #19, Learning #198 e deploy #262 já estavam mesclados.
A candidata desta auditoria ainda não identificava uma imagem produtiva saudável.
Nenhuma escrita remota, habilitação de pipeline ou alteração de permissões foi
feita nesta rodada. Fonte local, versão instalada e identidade de imagem são
evidências diferentes.

### Instância e ambiente

- Alvo confirmado pelo conector compartilhado: `https://facodi.com`, banco
	`facodi`. A consulta de identidade foi corrigida para selecionar o UID
	autenticado, não o primeiro usuário visível; releitura confirmou igualdade.
- Versões instaladas observadas: API `19.0.3.1.0`, Learning `19.0.2.0.0`,
	AI `19.0.2.0.0`, AI Learning `19.0.1.2.0`, theme `19.0.10.89.0`.
- Browser público respondeu health v1 com `19.0.1.0.0`, divergente da versão
	instalada. A candidata API `19.0.3.2.0` lê o manifest carregado. Health não
	comprova SHA/digest de imagem nem readiness de providers.
- Gate API `false`, cron API inativo, provider Learning `supabase_edge`;
	crons Learning e AI Learning ativos. Eventos API: 0; jobs Learning: 2;
	jobs AI Learning: 0. Não houve leitura de payload privado de jobs.
- O usuário de inspeção não dispõe de Operator para ler runs. Browser anônimo
	recebeu 401 em v2; o cliente HTTP comum recebeu Cloudflare 403. Essa resposta
	de infraestrutura não é uma resposta contratual do controller.
- Schema REST Supabase acessível em leitura; isso não identifica as versões
	efetivamente implantadas das Edge Functions. Segredos não foram registrados.
- YouTube local adquiriu transcrição real para `4GVbqYFmGBw` e `9-WOBr534pQ`;
	replay da primeira chave conservou document ID/checkpoint. Duração não foi
	medida: não constitui aceite de vídeo longo, canary Odoo ou publicação.
	O `YOUTUBE_IP_BLOCKED` produtivo abaixo é evidência histórica, não uma falha
	reproduzida nesta rodada nem um bloqueio de todos os ambientes.
- Sem acesso Coolify/digest, backup produtivo emparelhado, provider LLM/custos,
	benchmark de recuperação ou permissão GitHub Project. Produção YouTube:
	**NOT_EXECUTED** nesta rodada; não foi substituído por transcrição manual.

### Matriz de capacidade

`Sim` indica implementação existente, não aceite produtivo. `Parcial` limita a
afirmação ao alcance descrito. Testes abaixo são de candidata descartável;
consultar o registro de validação para falhas e resultados finais. `Contrato`
remete ao README API; `Plano` às decisões incrementais desta seção.

| Capacidade | Planejado | Implementação | Prova disponível | API | Odoo | Frontend | Docs | Dívida | Próxima ação |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Engine independente | Sim | Core puro | Suite pura | v2 fachada | ORM adapter | Backend | Contrato | Paridade externa | Providers |
| Manual/Markdown | Sim | Sim | Pure/HTTP/ORM | Intake | Run | Wizard | Contrato | Canary | Privado |
| Documento | Sim | Parcial | Normalização | Intake | Fonte | Wizard | Contrato | Attachments autorizados | ACL/limites |
| YouTube automático | Sim | Sim | Local real + limites | Intake | Adapter | Wizard | Auditoria | Transporte produtivo | Canary guardado |
| Transcript manual | Sim | Sim explícito | HTTP/ORM | input | Revisão filha | Backend | Contrato | Não confundir aquisição | Manter proveniência |
| Normalização/chunks | Sim | Sim | Pure/checkpoint | Run | Projeção | Resultado | Contrato | Volume/duração | Benchmark |
| Enriquecimento metadata | Sim | Sim | Pure/ORM | Run | Resultado | Review | Contrato | Não é LLM | Capabilities |
| Enriquecimento LLM | Sim | Parcial/legado | Sem canary atual | Provider | AI/Supabase | Review | Plano | Provider real/custos | Adapter contratual |
| Snapshot catálogo | Sim | Parcial, cursos até 50 | ORM | Intake | ACL-visível | Backend | Contrato | UC/outcomes incompletos | Snapshot versionado |
| Matching lexical | Sim | Sim | Pure | Resultado | Propostas | Review | Contrato | Pesos fixos/confidence | Explicar componentes |
| Matching semântico | Sim | Não | Nenhuma | Não | Não | Não | Plano | Embeddings/avaliação | Dataset e baseline |
| Intake async | Sim | Sim | HTTP 202/scheduler | v2 | Run | Backend | Contrato | Canary | Não self-HTTP |
| Identidade imutável | Sim | Sim | Pure/ORM | v2 | Source/provider/actor | Backend | Contrato | Cutover | Preservar |
| Idempotência/replay | Sim | Sim | Pure/HTTP/ORM | Chave/revisão | Locks/receipts | Backend | Contrato | Não exactly-once rede | Recovery |
| Checkpoints | Sim | Sim | Spies ingest/normalize/enrich | Retry | Storage | Estado | Contrato | Crash em processo | Failure injection |
| Retry/budget | Sim | Sim, limite 20 | Pure/ORM | retry | Tentativas | Backend | Contrato | p95/recovery | Benchmark |
| Cancel | Sim | Parcial, fronteira transacional | ORM/consumer | cancel | Estado | Backend | Contrato | Não interrompe IO ativo | Deadline/cancel |
| Waiting input | Sim | Sim | ORM | input | Revisão filha | Backend | Contrato | UX/externalcanary | Validar |
| Review/publicação | Sim | Sim | HTTP/ORM | approve | Review + slide nativo | Backend/Website | Contrato | Canary privado | Guardas |
| Consumidor Learning | Sim | Opt-in | Native consumer | Fachada ORM | Um job/um run | Backend | Contrato | Provider ativo legado | Canary/paridade |
| Webhooks autenticados | Sim | Candidata corrigida | Pure/native/HTTP | v1 | Evento após auth | Não | Contrato | Config/replay dedup | Não promover sem secrets |
| Version health | Sim | Candidata corrigida | Native/HTTP | v1 | Manifest | JSON | Contrato | Não é digest | Imagem verificável |
| Learning Object genérico | Sim | Não como contrato completo | Nenhuma | Sem rota LO | Slides/resultados existem | Parcial | Plano | Identidade/versões | Referência incremental |
| Relações consultáveis | Sim | Parcial | Curriculum/mapping native | Sem grafo genérico | Coverage/assignments | Currículo | Plano | Relações tipadas/proveniência | Read model |
| Estrutura educacional gerada | Sim | Não | Nenhuma | Não | Composição manual | Currículo | Plano | Proposta/review/rollback | Não auto-publicar |
| Project trabalho humano | Sim | Não; mirror técnico atual | Mirror existente | Run | Project + 3 subtasks/run | Project | Plano | Não conforme intenção | Projeção humana |
| API discovery/OpenAPI | Sim | Não | Nenhuma | Sem capabilities/OpenAPI | Não | Não | Plano | Contrato consultável | Specs executáveis |
| Restore | Sim | Descartável comprovado antes | Gate local anterior | Não | DB + filestore | Browser anterior | Histórico | Backup produtivo | Par emparelhado |

### Contrato real e recuperação

Rotas existentes: GET `/facodi/api/v1/health`; POST v1 `webhook/supabase`
e `webhook/stripe`; POST `/facodi/api/v2/pipeline/runs`; GET de um run e
POST `retry`, `cancel`, `input`, `approve` nesse run. Não existem hoje rotas
`/jobs`, `/sources`, `/learning-objects`, `/matches`, capabilities ou OpenAPI.
Payloads, bearer, campos e respostas estão no [README API](../../addons/facodi-api/README.md).
V2 exige bearer, Operator e gate; aprovação exige Reviewer/review nativo.
Entrada aceita não é editada: correção de transcript cria revisão filha.

Core: `ContentSource`, `ContentDocument`, `EnrichedDocument`, `CatalogSnapshot`,
`TargetEntity`, `MappingCandidate`, `MappingResult`, `PipelineRun`.
Etapas: ingest, normalize, enrich, map. Fingerprint de checkpoint vincula
source/catalog/provider/pipeline version. Garantia: execução at-least-once
com efeitos idempotentes, não entrega exactly-once de rede.

| Cenário | Evidência / limite |
| --- | --- |
| A: sucesso | Pure, native e HTTP; vídeo externo local separado de handoff |
| B: falha antes ingest | Retry sem checkpoint de documento fictício |
| C: falha enrich | Retry reutiliza ingest/normalize; spies impedem repetição |
| D: falha map | Retry mantém call counts ingest/normalize/enrich em 1 |
| E: duplicação | Chave/payload/revisão, concorrência e replay ORM/HTTP |
| F: cancel | Estado/consumer provados; interrupção de IO ativo não provada |
| G: timeout/rede | Limites/erros seguros; browser403 separado do contrato |
| H: segredo ausente | Webhook503, assinatura ausente/inválida401, nenhum evento |
| I: input/review | Filho imutável, revisão humana, publicação canônica única |
| J: crash/restart | Persistência/restart anteriores; crash em toda fronteira e p95 pendentes |

Assinaturas usam corpo exato e limite de 262144 bytes: Supabase HMAC-SHA256;
Stripe SDK oficial com tolerância 300 segundos. Timestamp expirado/tamper são
testados. Replay dedup de evento continua pendente: não fecha API #2 inteiro.
Configuração de signing secrets é pré-condição de rollout, não uma razão para
voltar a aceitar webhook sem autenticação.

### Arquitetura incremental, ainda não implementada

Não criar um segundo engine em Learning ou AI. O core API aceita fonte,
catálogo, provider e política versionados e retorna artefatos/propostas sem
depender de Odoo. Adapters internos usam a fachada ORM comum, nunca self-HTTP.
Learning conserva histórico, revisão, conteúdo canônico e projeções; AI mantém
serviços reutilizáveis fora desse domínio.

1. **Learning Object reference.** Estender proveniência existente com identidade
	`(source_kind, canonical_source_id, revision)`, hash, artifact/checkpoint IDs,
	provider/pipeline/policy versions, actor e scope. Vincular resultados e
	`slide.slide`, sem curso/progresso paralelo. Migration aditiva preenche só
	fatos verificáveis; histórico desconhecido permanece legado. Aceite: replay
	conserva identidade, revisão cria filho, public não lê artefato privado.
2. **Relações consultáveis.** Reusar mapping, coverage e assignments; adicionar
	apenas tipos não representáveis, com origem, evidência, status e versão.
	Read model consulta por LO/unidade/curso e revalida ACL dos destinos; não
	abrir ACL de auditoria. Aceite: revisão não expõe destino privado, reversão
	preserva histórico, replay não duplica relação.
3. **Matching explicável.** Baseline lexical atual: concept .30, tag .25,
	name .20, summary .10, max 1, threshold .25, top 5; confidence é score,
	não probabilidade calibrada. Introduzir política versionada de pesos e
	thresholds, evidência por componente e razões de exclusão. Outcomes e
	prerequisites exigem catálogo real; embeddings exigem dataset revisado.
	Congelar política no run. Aceite: ranking determinístico explicado,
	comparação com baseline multilíngue e isolamento entre atores.
4. **Geração revisável.** LOs/relações/matches propõem unidades, agrupamentos e
	composição pelos modelos Learning existentes. Preview não altera conteúdo;
	reviewer aprova diff idempotente, auditável e reversível. Nenhuma proposta
	publica automaticamente. Aceite: rejeição não muda progresso/curso, replay
	não duplica itens e rollback preserva evidência.

### Project: trabalho humano

O código ainda cria Project privado, tarefa principal e três subtarefas técnicas
por run. Isso é legado, não a política desejada. Não foi removido nesta candidata.
Estados, checkpoints e tentativas técnicos ficam em runs/jobs/logs.

Projetar somente revisão editorial, validação de fonte, decisão curricular,
bloqueio operacional e aprovação/publicação que exijam pessoa. Chave idempotente
`(run_id, revision, human_reason)`; tarefa tem referência, responsável/papel,
contexto, decisão e prazo, sem segredo/transcript privado. Replay atualiza a
mesma pendência; aprovação/cancel encerra ou arquiva sem excluir histórico.
Mirror legado só fica read-only/arquivado após reconciliação. Testes: zero
tarefa em etapa automática, uma por motivo humano, retry/replay/cancel sem
duplicação e isolamento entre atores. Dependência: eventos de decisão do run.

### Consumidores legados classificados

| Call site | Papel real | Decisão incremental |
| --- | --- | --- |
| Learning `analysis_job` | Metadata/Supabase; cron exclui `odoo_python` | Preservar até paridade/canary |
| Learning `pipeline_adapter` | Um job/um run, sem engine próprio | Manter fachada ORM, sem self-HTTP |
| Learning discovery/YouTube | Metadata Supabase | Separar discovery de análise |
| Learning `slide_slide` export | Origem API exclui export legado | Manter origem/provider e teste de edições |
| AI Learning `slide_extensions` | Enfileira job por course/slide | Migrar intake após equivalência |
| AI Learning `learning_suggestion` | Cron, `_process`, profile, `facodi.ai.service._run` | Provider adapter, preservar filas/histórico |
| AI audit/settings/profile | Sanitização/config/proveniência | Conservar serviços fora de Learning |
| AI análises/suggestions/mappings | Histórico de revisão | Preservar consulta; não reprocessar |
| Supabase `v3_analyze_learning_resource` | Análise externa | Validar contrato/provider/versionamento |
| Supabase `v3_discover_resource_metadata` | Discovery | Metadata não é análise educacional |
| Supabase `v2_process_video_pipeline`, push/sync | Orquestração/export legado | Impedir dois workers/publicações |

Python produtivo de Learning não contém chamadas diretas a
`facodi.ai.service`; referências históricas em testes não são consumidores.
Transporte outbound Supabase com `apikey` não autentica webhook inbound:
a branch concorrente desse transporte é entrega distinta, não sobrescrita aqui.

Learning já tem sugestões determinísticas de coverage versionadas e review-only
([#23](https://github.com/marcelo-m7/facodi-learning/issues/23), PR #194 mesclado).
Isso não é o matching lexical do core API nem um grafo genérico. A evolução deve
reusar `course-profile-v1`, title similarity e coverage, preservando decisões
terminais. O bloqueador HITL de #23 permanece aberto.

Coordenação existente: [Program #7](https://github.com/marcelo-m7/facodi-monorepo/issues/7)
e [Increment #12](https://github.com/marcelo-m7/facodi-monorepo/issues/12).
`facodi-monorepo` é control plane de engenharia; deploy é control plane de
release; somente commits aprovados/mesclados podem ser promovidos. A candidata
local não autoriza promoção nem substitui esses owners.

### Próximos cinco passos

| Ordem | Dono / issue | Dependência | Aceite | Teste |
| --- | --- | --- | --- | --- |
| 1 | API/Deploy #2,#4,#13 | Signing secrets, review/CI exato | Health real, webhook fail-closed; dedup ainda aberto | Pure/native/HTTP/assinatura expirada |
| 2 | Operações/API #6,#13 | Digest, backup DB+filestore, Operator/provider | Canary YouTube privado, aquisição/custo, sem cutover | Desktop/mobile, retry/cancel/recovery/p95, vídeo longo medido |
| 3 | API #8 + Learning #23, Increment #12 | UC/outcomes/dataset reais | LO/relações/política explicável aditivos | Replay/revisão/ACL, ranking explicado, migration |
| 4 | API/Learning #5,#9 | Eventos humanos, relações/matching | Project humano e estrutura proposta/revisável | Zero tarefa automática, replay/cancel, review/rollback |
| 5 | API #11 + Learning/AI/Supabase, deploy #255-258 | Canary/paridade | Cutover opt-in, histórico, schedulers exclusivos | Legacy/provider E2E, upgrade/restore/browser |

Project não sincronizado: token sem escopo do board. Página pública sem Projects
não prova inexistência de board privado. Requer acesso `project` ao board correto;
não criar board ou duplicar issues como substituição. Correções parciais não
fecham épicos nem critérios produtivos.

### Validação e publicação desta candidata

- Root: 22 testes passaram; identidade autenticada: 3 focados.
- Baseline API pure: 111 passed, 1 skipped (ORM fora do runtime nativo).
	Pin API mesclado: 112 passed, 1 skipped, após teste adicional do transporte.
- Deploy/migração/preflight: 66 unittest passaram; subset pytest: 61.
- Baseline native: API 27 + Learning consumer 18 passaram.
- Baseline isolada antes dos merges: **29 API + 423 Learning native, zero falhas/erros**.
	HTTP health/segredo ausente sem evento, fresh install, upgrade legado,
	dois upgrades, concorrência, review/publicação e restart passaram.
- Learning ampliado: primeira rodada 5 falhas/4 erros; segunda 4 falhas/0 erros;
	terceira verde. Não removidos cenários/skips. Corrigidos criação interna de
	capture/group/occurrence após source write authorization, assertions antigas
	de bootstrap/prefill e fallback authored OpenGraph; ACL permanece read-only.
- [API PR #22](https://github.com/marcelo-m7/facodi-api/pull/22):
	`4671ceeab158b9a54f359196156d43372ed146a1`, manifest `19.0.3.2.0`.
- [Learning PR #200](https://github.com/marcelo-m7/facodi-learning/pull/200):
	`2a3a83cf1f518bee1edff7bf4de15ed423255117`, manifest `19.0.2.1.0`.
- Esses merges incorporam também as alterações concorrentes aprovadas pelo owner:
	Supabase outbound usa secret key em `apikey`, sem bearer; export v2 de vídeo
	permanece desligado por padrão e exige função de compatibilidade explícita.
	Os registros/histórico legados continuam preservados. A fixture de plataforma
	verifica default sem chamada e opt-in explícito, sem executar transporte real.
- CI dos pins mesclados: [API/full Learning](https://github.com/marcelo-m7/facodi-deploy/actions/runs/37685198494)
	e [plataforma/browser/restore](https://github.com/marcelo-m7/facodi-deploy/actions/runs/37685198454).
	Seus resultados devem ser associados ao SHA próprio, não ao baseline anterior.
- Imagem canônica inicial passou migração, consumer 18 e browser desktop/mobile,
	narrow320, portal e backend. D2 HTTP passou; invocação interrompida por ausência
	do diretório screenshot D2. Repetição com variável correta mantém todos os gates.
- Repetição completa: **PASS imagem canônica, D1/D2 browser desktop/mobile e
	restore emparelhado DB+filestore**, preservando Website, progresso, currículo,
	reviews e attachment. State foi exclusivamente descartável.
- Compose encaminha signing secrets server-only, vazio por padrão; contrato e
	resolução com valores sintéticos passaram, mantendo portas/gate/volumes.
	CI remoto da candidata exata permanece gate de publicação, não de promoção.
	Nenhum deploy produtivo está implícito nesses PRs.

## Resultado

**Base isolada revisada, corrigida, mesclada e observada na instância. Integração ampla ainda não liberada.** O fluxo de conteúdo original passou via MCP até revisão nativa e publicação canônica em curso privado. A aquisição automática de dois vídeos YouTube na instância falhou com `YOUTUBE_IP_BLOCKED`; portanto, o E2E real de aquisição YouTube está **BLOQUEADO**, sem substituição por transcrição manual.

O pipeline e seu cron estão desativados após o teste. Permissões temporárias foram removidas e os consumidores legados conservam seu processamento. A próxima fase integra esses consumidores e simplifica Learning/AI, depois de resolver os bloqueadores e provar paridade.

## Revisões e merges

| Componente | Evidência |
| --- | --- |
| API revisada | [PR #16](https://github.com/marcelo-m7/facodi-api/pull/16), source `3f2683bf0dff7c7975e0037db776f4227dede796` |
| Merge API em main | `4f9051ff78469fb8acab6891b3eff5ad21b71a05` |
| Deploy revisado | [PR #261](https://github.com/marcelo-m7/facodi-deploy/pull/261), source `5685788e8a49d9870becac0172cd82462accddc8` |
| Merge deploy em main | `2dc03d9da929d573388365366d15f6230976c626` |
| Gitlink da API no deploy | `addons/facodi-api` → `3f2683bf0dff7c7975e0037db776f4227dede796`; commit alcançável em main da API |
| Odoo base produção/dev/teste | `odoo:19.0@sha256:dd9013e669caaa23d26765dc55814655eaeecca7cfc2c265dbabae913bce22fd` |
| Addon observado via MCP | `facodi_api`, instalado, `19.0.2.0.0` |

Os PRs antigos #15/API e #260/deploy foram reconhecidos pelo GitHub como ancestrais mesclados; seu diff antigo não foi aplicado separadamente nem usado como rollback. O PR documental #259/deploy foi fechado como substituído pelo prompt e pelas evidências atuais, preservando sua branch e o backlog.

Commits posteriores que apenas atualizem estas evidências não alteram o gitlink revisado. A versão instalada e o comportamento comprovam upgrade/execução da API, mas não identificam sozinhos o SHA da imagem em execução. Não houve acesso à identidade da imagem ou ao painel Coolify nesta revisão.

## Correções efetivamente incorporadas

- Autorização ORM de create/write/execução/publicação: proprietário, empresa e website são gerados e revalidados; estados, entrada aceita, resultados e receipts não podem ser forjados por RPC ou `default_*`.
- Intake HTTP usa a interface suportada do Odoo 19, com limite de rota antes do parsing de parâmetros. Limite de 262144 bytes mais sentinela, incluindo requests chunked/keep-alive. Bearer explícito impede fallback de sessão.
- Idempotência por proprietário/empresa, hash de payload e locks; worker usa row lock e cron exige administração antes de consultar a fila. Autorização inválida no primeiro item não impede a fila de avançar.
- Upgrade real de 19.0.1 preserva payload, metadados, artefatos, relações e estado anterior; coloca histórico não verificável em quarentena, retira ACLs amplas e fecha gate/cron.
- YouTube executa em processo filho sem Odoo/DB: prazo total de 45 segundos, timeouts de conexão/leitura, orçamento de corpo/segmentos/texto e rejeição antecipada de redirects. Erros têm códigos seguros. Transcript manual é identificado explicitamente.
- Publicação cria draft, exige evidência editorial explícita, chama a revisão nativa de Learning e publica com seu guard, dentro de savepoint. Replay revalida o conteúdo/review atuais.
- Vídeo externo permanece `slide.slide` de categoria video, com URL canônica e resumo em description; HTML e URL não são preenchidos simultaneamente. Artigos usam HTML escapado.
- Criação v2 suprime somente seu export legado Supabase por contexto interno. O teste composto confirma que hooks comuns continuam funcionando. Essa contenção ainda precisa evoluir para origem/provider persistidos, inclusive em edições posteriores.
- Imagem instala dependências no interpretador real do Odoo, executa import smoke/`pip check`, inclui API no migrate e usa storage persistente no volume existente `odoo-data`. A identidade de recursos/volumes de produção foi preservada.
- Harness descobre novamente a porta aleatória de loopback após restart e sinaliza mudanças do registry após fixtures, evitando falsos negativos.

## CI e testes reais

| Execução | Resultado / alcance |
| --- | --- |
| [API 37609607055](https://github.com/marcelo-m7/facodi-api/actions/runs/37609607055) | SUCCESS; 57 testes puros, 1 skip apenas da suíte que exige Odoo nativo |
| [Runtime final do PR 37610480117](https://github.com/marcelo-m7/facodi-deploy/actions/runs/37610480117) | SUCCESS; Odoo 19 real, 9 testes ORM, instalação limpa, upgrade legado e repetido, HTTP, scheduler, publicação e restart |
| [Plataforma final do PR 37610480249](https://github.com/marcelo-m7/facodi-deploy/actions/runs/37610480249) | SUCCESS; imagem canônica, contratos, Website/backend/browser/Portal, governança nativa e restore descartável |
| [Runtime de main 37611311972](https://github.com/marcelo-m7/facodi-deploy/actions/runs/37611311972) | SUCCESS após merge |
| [Plataforma de main 37611312267](https://github.com/marcelo-m7/facodi-deploy/actions/runs/37611312267) | SUCCESS após merge |

O CI dedicado usa PostgreSQL/Odoo, banco, volumes, rede e portas próprios. Verifica gate/cron desligados, bearer, 202 sem processamento síncrono, limites, 409, submissões simultâneas, isolamento, dois cursores, scheduler real, publicação/autorização e persistência após restart.

O CI composto instala API+Learning e usa o review nativo; verifica evidência ausente sem publicação, defaults hostis ignorados, review aprovado único, vídeo standard e replay. Apenas o transporte externo legado Supabase é controlado nesse cenário, com assert por registro; engine, ORM, review e publicação são reais. A fixture de vídeo com transcript explícito prova o handoff, **não aquisição externa ou licença real**.

## Continuação da integração API → Learning

Os PRs [API #17](https://github.com/marcelo-m7/facodi-api/pull/17), [Learning #197](https://github.com/marcelo-m7/facodi-learning/pull/197) e [Deploy #262](https://github.com/marcelo-m7/facodi-deploy/pull/262) implementam a continuação auditada em ordem dependente. A API estabiliza comandos versionados, wizard backend não forjável, snapshot ACL-visível, retry/replay e submissão concorrente. Learning adiciona o consumidor opt-in `odoo_python`, cancel versionado, reconciliação editorial atómica, exclusão mútua dos schedulers e a origem persistida que impede reenvio Supabase apenas para conteúdo da API. Deploy preserva a seleção administrativa em migrações repetidas, exige a API instalada e executa o teste nativo do adapter antes de iniciar Odoo.

Na validação pré-merge, a API passou 101 testes puros (1 skip) e 23 testes nativos isolados, incluindo instalação limpa, dois upgrades, HTTP, concorrência, publicação e restart. Learning passou a matriz Odoo 19 com 225 testes (263 estatísticas de métodos), seguida de dois upgrades, incluindo regressões legacy Supabase e `facodi_api_consumers`. Estes resultados são evidência descartável de código; não provam promoção, canary, identidade da imagem ou recuperação produtiva.

A promoção continua deliberadamente desligada: `facodi_api.pipeline_enabled=false`, provider produtivo `local_metadata` e processing plane produtivo `supabase` na última leitura autorizada. Não houve escrita produtiva nesta continuação. O canary YouTube continua bloqueado por `YOUTUBE_IP_BLOCKED`; benchmark, provider externo, backup/restauro produtivo emparelhado e cutover amplo permanecem critérios abertos.

Website/browser e restauração emparelhada de PostgreSQL+`odoo-data` passaram em ambiente descartável, preservando elementos Website, progresso, currículo/reviews e attachment/filestore. Isso não comprova backup/restauração dos volumes produtivos. Benchmark p95 e recovery completo de crash/retry/cancel ainda não foram aceitos.

## Teste controlado na instância via Odoo MCP

Conexão escolhida explicitamente: `https://facodi.com`, database `facodi`, connection `4557`. Inventário precedeu as escritas. Não foram usados outros alvos da conta, cron global ou consumidores reais como fixtures.

Curso de teste **43**, website **1**, empresa **1**, visibility **members**, matrícula **invite**, `website_published=false`. Projetos técnicos **3, 4, 5** são followers-private; cada run criou uma tarefa principal e três subtarefas.

| Cenário | Resultado observado |
| --- | --- |
| Intake com gate desligado | Recusado; não criou run com a chave de teste |
| YouTube inglês: `4GVbqYFmGBw`, run **4**, tarefa **7** | Received → failed / `YOUTUBE_IP_BLOCKED`; 0 chunks/conceitos, sem slide; `is_manual_transcript=false` |
| YouTube português: `9-WOBr534pQ`, run **5**, tarefa **11** | Received → failed / `YOUTUBE_IP_BLOCKED`; 0 chunks/conceitos, sem slide; `is_manual_transcript=false` |
| Texto original de aceite, run **6**, tarefa **15** | Received → waiting_review; 1 chunk / 12 conceitos; nenhum slide antes da aprovação |
| Aprovação do run 6 | Published; slide canônico **1062**, article, curso **43**; review nativo **553**, approved, hash registrado, reviewer **2** |
| Repetição de aprovação | Mesmo slide **1062**, apenas um review; sem duplicação |
| Leitura em chamada posterior | Slide persistente após restauração das permissões/gate |
| Limite desta prova | Publicação/persistência observadas pelo ORM/MCP; rota Website HTTP nativa foi testada no CI, não por sessão browser produtiva nesta revisão |

O conteúdo manual é texto original gerado exclusivamente para o teste autorizado, com autoria/uso/purpose explicitamente registrados. Não é legenda dos vídeos, nem evidência de aquisição YouTube ou enriquecimento LLM.

### Configuração final confirmada

- `facodi_api.pipeline_enabled=false` (parâmetro 80).
- Cron 26 permanece `active=false`; não foi habilitado no teste.
- Usuário 2 voltou aos grupos diretos originais `[32,27,22,18,28,4]`; papel temporário de reviewer foi removido.
- `facodi_publication_review_enabled` permanece habilitado no website 1.
- Curso 43 continua privado e não publicado; registros de teste ficam como evidência controlada.
- Runs históricos 1/2/3 estão cancelled/quarantined, com legacy_status preservado; não foram reprocessados ou publicados.

## Bloqueadores e próximos passos

1. **P0 — aquisição YouTube real bloqueada por IP** ([API #6](https://github.com/marcelo-m7/facodi-api/issues/6)). Resolver transporte suportado/configuração server-side ou alternativa autorizada, com orçamento, redaction e teste externo positivo. Fonte não pode fornecer proxy/credencial arbitrários. Não confundir correção de timeout com correção do bloqueio de rede.
2. Retry/cancel/waiting_input, comandos versionados e replay imutável foram implementados na integração #17; ainda falta promover e provar recovery/canary produtivo sem editar a entrada aceita.
3. Provider de enriquecimento independente: baseline atual não comprova LLM. Completar capabilities/OpenAPI, documentos por attachments autorizados e snapshot curricular real.
4. O consumidor opt-in de Learning foi implementado em #197 com provider/ator/origem congelados, um run por job e exclusão mútua dos schedulers; ainda falta a revisão final, merge ordenado e canary privado antes de qualquer cutover.
5. Simplificar Learning e retirar chamadas AI apenas após paridade, preservando modelos/histórico e funções AI fora desse domínio.
6. Antes de cutover amplo, confirmar backup produtivo emparelhado e identidade da imagem instalada, executar benchmark e canary. Não alegar essas provas a partir deste CI.

Issues API #1–13 e deploy #255–258 permanecem abertas pelos critérios ainda pendentes. Este aceite é da base isolada; não fecha a arquitetura completa nem libera todos os consumidores.

## Entrega ao agente local

Use o [prompt integral da próxima fase](prompt-platform-integration.md). Ele exige isolamento, implementação completa, testes nativos, preservação dos dados, revisão editorial, rollback e atualização de evidências. O novo agente deve começar pelo bloqueio YouTube e completar a integração antes de ampliar o cutover.

## Seguimento local: composição candidata de integração

Esta seção registra uma validação local posterior, não uma nova promoção ou
inspeção da instância. Os gitlinks da release acima permanecem inalterados.

O inventário encontrou a API local em
`798c8930fb7b1f9b5092545575f73a007eaa34a0`, dez commits atrás de seu
`origin/main`, enquanto Learning já tinha o adapter ativo. Os contratos ausentes
nesse checkout (`submit`, retry/cancel, revisão e tentativas) existem na API
posterior. A validação usou um worktree limpo, sem substituir esse checkout ou
recriar o adapter existente.

| Fonte efetivamente testada | SHA completo |
| --- | --- |
| API, após PRs #17/#18 | `6481a80b7cec311b978fe4625bd839633a8184f7` |
| Learning | `61680b23817207d8d70970fa1600d0829a1ba45f` |
| Deploy de partida, com alterações locais no harness | `4f22c3d75ccd85a0199f1bba84a267765964d097` |

| Verificação local | Resultado |
| --- | --- |
| API: `python -m pytest -q` no worktree | PASS: 103 passed, 1 skipped (suíte Odoo nativa) |
| Odoo API descartável | PASS: 26 testes, zero falhas/erros no resumo nativo |
| Learning descartável: `facodi_api_consumers` | PASS: 13 testes, zero falhas/erros no resumo nativo |
| HTTP, instalação, upgrades, scheduler e restart | PASS na composição candidata |
| Guardas de fonte e resultado nativo | PASS: 8 testes de regressão |
| Compose produtivo: `config --quiet` | PASS; nenhum serviço produtivo iniciado |
| Contratos deploy/migração | FAIL: checkout da API diverge do gitlink da release; demais testes passaram |
| Identidade/backup produtivos, MCP descartável, YouTube/LLM externos e benchmark | NOT_EXECUTED nesta rodada |

O handoff nativo comprova um run por job, exclusão do scheduler legado,
resultado/tentativa únicos, aprovação com reutilização do slide canônico,
provider/origem congelados, invalidação de entrada alterada, rollback da projeção
editorial e cancelamento sem tentativa fictícia. Isso não comprova crash recovery
completo, aquisição YouTube externa ou LLM real.

O harness agora aceita fontes Git limpas rastreadas, registra seus SHAs e exige
um resumo Odoo sem falhas e com testes efetivamente executados. CI usa o checkout
do submodule diretamente, evitando uma cópia cuja referência `.git` poderia
apontar para outro diretório. Learning executa em uma segunda base descartável;
uma release sem dependência da API é marcada `NOT_EXECUTED` nesse cenário.

Os logs Odoo incluem mensagens `cursor already closed` durante o encerramento de
threads de assets, posteriores aos resumos nativos verdes. Elas não foram
confundidas com falhas dos testes nem corrigidas nos mirrors vendor.

Para reproduzir, seguir [a seção de aceite local](../development.md#isolated-api-and-learning-acceptance)
com os SHAs acima. Antes de promoção, reconciliar os gitlinks de todos os addons,
validar a composição exata final com o gate Coolify/browser/restore, confirmar
imagem e backup produtivos e obter autorização operacional. Default, gate e cron
produtivos não foram alterados por esta validação.

## Gate local seguinte: pins e imagem completa

Os gitlinks candidatos foram agora preparados no index, sem commit, push,
deploy ou alteração operacional. A API passou para o SHA testado em um checkout
detached; Learning e theme conservaram as revisões preexistentes. O contrato
compara o checkout com o gitlink staged, permitindo validar a candidata antes
do commit. Mantém igualdade exata de SHA, modo `160000`, stage `0` e caminho,
com regressões que recusam drift e entradas unmerged.

| Fonte | Gitlink candidato |
| --- | --- |
| API 19.0.3.0.0 | `6481a80b7cec311b978fe4625bd839633a8184f7` |
| Learning 19.0.2.0.0 | `61680b23817207d8d70970fa1600d0829a1ba45f` |
| Theme 19.0.10.89.0 | `2cc983d6f5f99601983d57cc19ef7923aa60c7dc` |
| AI, preservado | `c9cf01739180b12a758b3f61082a38179e1e475b` |
| Monodoo, preservado | `2f9fb6bdad212442a3e16f5c3740ae11a7fb0923` |
| MuK, preservado | `b8d5a31039d8a23aa7383c4f9f069dc5f9af7727` |

Comandos executados na raiz do deploy:

```bash
bash scripts/validate-repository.sh
docker compose --env-file .env.ci -f deploy/coolify/docker-compose.yml config --quiet
FACODI_REQUIRE_EMPTY_DATABASE=1 bash tests/test_coolify_runtime.sh
FACODI_REQUIRE_EMPTY_DATABASE=1 FACODI_BROWSER_ACCEPTANCE=1 \
	FACODI_BROWSER_CHROME_BIN=<Chromium local> \
	FACODI_BROWSER_SCREENSHOT_DIR=<diretorio temporario D1> \
	FACODI_D2_BROWSER_SCREENSHOT_DIR=<diretorio temporario D2> \
	bash tests/test_coolify_runtime.sh
```

Ambos os gates completos saíram com código `0`. O primeiro validou HTTP/ORM e
restore, mas não habilitou Chromium. O segundo habilitou explicitamente os
browsers: catálogo em 1440, 390 e 320 px; Roadmaps, UCs, Explore e detalhes;
vídeo nativo fullscreen; intake contextual; Portal e backend Monodoo/MuK;
páginas D2 About, contribuição, blog, contato e política. As asserções verificam
hooks, interações e ausência de overflow, além das capturas de tela.

A instalação começou sem base `facodi`, inicializou os módulos e repetiu a
migração. O restore quiesceu Odoo, capturou PostgreSQL e filestore juntos,
alterou ambos, restaurou o par e confirmou Website, curso, progresso,
histórico curricular e attachment/filestore. Toda essa evidência é descartável.

Identidade local da segunda execução, arquitetura `arm64`:

- Imagem Odoo: `sha256:b5fcf3a36629fabfb43a1923a24fbfeb5a58ea70debd66277425b9045b0d45e4`.
- Imagem migrate: `sha256:56126a4f429617e90eaa8252160c93bca17f7ebec3f789d50a3fe7c686112bfa`.
- Base Odoo continua no digest documentado no aceite inicial. Os IDs acima
	identificam imagens locais, não digests publicados em registry ou produção.
- Playwright `1.55.0`, Chromium `140.0.7339.16`, instalados temporariamente.

Logs completos e screenshots ficaram em diretórios temporários locais; nenhuma
credencial produtiva foi usada. Os containers/volumes de CI foram removidos pelo
harness. Permanecem pendentes o commit/CI dessa candidata, identidade e backup
produtivos, autorização de promoção, MCP descartável, benchmark e provas
externas YouTube/LLM. Este gate não ativa processamento como default.

## Publicação consolidada e correções de revisão

A composição anterior foi consolidada com o trabalho preservado do PR deploy
#262, incluindo a migração que conserva a escolha explícita `odoo_python`
sem ativar o gate. O commit local `f8fc321dd29d185f4904d1df50609e5eb16ebd16`
foi preservado por merge, não descartado. Seus cinco testes de comportamento
agora fazem parte obrigatória de `scripts/validate-repository.sh`.

Revisões finais consumidas:

- API `c6da48b8eeb62ff0f83a084bec4a6928de31cc0e`, addon `19.0.3.1.0`,
	[PR #19 mesclado](https://github.com/marcelo-m7/facodi-api/pull/19).
- Learning `2c066b3ae4b9e865d22d8af7747687729598e0da`,
	[PR #198 mesclado](https://github.com/marcelo-m7/facodi-learning/pull/198).
- Theme permanece `2cc983d6f5f99601983d57cc19ef7923aa60c7dc`;
	AI/Monodoo/MuK permanecem nos pins anteriores.

A primeira execução nativa da correção API recusou a fixture de replay porque
ela tinha Officer, não Reviewer/Manager. O teste foi corrigido concedendo o
papel requerido; a autorização de publicação não foi relaxada. O harness
detectou a falha e bloqueou a entrega antes do merge.

| Gate repetido nos SHAs finais | Resultado |
| --- | --- |
| API pura | 104 passed, 1 skipped (Odoo nativo) |
| Contratos deploy/migração/provider | 66 testes, sem falhas |
| API nativa | 27 testes, sem falhas/erros |
| Learning: consumidores nativos | 18 testes, sem falhas/erros |
| Instalação/upgrades/HTTP/scheduler/replay/restart | PASS, saída 0 |
| Imagem canônica/Chromium D1+D2/restore emparelhado | PASS, saída 0 |

A recuperação de receipts Learning foi revalidada: projeção terminal repetida
não duplica resultado/tentativa, actor/configuração congelados persistem e
falhas de projeção não permitem publicação incompleta. A API congela nome e
digest de attachment, recusa replay de conteúdo alterado e classifica falhas
de transporte com códigos seguros.

Logs locais completos: `/tmp/facodi-publish-native-final-20261007.log` e
`/tmp/facodi-publish-full-browser-20261007.log`. Capturas D1/D2 permanecem
temporárias, sem dados produtivos. CI e merge do deploy são acompanhados no
[PR #262](https://github.com/marcelo-m7/facodi-deploy/pull/262); resultados de
commits antigos não substituem os checks do head final desse PR.

Os merges/pushes de fonte não comprovam identidade ou backup produtivos nem
autorizam ligar default/gate/cron. YouTube/LLM externos, MCP descartável,
benchmark, recuperação completa e canary continuam explicitamente pendentes.
Issues somente podem ser fechadas quando todos os seus critérios específicos
tiverem evidência; este avanço não fecha automaticamente o epic.

</details>
