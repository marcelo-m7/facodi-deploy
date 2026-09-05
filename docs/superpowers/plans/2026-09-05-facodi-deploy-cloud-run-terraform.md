# FACODI Deploy — Cloud Run + Terraform Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `marcelo-m7/facodi-deploy` as the reproducible composition and deployment repository for FACODI: pin both addons, build immutable Odoo 19 images, provision Google Cloud with Terraform, and release safely through Cloud Run + Cloud SQL.

**Architecture:** Terraform owns durable infrastructure and IAM. GitHub Actions owns image build and application rollout. Each environment has a Cloud Run service plus a Cloud Run migration job; the job initializes/upgrades Odoo before the service advances to the same immutable image.

**Tech Stack:** Terraform 1.16.1; `hashicorp/google >= 7.45.0, < 8.0.0`; Cloud Run v2, Cloud Run Jobs v2, Cloud SQL PostgreSQL 16, Cloud Storage, Secret Manager, Artifact Registry, IAM/WIF; Docker/Odoo 19 Community; GitHub Actions; Bash; Python 3 stdlib tests.

**Spec:** `docs/superpowers/specs/2026-09-05-facodi-deploy-cloud-run-terraform-design.md`

## Approved execution refinement

The bootstrap root declares a partial `gcs` backend even though its first initialization uses `-backend=false`. After the bootstrap creates `marcelo-497411-facodi-tfstate`, its local state is migrated into that bucket with `terraform init -migrate-state -backend-config=...`. This correction was approved before implementation.

The implementation additionally exposes staging `min_instances` with a default of `0`; acceptance tests for Odoo cron/background execution run with `min_instances = 1` before production activation.

## Global Constraints

- Default project: `marcelo-497411`; region: `europe-southwest1`.
- `facodi-learning` and `facodi-theme` remain independent repositories consumed as pinned Git submodules.
- Current Odoo technical modules are `facodi_learning` and `website_facodi`.
- Base image: `odoo:19.0`; database: PostgreSQL 16.
- Cloud Run v1 policy: `workers=0`, `max_cron_threads=1`, `max_instance_count=1`, `proxy_mode=true`.
- Do not use the upstream Odoo Docker entrypoint unchanged: it treats `PORT` as PostgreSQL port, while Cloud Run reserves `PORT` for HTTP. FACODI uses `PORT` only for HTTP and `DB_PORT=5432`/`PGPORT=5432` for PostgreSQL.
- Odoo database initialization and addon updates execute in a Cloud Run v2 Job before service rollout; the web service never migrates during startup.
- No service-account JSON keys and no secret payloads in Git or Terraform state.
- Terraform creates Secret Manager containers/IAM only. Secret versions and the Cloud SQL `odoo` password are configured outside Terraform.
- Images are addressed by immutable `facodi-deploy` Git SHA; no deployment uses `latest` as source of truth.
- Terraform ignores application-driven image changes on the Cloud Run service and migration job.
- Production remains disabled until staging acceptance passes, including Cloud Storage filestore persistence tests.

---

## Implementation status

The proposal branch contains the implementation described by this plan: pinned addon gitlinks, Cloud Run-safe Odoo image/entrypoint, Terraform bootstrap/shared/runtime/environment stacks, database-user bootstrap, runtime deployment/verification adapters, GitHub Actions workflows, tests, README and operations runbook.

The final completion gate remains intentionally open until Terraform/provider validation and a real staging apply can be executed. Static repository tests and shell/YAML checks can be run without Google credentials; Docker/Terraform/cloud verification require an environment that provides those tools and, for cloud operations, an authorized Google Cloud administrator/bootstrap identity.

For the detailed task history and acceptance criteria, use the approved design in the linked spec and the operational sequence in `docs/operations.md`.
