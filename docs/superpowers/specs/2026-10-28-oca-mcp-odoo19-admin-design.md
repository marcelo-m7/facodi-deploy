# FACODI MCP administrativo — port de OCA 16.0 para Odoo 19

**Estado:** proposta de arquitetura — aguarda aprovação de Marcelo antes de implementação.
**Data:** 2026-10-28
**Repositório integrador:** `marcelo-m7/facodi-deploy`
**Fonte:** [OCA/ai — ai_oca_mcp 16.0](https://github.com/OCA/ai/tree/16.0/ai_oca_mcp)

## 1. Intenção e âmbito

Permitir que clientes MCP externos consultem o Odoo e executem **operações administrativas explicitamente autorizadas** na instância FACODI Odoo 19 Community, com autenticação por cliente, identidade Odoo de execução, mínimo privilégio, auditoria sem segredos e aprovação humana de alterações críticas. O MCP é uma superfície de integração administrativa, não uma substituição das regras de domínio e revisão do FACODI.

Objetivos:
- Preservar os conceitos e a atribuição do módulo OCA (servidores, ferramentas `generic`, chaves por cliente, logs), adaptando-o ao Odoo 19.
- Manter FACODI Learning, Project, API e Theme responsáveis pelos próprios modelos e fluxos. Usar os métodos de negócio/revisão existentes; nunca escrever diretamente estados terminais protegidos.
- Permitir operações de leitura e escrita restritas e extensíveis, com segregação por cliente/identidade/servidor.
- Integrar instalação e atualizações ao gate de migração idempotente do Coolify, sem ativar acessos por omissão.

Não objetivos da primeira entrega:
- Expor arbitrariamente `env[model].search/create/write/unlink`, `sudo()`, SQL, shell, gestão de permissões, segredos, pagamentos ou exclusões ao agente.
- Implementar OAuth 2.0/Claude Desktop; a ligação inicial será MCP HTTP com Bearer Key e clientes compatíveis (p. ex., n8n), sujeita a teste de protocolo.
- Alterar automaticamente dados de produção, criar chaves, publicar ferramentas, aprovar conteúdos ou contornar revisões humanas.
- Introduzir um gateway/porta de rede pública separado ou alterar volumes persistentes.

## 2. Abordagens consideradas e decisão

1. **Selecionada: portar `ai_oca_mcp` para Odoo 19**, dependente de `ai_tool` 19.0 da OCA, com reforço de segurança e ferramentas FACODI por extensão. Reutiliza o ecossistema Odoo e um único processo HTTP; requer manutenção do port e respeito à licença AGPL-3.
2. **Alternativa rejeitada: gateway MCP externo** sobre APIs Odoo. Oferece isolamento de processo, mas duplica autorização/auditoria, adiciona serviço ao Coolify e exige mapear com cuidado cada permissão Odoo.

O `ai_oca_mcp` não está disponível na árvore pública 19.0 da OCA consultada em 2026-10-28; o `ai_tool` está. A base 16.0 contém comportamentos inadequados à segurança administrativa sem adaptação: log do payload e resultado completos, exceções internas repassadas ao cliente, e necessidade de validar a compatibilidade efetiva do transporte MCP com clientes atuais.

## 3. Arquitetura e ownership

- `addons/oca-ai`: novo **git submodule com commit fixo**, apontando para `OCA/ai` versão 19.0; consumir o addon `ai_tool` sem copiar ficheiros para o superprojeto.
- `marcelo-m7/facodi-ai` (git submodule atual): novo addon `ai_oca_mcp` (port da OCA 16.0 para 19.0, licença AGPL-3 e atribuições preservadas), mais extensão FACODI independente para ferramentas autorizadas, sem modificar a implementação de `facodi_ai` desnecessariamente. Manter a licença e ficheiros de origem identificáveis para facilitar upstream.
- `facodi-deploy`: atualizar gitlinks, `.gitmodules`, composição das fontes Docker, path do desenvolvimento, lista explícita `FACODI_MODULES`, gate de migração, testes de contrato, documentação de operação e rollback. Não acrescentar modelos de negócio diretamente ao deploy.
- `facodi_learning`/outros donos de domínio: se uma ferramenta exigir nova ação de negócio, implementar no addon proprietário e expor uma ponte estreita no MCP. Não duplicar regras editoriais.
- Preservar `db -> migrate -> odoo`, as volumes `postgres-data` e `odoo-data`, a ausência de host ports para DB/Odoo e o contrato de instalação atual.

Fluxo: cliente externo HTTPS -> rota MCP existente no Odoo -> autenticação Bearer -> resolução do servidor/chave/identidade -> ferramenta autorizada -> ORM/método de negócio **sem sudo** e sob ACL/regras de registo -> resposta mínima e auditoria sanitizada.

## 4. Segurança e autorização

### 4.1 Identidade e chaves
- Não criar servidor/chave/ferramentas no bootstrap ou na migração; configuração inicial fechada. Um administrador Odoo atribui ferramentas a um servidor e cria uma chave por cliente e por utilizador técnico interno.
- Chaves geradas por CSPRNG (mínimo 256 bits de entropia), mostradas **uma vez**, guardadas apenas sob hash, com expiração, revogação e rotação; nunca em URL, eventos, logs, erros ou banco em texto simples.
- O identificador público opaco da rota não é segredo substituto da chave; exigir sempre Bearer válido. Mensagens de falha de autenticação indistinguíveis (401), independentemente da existência do servidor ou da chave.
- Rejeitar utilizadores desativados ou externos (Portal/Public), servidores inativos e chaves revogadas/expiradas; invalidar a autenticação imediatamente após alterações, evitando cache persistente de validade.
- Apenas administradores autorizados podem criar servidores, associar ferramentas e emitir/revogar chaves. O utilizador técnico não recebe privilégios `base.group_system` por inerência do MCP.

### 4.2 Ferramentas e execução
- **Deny by default:** `tools/list` mostra apenas ferramentas explicitamente autorizadas para aquele servidor e identidade; nenhuma descoberta automática de todos os modelos/métodos.
- Suportar exclusivamente tools `generic` nesta fase; esquemas de entrada e saída são verificados, com limites de tamanho, paginação, campos e resultados. Nomes de ferramenta únicos; argumentos inesperados rejeitados.
- Os métodos executam no contexto do `res.users` da chave, usando ACL, record rules, empresas e websites nativos. `sudo()` permitido somente na busca estritamente interna de metadados/autenticação e na persistência auditada, nunca para operações de negócio.
- A ponte FACODI deve registar ferramentas granulares, não um `execute_model` genérico. Primeiro conjunto-alvo: pesquisa paginada de cursos `slide.channel` e aulas `slide.slide`; leitura administrativa de submissões com ACL; criação e edição de **rascunhos editoriais não publicados** por métodos controlados. As operações exatas e os campos são fechados e testados contra os modelos vigentes antes da entrega.
- Ações de publicação, aprovação de cobertura/revisão, gestão de utilizadores/permissões, alterações de configuração, exclusões e alterações em massa **não ficam disponíveis diretamente** na primeira ativação. A expansão futura exige ferramenta específica, gate humano no Odoo, identidade de aprovador separada quando aplicável, prazo curto, hash do comando aprovado e uso único.
- Para escritas autorizadas: idempotência por identificador de operação com resultados reconsultáveis, validação de propriedade/estado, transação atómica e teste de reenvio/concorrência. O MCP nunca permite que o cliente defina contexto privilegiado, `sudo`, estado final de revisão ou `website_published` arbitrário.

### 4.3 HTTP, erros e auditoria
- Rota HTTPS no domínio Odoo, somente POST, `Content-Type` JSON, limites de corpo e tempo, validação de JSON-RPC, método e tipos de argumentos; respostas de erro com código estável, sem stack trace, nomes de segredos ou exceções internas.
- Confirmar implementação de handshake/`initialize`, `notifications/initialized`, `ping`, `tools/list`, `tools/call` e negociação de versão/HTTP exigidos pelos clientes escolhidos. Não anunciar capacidades não suportadas.
- Aplicar limites por chave/cliente e evitar que falhas ou picos de MCP prejudiquem eLearning/Website; avaliar regras de reverse proxy e proteção por origem conforme o transporte especificado.
- Log imutável mínimo: timestamp, identificadores de servidor/chave/utilizador, nome da ferramenta, request/trace ID, resultado, duração e categoria de erro. **Não** guardar Bearer, payloads integrais, respostas, dados pessoais, credenciais ou exceções internas; retenção operacional proposta de 30 dias.
- Rejeitar requests inválidos antes da execução e garantir que erros não elevem permissões nem deixem escritas parciais; contar tentativas falhadas na proteção contra abuso sem revelar existência de credenciais.

## 5. Instalação, ativação e rollback

1. Desenvolver/validar o port e a ponte no repositório `facodi-ai`; fixar fontes OCA 19 e commit `facodi-ai` em `facodi-deploy`.
2. Incorporar ambos os addons na imagem pelo pipeline existente; ajustar Compose dev, teste de contratos e `FACODI_MODULES` do `migrate` e do `odoo`. Atualizar a lista de update de `docker/migrate.py` apenas conforme o gate necessário; instalação em BD existente via `FACODI_MODULES`, atualização via APIs normais.
3. O Coolify só publica a nova imagem após sucesso do gate. Módulo instalado continua **inativo externamente** até um administrador configurar servidor, ferramentas permitidas e chave.
4. Ativar primeiro uma chave de teste ligada a utilizador técnico sem privilégios administrativos amplos e uma ferramenta inofensiva; observar logs e limites; ativar ferramentas editoriais específicas uma de cada vez.
5. Rollback operacional imediato: desativar servidor/revogar chaves. Reverter imagem/código requer compatibilidade de esquema; usar backup emparelhado DB + filestore quando necessário. Nunca usar `docker compose down -v` nem retirar o fail-closed gate.

## 6. Verificação e critérios de aceitação

Testes automatizados do addon:
- Instalação limpa e upgrade Odoo 19, manifestos, menu/segurança, licença/atribuição.
- Handshake e chamadas MCP num cliente HTTP real; casos válidos, invalidez de JSON, método, content type, corpo grande, credencial errada, expirada, revogada e utilizador desativado.
- Listagem apenas de ferramentas autorizadas; um cliente não executa ferramenta de outro servidor; ACL/record rules do Odoo bloqueiam acesso indevido e não são contornadas por `sudo()`.
- Leitura paginada e rascunho permitido; bloqueio de escrita publicada, campos sensíveis, ações críticas, contexto forjado, duplicações/replay e uso simultâneo.
- Auditoria redigida; logs e erros não contêm chaves, conteúdo sensível ou traceback; falha de ferramenta não produz alterações parciais.

Integração no deploy:
- `git submodule update --init --recursive` e verificação de gitlinks exatos.
- `bash scripts/validate-repository.sh`, `docker compose --env-file .env.ci -f deploy/coolify/docker-compose.yml config --quiet`, `python3 -m unittest tests/test_repository_contract.py tests/test_migration_contract.py -v`, `bash tests/test_coolify_runtime.sh`.
- Cenário descartável de migração inicial + repetição idempotente; Website e rotas públicas mantêm-se saudáveis.
- Smoke test autenticado do MCP apenas depois de ativação intencional; nunca usar credenciais reais em CI ou criar ferramenta pública por efeito da migração.

## 7. Decisões delegadas à implementação

- Revisar compatibilidade exata das APIs Odoo 19 e da versão MCP usada por n8n antes de fixar o código do transporte; preferir subconjunto padronizado e testar.
- Escolher abordagem técnica de rate limiting no reverse proxy/Odoo e de expiração de logs de acordo com o runtime observado, sem criar nova porta nem dependência de estado externo.
- Selecionar os métodos de negócio existentes e campos estritos para rascunhos do primeiro conjunto de ferramentas; preservar workflows e campos obrigatórios de cada domínio.
- Integrar documentação de configuração, rotação e recuperação operacional nos manuais existentes.

## 8. Gate de aprovação

**Nada de código, instalação ou ativação em produção antes de Marcelo aprovar este desenho.** Depois da aprovação: produzir plano de implementação incremental com testes, executar em fontes proprietárias, propor alterações por PR para revisão e validar primeiro em ambiente descartável. O deployment/ativação efetiva em `facodi.com` é um gate operacional separado.
