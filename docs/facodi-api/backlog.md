# Backlog de integração FACODI API

Epic de deploy: https://github.com/marcelo-m7/facodi-deploy/issues/255. Epic do addon: https://github.com/marcelo-m7/facodi-api/issues/1.

| Issue | Objetivo | Dependências |
| --- | --- | --- |
| [D01](https://github.com/marcelo-m7/facodi-deploy/issues/256) | Integrar facodi_api, Project e dependências Python na imagem e pins de deploy | [A04](https://github.com/marcelo-m7/facodi-api/issues/5), [A05](https://github.com/marcelo-m7/facodi-api/issues/6), [A12](https://github.com/marcelo-m7/facodi-api/issues/11) |
| [D02](https://github.com/marcelo-m7/facodi-deploy/issues/257) | Implementar seleção explícita legacy/odoo_python e migração idempotente com cutover | [D01](https://github.com/marcelo-m7/facodi-deploy/issues/256), [A08](https://github.com/marcelo-m7/facodi-api/issues/9), [A10](https://github.com/marcelo-m7/facodi-api/issues/12) |
| [D03](https://github.com/marcelo-m7/facodi-deploy/issues/258) | Provar pipeline integrada em staging e preparar release, backup e recuperação | [D02](https://github.com/marcelo-m7/facodi-deploy/issues/257), [A11](https://github.com/marcelo-m7/facodi-api/issues/13) |

## Gates de release

- [ ] Owner API revisto e testes A01–A12 concluídos.
- [ ] D01: imagem, lock e pins coerentes; Project instalado sem dependência Enterprise.
- [ ] D02: fresh/upgrade/segundo upgrade e provider local explícito, sem I/O no migrate.
- [ ] D03: staging, cron observado, replay, benchmark e paired backup/restore.
- [ ] Estratégia de build/replacement documentada. Se adotar prebuilt, concluir evidência Coolify em [#224](https://github.com/marcelo-m7/facodi-deploy/issues/224) / [#226](https://github.com/marcelo-m7/facodi-deploy/pull/226).
- [ ] Release explicitamente autorizado, preservando recursos/volumes e revisão editorial.

Este checklist é futuro. Publicar a proposta não satisfaz qualquer gate de runtime.

## Coordenação

Manter [epic curricular existente #20](https://github.com/marcelo-m7/facodi-deploy/issues/20) como histórico/contexto; não fechar nem sobrescrever backlog anterior. O presente conjunto cobre a nova direção do processamento em Python dentro do addon. Não duplicar o desenvolvimento prebuilt existente. Alterações necessárias em Learning/AI devem ser PRs nos owners, referidos na issue API responsável e consumidos apenas após revisão.

