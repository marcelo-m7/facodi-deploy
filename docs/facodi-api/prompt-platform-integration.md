# Prompt para o agente local — integração e simplificação FACODI

Você assume a próxima fase de implementação da plataforma FACODI. Trabalhe autonomamente até entregar a integração completa, validada ponta a ponta, com documentação e PRs revisáveis. Não pare em planejamento, scaffolding, testes unitários, relatório de intenção ou indicação de que alguém deve concluir o código. Corrija falhas encontradas, execute os testes reais e acompanhe os builds. Se existir um bloqueio externo incontornável, conclua todo o trabalho independente e informe o bloqueio concreto, a evidência e a intervenção mínima necessária; não invente um sucesso nem permaneça repetindo uma operação sem resultado.

## Baseline verificada e prioridade imediata — 2026-10-07

API PR #16 e deploy PR #261 estão mesclados. Merges de código: API `4f9051ff78469fb8acab6891b3eff5ad21b71a05`; deploy `2dc03d9da929d573388365366d15f6230976c626`. Gitlink API do deploy: `3f2683bf0dff7c7975e0037db776f4227dede796`. Documentação posterior pode avançar main sem mudar esse pin; sempre refaça o inventário dos heads reais.

CI final dos PRs [runtime 37610480117](https://github.com/marcelo-m7/facodi-deploy/actions/runs/37610480117) e [plataforma 37610480249](https://github.com/marcelo-m7/facodi-deploy/actions/runs/37610480249) passou. Após merge, [runtime 37611311972](https://github.com/marcelo-m7/facodi-deploy/actions/runs/37611311972) e [plataforma 37611312267](https://github.com/marcelo-m7/facodi-deploy/actions/runs/37611312267) também passaram. Leia [aceite completo](acceptance-2026-10-07.md) e não repita o relato antigo do agente como prova.

MCP confirmou `facodi_api 19.0.2.0.0` e a quarentena do histórico. Os vídeos YouTube `4GVbqYFmGBw` e `9-WOBr534pQ` foram submetidos sem texto manual, runs 4/5: ambos falharam `YOUTUBE_IP_BLOCKED`, sem chunks nem publicação. **Comece resolvendo a aquisição externa real.** Transporte alternativo/proxy exige configuração suportada server-side e credenciais autorizadas, jamais URLs/segredos escolhidos pela fonte. A falta de acesso externo é um bloqueio verificável, não autorização para falsificar legendas ou relaxar segurança. Implemente e valide o restante independente enquanto esse bloqueio é tratado.

Controle positivo separado: run 6 com texto original → waiting_review → revisão nativa 553 approved → slide article 1062, curso privado 43; replay sem duplicação. Isso comprova handoff de conteúdo original, não YouTube adquirido ou LLM. Ao final: gate false, cron 26 inactive, permissões temporárias removidas, curso 43 members/invite/unpublished. Não reprocessar runs históricos 1/2/3 ou fixtures 4/5/6 para simular nova evidência. Use novos registros de teste e preserve o histórico.

Backup emparelhado foi testado apenas no runtime descartável. O SHA da imagem produtiva e backup produtivo precisam de confirmação operacional antes do cutover amplo.

## 1. Estado inicial e leitura obrigatória

Repositórios: `marcelo-m7/facodi-api`, `marcelo-m7/facodi-learning`, `marcelo-m7/facodi-ai` e `marcelo-m7/facodi-deploy`. `facodi-theme` só participa quando apresentação/traduções exigirem uma alteração específica. Identifique o owner de cada arquivo antes de editar. O deploy consome commits exatos por gitlink; não copie código de addons para o superprojeto.

Leia os AGENTS.md aplicáveis, os manifests, `docs/facodi-api/review-integration-2026-10-07.md` na API, o relatório operacional correspondente no deploy e as issues API #1–13/deploy #255–258. Leia a implementação e os resultados reais dos PRs API #16 e deploy #261. Atualizações mais recentes e instruções deste prompt superam as antigas proibições genéricas de cutover, mas os testes e a preservação dos dados continuam obrigatórios.

A API v2 já possui intake bearer assíncrono, idempotência por proprietário/empresa, Project privado, cron, revisão e publicação canônica. A revisão adicionou guards ORM contra writes e default_* do contexto, escopo empresa/website, locks, falhas sanitizadas e aquisição YouTube em processo filho com prazo máximo. A versão 19.0.2.0.0 coloca registros antigos em quarentena, preservando legacy_status e evidência. Não remova esses guards nem reative histórico sem identificar sua origem. O enriquecedor padrão é baseline determinístico, não um LLM comprovado.

Antes de implementar, confirme o estado efetivo de main, pins, CI, implantação e resultados YouTube no relatório de aceite. Não deduza deploy de um check verde. Se houver um bloqueador pendente, resolva-o primeiro; não amplie o cutover sobre uma aquisição ou migração que ainda não passou.

## 2. Isolamento e autonomia

Crie worktrees/branches próprios para esta fase, a partir das revisões reais de main. Preserve o workspace de Marcelo e alterações preexistentes. Use banco, volumes, rede, portas, credenciais e storage próprios nos testes. Não reutilize facodi/produção ou a instância de outro projeto para experimentos. Nunca use down -v nos volumes produtivos, renomeie o recurso Coolify ou contorne migrate.

Faça as decisões rotineiras e correções necessárias sem pedir confirmação a cada etapa. Mantenha um plano, checkpoints e commits focados. Investigue falhas antes de alterar código. Faça revisão do diff e corrija os problemas antes da entrega. Testes obrigatórios não podem ficar SKIPPED, xfail, 501 ou substituídos por assertions de texto-fonte.

## 3. Resultado esperado e arquitetura

Torne facodi_api o mecanismo único de ingestão, normalização, enriquecimento, ranking e orquestração para os novos trabalhos elegíveis. facodi_learning permanece owner dos conceitos educacionais, submissões, proveniência editorial, currículo, cobertura revisada e projeções públicas; passa a consumir contratos estáveis da API, sem manter uma segunda engine. facodi_ai mantém suas funções ainda usadas fora desse fluxo, mas deixa de ser dependência ou executor da nova análise de conteúdo.

Use `slide.channel` como curso e `slide.slide` como conteúdo, preservando matrícula/progresso e anexos nativos. Use Project/tarefas/atividades standard. Não crie cursos, progresso, submissões ou árvores curriculares paralelos. Não trate cobertura como equivalência acadêmica ou concessão de créditos.

Mapeie o call graph atual antes de mudar: submissão contextual, fila Explore/YouTube, descoberta de candidatos/cursos, analysis.job/result/attempt, revisão de conteúdo, mappings de conteúdo/cursos, curriculum coverage/module items, comandos backend e Portal. Inspecione o módulo opcional facodi_ai_learning e seus crons. Entregue uma matriz consumidor → contrato da API → persistência editorial → scheduler → rollback; cada consumidor real deve ter um teste correspondente.

A dependência deve ser acíclica. A engine pura de facodi_api não importa Odoo nem facodi_ai/facodi_learning. A camada Odoo da API não precisa depender de learning para processar DTOs autorizados. Se learning passar a depender de facodi_api, seus adapters fazem o handoff editorial. Evite HTTP da instância para ela mesma ou tokens entre modelos: chamadas internas usam uma fachada de serviço comum com as mesmas regras que o adapter HTTP. Não use create/write bruto para simular um comando idempotente.

## 4. Complete os contratos e a recuperação antes do cutover

1. Exponha uma fachada versionada para ingest/enrich/map/pipeline, capabilities e status, com schemas/erros claros e testes HTTP reais. Mantenha compatibilidade dos endpoints já entregues. Não crie generic dispatch de modelos nem sudo aberto.
2. Implemente retry/cancel/waiting_input com transições validadas sob lock e versão esperada. Uma transcrição manual é evidência explícita de uma revisão nova; nunca substitui silenciosamente a entrada aceita nem prova legenda adquirida. Capture motivos distintos: sem legenda, idioma, indisponibilidade, IP bloqueado, timeout e input inválido.
3. Faça recovery de crash/restart, leases/prazos e retomada por etapas/receipts sem duplicar rede, resultados, tarefas ou publicações. Uma falha na autorização do run mais antigo não pode travar a fila inteira. Um único scheduler deve ser responsável por cada trabalho.
4. Termine a ingestão documental por ir.attachment autorizado, com formatos/tamanho/tempo/memória limitados e parsing em fronteira isolada quando necessário. PDF/DOCX reais devem passar. Não aceite URL arbitrária para fetch; aplique whitelist, redirects, DNS/IP e SSRF conforme o transporte suportado.
5. Configure provider de enriquecimento independente de facodi_ai. Segredos são configuração server-side write-only; source/context não escolhe credenciais, prompt ou tool. Saída tem schema, evidência por chunk, limites de tokens/custo/tempo e versões para cache. Sem provider, retorne modo baseline claramente identificado; não marque isso como IA.
6. Faça snapshot autorizado dos cursos/conteúdos/unidades curriculares reais pelo adapter de learning. Ranking e cobertura proposta devem apontar para IDs/evidência existentes e conservar website/empresa/visibilidade. Ranking lexical contra até 50 cursos não satisfaz sozinho integração curricular completa.
7. Atualize etapas e resultados das tarefas standard conforme o processamento real. Preserve privacidade e deduplicação, inclusive logs/artefatos. Não dê acesso a tarefas técnicas para usuários Portal ou followers públicos.

## 5. Integre os consumidores sem executar duas engines

Adicione seleção explícita legacy/odoo_python, inicialmente opt-in, persistida por job/run. Jobs já existentes conservam provider, correlação, tentativas e histórico. Novas submissões elegíveis criam ou reutilizam um único run; seu job editorial recebe somente output completo/schema-validado. pending/queued não são resultados de análise.

O cron legado deve excluir trabalhos delegados à API e o cron da API não deve reenfileirar a mesma análise em learning/AI. Prove a corrida entre ambos. Um flag alterado depois da submissão não pode trocar o provider de um run em andamento. O migrate não deve sobrescrever a seleção local pela presença/ausência de secrets Supabase.

Inspecione os hooks de slide.slide que sincronizam vídeos com Supabase: a publicação/replay v2 não pode disparar uma segunda análise, loop de sincronização ou chamadas duplicadas. Trate a origem/provider persistidos e os receipts como autoridade. Contexto fornecido pelo cliente jamais autoriza estado, revisão, publicação, ownership ou segredo. Um guard de recursão não substitui idempotência nem autorização.

Preserve o handoff de revisão: executor propõe; um reviewer autorizado aprova pelos métodos de domínio existentes. Use versão esperada/snapshot para bloquear propostas obsoletas. Ao publicar ou reutilizar o receipt, revalide curso/website/empresa, visibilidade, conteúdo canônico e estado atual de publicação. Alteração manual posterior requer reconciliação explícita. Preserve vídeos como vídeos e documentos/anexos como seus tipos standard; não converta tudo em artigo de resumo.

Para submissões anônimas/Portal, o controller valida a submissão pública e delega uma solicitação mínima a um serviço autorizado. Não conceda grupo de operador técnico a todos os contribuidores, não exponha UUIDs técnicos/artefatos/task IDs/segredos no tracking público e não use sudo genérico sobre dados do catálogo. Reutilize o token de tracking e as páginas existentes com uma projeção segura.

### Contrato editorial já integrado: preserve e complete

A aprovação HTTP aceita {"publication_evidence":{"author":"...","rights_mode":"original|licensed|external","usage_basis":"...","purpose":"..."}}. Quando Learning está instalado, evidência explícita e eLearning Manager são obrigatórios. A API cria draft, usa facodi.learning.content.review.action_approve e só então publica pelo write guardado, sob savepoint. Não invente autoria/licença nem desligue facodi_publication_review_enabled. O contexto interno facodi_supabase_video_sync suprime o export legado somente nesta criação; a próxima fase deve substituir essa contenção por origem/provider persistidos e cobrir edições posteriores. O CI composto rastreia os registros que acionam o hook legado, preservando suas criações comuns.

A review nativa não substitui a proposta curricular versionada: faça o handoff pelos métodos de domínio e bloqueie revisões obsoletas. A API continua independente de Learning; o adapter de Learning pode depender da API sem criar ciclo. Atualize o critério histórico de dependência nas issues conforme essa direção.

## 6. Simplifique learning e retire chamadas de AI após comprovar paridade

Mantenha em learning apenas domínio, adapters, validação de contexto/entrada, revisão, currículo e projeção pública. Centralize processamento, provider, retries, cache e scheduling na API. Remova implementações duplicadas somente após migrar seus consumidores e demonstrar paridade nos testes.

Remova chamadas do novo fluxo a facodi_ai e a facodi_ai_learning. Inventarie outros usos antes de retirar dependências, crons ou módulos. Não desinstale um módulo que ainda detém modelos/dados históricos de auditoria sem uma migração explícita que preserve esses registros; quando necessário, mantenha uma camada histórica inativa/read-only. Stripe, Abacate, webhooks e AI fora da análise de learning não entram numa remoção indiscriminada.

Atualize manifests, imports, settings, views, traduções, crons, tests e pins para refletir a arquitetura final. Registre código eliminado e responsabilidades restantes. Prove instalação sem ciclo e upgrade repetido de uma base com jobs/pipeline runs/reviews/progresso/anexos pré-existentes.

## 7. UI e experiência

Reutilize a contribuição contextual, Explore, páginas de curso/slide, curriculum/módulos e `/my/home`. Não invente uma nova página para um fluxo que já existe. Preserve URLs, CTA/contexto e projeções públicas revisadas.

No backend, ofereça lista/formulário, filtros, ligação às tarefas e ações reais de retry/input/review/publicação. No tracking público, mostre estados compreensíveis e motivos seguros, sem detalhes de implementação. Inglês é source; traduções nativas pt_PT/es_ES/fr_FR. Use Website/QWeb/Portal standard e mantenha theme_facodi restrito à apresentação.

## 8. Gates obrigatórios de aceitação

Execute testes puros, contratos dos providers legados, ORM nativo e HTTP/worker reais em Odoo 19. O E2E determinístico pode controlar a fronteira externa do provedor, mas não mockar engine, ORM, fila, review, persistência ou publicação.

Prove, com comandos e evidência sanitizada:

- instalação limpa, upgrade da versão instalada, segundo upgrade, quarantine/histórico e restore DB+filestore;
- gate desligado conserva o legado e não cria efeitos v2; seleção local persiste durante migrate;
- bearer explícito mesmo com sessão, payload/types/limites, quotas, 202 sem processamento/rede síncrona, 409, replay e isolamento empresa/website/owner;
- create/write/RPC/default_* não forjam estado, autoria, review, receipt, snapshots ou artefatos;
- dois workers, dois crons, concorrência de intake/publicação, crash/restart e retry/cancel sem duplicação;
- YouTube com legenda adquirida, sem legenda, indisponível/IP bloqueado/timeout e input manual; timestamps só quando evidenciados;
- PDF/DOCX reais e anexos de outro usuário recusados; limites de recursos e SSRF/redirects;
- provider independente com saída válida/inválida, prompt injection tratada como dados, cache/custo/budget e nenhuma chamada a facodi_ai no novo fluxo;
- contribuição existente → uma análise/run → Project → proposta editorial → review → conteúdo standard → acesso Website/Portal;
- conteúdo continua privado antes de review; público só vê projeções aprovadas; matrícula/progresso/anexos sobrevivem;
- Website/backend e idiomas seguem funcionando, desktop/mobile sem overflow, URLs existentes preservadas;
- métricas/benchmarks medidos, sem prometer p95 ou aquisição externa a partir de mocks.

Mantenha o CI dedicado da API e o gate completo do deploy. Use os comandos documentados e a imagem/pins finais. Um skip apenas no ambiente sem Odoo é aceitável se a mesma suíte obrigatória passar no runtime real; nenhum cenário obrigatório pode desaparecer da aceitação final.

## 9. Promoção e teste na plataforma

Prepare e revise a implementação completa antes da promoção. Atualize gitlinks para os commits efetivamente revisados e faça os checks no head final. Faça merge dos PRs desta fase somente depois que todos os gates aplicáveis passarem; não misture PRs operacionais antigos sem revisar seu escopo.

Antes do rollout, confirme backup emparelhado de PostgreSQL e odoo-data e preserve o recurso/volumes Coolify. Acompanhe build, migrate bem-sucedido e saúde Odoo. Um CI verde prova a imagem descartável; prove a versão/código e o funcionamento que chegaram à instância. Faça canary opt-in para novas submissões, observe e só amplie depois do aceite; rollback de configuração pausa intake local preservando a evidência. Não restaure um gitlink velho como se isso desfizesse schema/dados.

No Odoo MCP, use conexão explicitamente guardada para `https://facodi.com`, database `facodi`; não confie no ponteiro ativo, pois existem várias instâncias na conta. Inventarie primeiro settings/cron/filas/cursos, registre IDs de teste e faça envios de vídeos reais já identificados no catálogo ou fornecidos por Marcelo. Confirme persistência, captura/artefatos, estado de review, handoff e conteúdo canônico em curso de teste privado. Restaure a configuração de teste ao terminar. Falha externa deve ser registrada como falha/espera, nunca disfarçada com transcript manual.

## 10. Entrega e condição de parada

Atualize README/arquitetura/contratos/OpenAPI/operations, runbooks de input/recovery/cutover/rollback e relatório de aceite. Atualize issues sem apagar critérios pendentes nem fechar uma epic apenas porque pytest passou. Relacione issues concluídas a evidência específica e deixe escopo restante explícito.

A entrega final contém: repos/branches/commits/PRs/pins, decisões e simplificações implementadas, matriz de consumidores atendidos, testes reais e links CI, estado da implantação, IDs/resultados MCP, resultados de aquisição externa, restauração das configurações e riscos/bloqueios remanescentes. Não entregue segredos, tokens, logs de corpos privados ou transcrições completas em comentários públicos.

Só termine quando a implementação desta fase estiver concluída, revisada e validada com todos os gates aplicáveis, documentação/issues atualizadas e funcionamento ponta a ponta comprovado. Se uma capacidade obrigatória estiver bloqueada por infraestrutura/credencial externa, o estado final deve dizer BLOQUEADO com evidência, o restante deve estar concluído e revisável, e o cutover afetado deve permanecer desligado.
