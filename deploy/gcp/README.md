# FACODI on Google Compute Engine

This directory is an **independent deployment** for one Google Compute Engine VM. It does not connect to, replace, or copy the existing Coolify volumes. Keep Coolify serving `facodi.com` until a separately planned data migration and DNS cutover are completed.

## Runtime

The VM runs Docker Compose with PostgreSQL 16, the same pinned FACODI Odoo 19 image used for both a one-shot migration and the persistent Odoo process, plus Caddy for HTTPS. The database and Odoo filestore use separate named volumes. Caddy stores TLS certificates in another volume. Only Caddy publishes host ports 80/443; neither PostgreSQL nor Odoo is published. The `/websocket` path is forwarded to Odoo's gevent port 8072.

`deploy.sh` checks the committed source and submodule revisions, builds the exact commit image **before** stopping Odoo, starts PostgreSQL, stops Odoo, runs migration and restarts Odoo/Caddy only after migration exits successfully. An upgrade that fails leaves the application stopped. Build failures leave the running application untouched. This is a single-VM design with downtime during migration, not high availability. A host failure requires restoration of a matching database and filestore backup.

## Provision the VM

1. Choose a GCP project, region and zone. Reserve a static external IPv4 address in the same region as the VM. Provision a Debian VM with enough CPU/RAM for Odoo, PostgreSQL and image builds (start at 2 vCPU, 8 GiB RAM and 100 GiB persistent boot disk; resize based on measured workload). Apply a dedicated network tag and a firewall rule opening only TCP 80/443 to the public for that tag. Restrict SSH using OS Login/IAP or an equivalent access policy. Do not open 5432, 8069 or 8072.
2. Create an A record for a **separate hostname** (for example `gcp.facodi.com`) pointing to the static IP. Check DNS propagation before bringing up Caddy. Caddy obtains its TLS certificate using the public 80/443 ports.
3. Install Docker Engine and its Compose plugin from the [official Debian installation instructions](https://docs.docker.com/engine/install/debian/). Ensure the operator can use Docker. Access to the Docker socket grants host-level privileges; restrict it to trusted administrators.
4. On the VM, clone the chosen commit of this branch and initialize its exact submodule pins:

   ```bash
   git clone --branch deploy/gcp https://github.com/marcelo-m7/facodi-deploy.git
   cd facodi-deploy
   git submodule update --init --recursive
   bash scripts/validate-repository.sh
   ```

5. Copy `deploy/gcp/.env.example` to `deploy/gcp/.env`, set the test hostname and **distinct, randomly generated** PostgreSQL and Odoo admin passwords, and run `chmod 600 deploy/gcp/.env`. This file is a shell environment file sourced by `deploy.sh`; quote values containing shell metacharacters and permit edits only by trusted operators. Never put credentials in Git, instance metadata or shell history. Set `SUPABASE_URL` and `SUPABASE_SECRET_KEY` together only if this independent instance will use that processing plane. A separate instance must not reuse production callbacks or integration secrets without reviewing their effects.
6. Ensure backup storage and monitoring are configured before storing real data. Run the first deployment:

   ```bash
   bash deploy/gcp/deploy.sh
   ```

The script uses Compose project `facodi-gcp`; volume names are therefore scoped to that project. Do not run `docker compose down -v` or change the project name. `FACODI_IMAGE` is set to `facodi-gcp:<full-superproject-commit>` for both migration and Odoo. `FACODI_GCP_DOMAIN=facodi.com` and `www.facodi.com` are rejected by the script to prevent an accidental production-domain cutover.

## Check the deployment

Run these from the repository root on the VM after the script completes:

```bash
docker compose --project-name facodi-gcp --env-file deploy/gcp/.env -f deploy/gcp/docker-compose.yml ps
curl -fsSI https://gcp.facodi.com/web/login
```

Replace the URL with the configured hostname. Check `/`, `/pt/`, `/courses`, `/forum`, and authenticated `/odoo`; test a real attachment and the portal, then inspect the application and proxy logs. If Supabase is enabled, validate it against its intended isolated environment. A successful `/web/login` alone does not prove that assets, modules, filestore and authenticated workflows are healthy.

## Revisions, backup and recovery

Before an upgrade that may migrate data, stop incoming writes and capture **a matching PostgreSQL database backup and Odoo filestore backup**. Verify that both can be restored. Prefer a coordinated maintenance window and a tested snapshot/backup policy; a boot-disk snapshot or database dump taken at a different time from the filestore is not a valid rollback pair. Back up the GCP `.env` separately in a secure secret store.

Fetch the desired branch commit, update pinned submodules, run `bash scripts/validate-repository.sh`, inspect the change, and run `bash deploy/gcp/deploy.sh` again. The build occurs while the previous revision serves traffic. During migration, Caddy may return 502. If migration fails, inspect `migrate` logs and leave Odoo stopped; do not bypass the gate. Rolling back code alone after a schema/data migration may be unsafe. Restore the pre-upgrade database **and** filestore backups together, then deploy the matching known-good source commit. No command in this directory automatically modifies Coolify or GCP resources.

## Local/CI checks

```bash
git submodule update --init --recursive
bash scripts/validate-repository.sh
FACODI_IMAGE=facodi-gcp:ci docker compose --env-file deploy/gcp/.env.example -f deploy/gcp/docker-compose.yml config --quiet
python3 -m unittest tests/test_gcp_deploy.py -v
```

The GCP contract check validates Compose and the fail-closed deployment order. The existing Coolify end-to-end runtime test exercises the shared image and migration on a disposable database; it does not prove GCP DNS, firewall, TLS or actual VM provisioning. Follow the [Compute Engine instance guidance](https://cloud.google.com/compute/docs/instances/create-start-instance) and [static IP guidance](https://cloud.google.com/compute/docs/ip-addresses/configure-static-external-ip-address) when provisioning.
