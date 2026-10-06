# FACODI API — plano de integração e rollout

Data 2026-10-06. Estado: proposta; documentação apenas. Nenhum pin, módulo ativo, segredo, Compose ou migração foi alterado por esta entrega.

Especificação de domínio: [facodi-api/docs/facodi-api](https://github.com/marcelo-m7/facodi-api/tree/docs/facodi-api-proposal-20261006/docs/facodi-api). Backlog: [issues e ordem de integração](backlog.md).

## Snapshot confirmado

`facodi-deploy/main` em `fe6a795d6eae077505c98a01ebfbb3d786b4fe74`. Gitlink API já existente `addons/facodi-api -> 05d6cb7fcc81e369646a6070e658a40b1d931c8b`. Odoo Community 19 + PostgreSQL 16. Compose ativo `deploy/coolify/docker-compose.yml` contém `build:` para migrate/odoo e não inclui explicitamente `facodi_api` em `FACODI_MODULES`. Não afirmar que o addon está instalado em produção a partir de presença do gitlink.

`docker/Dockerfile` instala requirements de `facodi-ai` e PyJWT em `/opt/facodi-venv`; a API precisará instalar o seu lock. `docker/migrate.py` escolhe `supabase_edge` com o par de credenciais Supabase. Esse comportamento deve ser adaptado antes de selecionar a pipeline local, conservando o default legado até cutover explícito.

## Ownership e dependências

O deploy integra fontes, imagem, migrações e prova de aceitação. Lógica fica em `facodi-api`; `facodi_learning` mantém domínio editorial e currículo; `facodi_ai` mantém chamadas IA e auditoria; theme não recebe consultas nem lógica. Não copiar addon para scripts de deploy, não criar novo LMS, não trocar gitlink por ficheiros soltos.

API passa a depender de `project`, `mail`, `website_slides`, `facodi_learning`, `facodi_ai`; addons existentes não passam a depender de API. `facodi_api` adiciona provider `odoo_python` e intercepta o scheduling local por herança de `action_process()`/cron, mantendo `_get_provider_registry()` compatível com outputs concluídos. A normalização existente espera saída síncrona: nunca receber um marcador de queued como resultado. O runner local é o único executor do job vinculado; providers legados continuam no scheduler atual. Também integra a criação de runs às submissões por herança, com feature flag desligada até ensaio.

## Configuração proposta

| Entrada | Semântica | Default de adoção |
| --- | --- | --- |
| `FACODI_PIPELINE_ENABLED` | aceita novas execuções localmente | `0` até staging aprovado |
| `FACODI_PIPELINE_PROVIDER` | `legacy` ou `odoo_python` | `legacy`; credenciais não escolhem engine novo |
| `facodi_api.pipeline_project_id` | Project técnico autorizado por company | XML ID bootstrap do addon |
| `facodi_api.pipeline_concurrency` | concorrência inicial | 1 |
| `facodi_api.pipeline_max_attempts` | tentativas totais | 3 |
| segredos IA existentes | resolução pelo facodi_ai | nunca no cliente/issue/log |
| par Supabase existente | compatibilidade do provider legado | conservar até drenagem comprovada |

`FACODI_PIPELINE_PROVIDER=legacy` preserva a política atual: ambos secrets Supabase selecionam supabase_edge; nenhum seleciona local_metadata; par parcial/malformado falha. `odoo_python` exige API instalada e dependências válidas; independentemente das credenciais antigas, seleciona explicitamente provider local. Ausência do par não pode sobrescrever esse provider no próximo migrate. Feature flag desligada não cancela runs existentes: impede novos e pausa execução automática por decisão operacional documentada.

Persistir provider/schema/pipeline version em cada run. Runs Supabase antigos continuam no provider original e conservam correlation IDs. Não converter histórico imutável para aparentar execução local. Não executar a mesma source simultaneamente em dois engines por efeito de migração. Não remover secrets Supabase enquanto callbacks pendentes existirem.

## Integração de fonte e imagem — D01

1. Consumir SHA revisto de API e, só se necessário, alteração do owner Learning/AI por gitlink separado; não apontar a branch mutável.
2. Adicionar API ao contrato de manifests/sources/tests e `FACODI_MODULES` nos ambientes CI/dev/runtime propostos.
3. Docker instalar requirements lock API com hashes no mesmo interpreter usado por Odoo; `pip check`, imports e ensaio de fixture. Atualizar `docker/Dockerfile.dev` conforme contrato dev existente.
4. Preservar volumes `postgres-data`, `odoo-data`, recurso Coolify e `db -> migrate -> odoo`; sem ports publicados/name override.
5. Registrar imagem, SHA de deploy, todos os pins e versões Python/libs no release manifest; CI deve conferir gitlinks exatos.

## Migração e cutover — D02

Instalação limpa cria Project/stages pelo addon sem demo data. Upgrade acrescenta schema/ACLs/dependências via API standard e preserva dados existentes. Segundo upgrade não duplica Project/tasks/stages. Não fazer chamadas a YouTube/LLM nem reanálise editorial no migrate.

1. Pausar intake/executor novo por flags, inventariar backlog legado em read-only e registar jobs pendentes.
2. Fazer backup emparelhado PostgreSQL + filestore; registar volumes/release conhecido.
3. Migrar em staging com provider `legacy`; comprovar website/eLearning/progress/reviews.
4. Ativar `odoo_python` em staging; criar submissão descartável, observar cron e tarefas; simular falha/retry/replay.
5. Drenar ou manter legado em percurso separado explícito; congelar provider nos runs novos.
6. Produção só após aceitação e release separado. Ativar flag e provider por decisão explícita; smoke em conteúdo controlado, sem publicar automaticamente.

Rollback de configuração desliga novos runs locais; histórico e artefactos ficam intactos. Se API/schema já foi instalado e for compatível, manter a versão instalada e regressar seleção a legacy. Não desinstalar Project/API para rollback de provider. Se rollback de imagem cruza migração incompatível, restaurar DB e filestore como par; imagem antiga sozinha não desfaz schema. Runs locais existentes não passam automaticamente a Supabase.

## Aceitação — D03

Executar checks existentes:

```bash
git submodule update --init --recursive
bash scripts/validate-repository.sh
docker compose --env-file .env.ci -f deploy/coolify/docker-compose.yml config --quiet
python3 -m unittest tests/test_repository_contract.py tests/test_migration_contract.py -v
bash tests/test_coolify_runtime.sh
```

Acrescentar em CI, no ambiente descartável: fresh + upgrade + segundo upgrade API/Project; pipeline com fixture; HTTP bearer/ACL; Project/subtarefas e status; mapping proposto/revisão Manager/publicação explícita; replay/restart; paired restore com artefactos; ausência de segredos em logs. Scripts futuros `tests/test_facodi_api_runtime.sh` e `tests/test_facodi_api_migration.py` têm de ser escritos na implementação, não existem por causa deste documento.

Medir p95 Website sob pipeline ativa e metas da especificação. Live transcript smoke separado opt-in; resultado registra disponibilidade/bloqueio, não torna falha externa uma aprovação inventada. `/web/login` saudável sozinho não é aceitação de pipeline.

## Build fora da janela de substituição

Reutilizar [issue #224](https://github.com/marcelo-m7/facodi-deploy/issues/224) e [PR draft #226](https://github.com/marcelo-m7/facodi-deploy/pull/226), sem duplicar esse desenvolvimento. #224 ainda exige evidência num Coolify não produtivo antes de trocar o Compose ativo por imagem prebuilt. Não depender da conclusão dessa iniciativa para escrever/testar o addon em staging; promoção de produção deve documentar a estratégia de build e a evidência aplicável.

Se a solução prebuilt for aprovada, `migrate` e `odoo` usam o mesmo digest imutável e o trigger só ocorre depois da publicação da imagem. Nunca alterar o Compose produtivo nesta entrega documental nem afirmar downtime zero.
