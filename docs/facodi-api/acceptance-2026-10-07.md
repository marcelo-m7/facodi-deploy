# Aceite e próximos passos — FACODI API, 2026-10-07

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
2. Implementar retry/cancel/waiting_input/lease/recovery e nova evidência de transcript manual sem editar a entrada aceita.
3. Provider de enriquecimento independente: baseline atual não comprova LLM. Completar capabilities/OpenAPI, documentos por attachments autorizados e snapshot curricular real.
4. Integrar consumidores de Learning por provider congelado por job/run; um scheduler por trabalho; provar ausência de chamadas/loops AI/Supabase no novo fluxo.
5. Simplificar Learning e retirar chamadas AI apenas após paridade, preservando modelos/histórico e funções AI fora desse domínio.
6. Antes de cutover amplo, confirmar backup produtivo emparelhado e identidade da imagem instalada, executar benchmark e canary. Não alegar essas provas a partir deste CI.

Issues API #1–13 e deploy #255–258 permanecem abertas pelos critérios ainda pendentes. Este aceite é da base isolada; não fecha a arquitetura completa nem libera todos os consumidores.

## Entrega ao agente local

Use o [prompt integral da próxima fase](prompt-platform-integration.md). Ele exige isolamento, implementação completa, testes nativos, preservação dos dados, revisão editorial, rollback e atualização de evidências. O novo agente deve começar pelo bloqueio YouTube e completar a integração antes de ampliar o cutover.
