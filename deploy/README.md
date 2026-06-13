# Deployment — GitLab CI → Helm → Kubernetes

Design/prep for deploying carbonmice-admin. The app is one Docker image (the `production`
target of the repo `Dockerfile`) run as two workloads against the **shared** carbonmice
Postgres, owning only the `admin` schema.

```
GitLab push ─▶ test ─▶ build (image → registry) ─▶ deploy (helm upgrade)
                                                        │
              Kubernetes namespace "carbonmice":        ▼
                ┌─────────────┐   ┌──────────────┐   ┌──────────────────────┐
   Ingress ───▶ │ web (Puma)  │   │ worker        │   │ migrate (Helm hook)  │
   (TLS)        │ N replicas  │   │ bin/jobs ×1   │   │ pre-upgrade Job      │
                │ app role    │   │ app role      │   │ migrator role        │
                └─────────────┘   └──────────────┘   └──────────────────────┘
                       └─────────────┴── shared Postgres (admin + public/Go) ──┘
```

## Why three workloads
- **web** — Puma, serves HTTP, scales horizontally. Uses the limited `carbonmice_admin_app`
  role and runs with `SKIP_DB_MIGRATE=true` so it never migrates.
- **worker** — one pod running `bin/jobs` (Solid Queue supervisor + recurring scheduler that
  fires `purge_sessions`). Also the app role (it has DML on the admin-schema `solid_queue_*`
  tables). Kept at 1 replica (`Recreate`) so a single scheduler runs.
- **migrate** — a Helm `pre-install,pre-upgrade` hook Job running `bin/rails db:migrate` as
  `carbonmice_admin_migrator`. It owns the admin objects, which is what makes the audit-log
  append-only `REVOKE` on the app role actually bite. Admin schema only — never `public`.

## One-time prerequisites (per environment)
1. **DB roles:** apply `db/roles/least_privilege.sql` to the shared Postgres and set passwords
   (see `db/roles/README.md`). Migrations run as the migrator; runtime as the app role.
2. **Namespace / registry pull secret:** the chart can create the namespace (`--create-namespace`).
   If the registry is private, create a `docker-registry` secret and set `imagePullSecrets`.
3. **Ingress + TLS:** an ingress controller (default class `nginx`) and, if using cert-manager,
   the issuer annotation in `values.yaml` (`ingress.annotations`).
4. **Kube access for CI:** a GitLab Kubernetes Agent (set `KUBE_CONTEXT`) or a `KUBECONFIG`
   CI/CD file variable.

## GitLab CI/CD variables (Settings → CI/CD → Variables)
| Variable | Masked | Purpose |
|----------|--------|---------|
| `RAILS_MASTER_KEY` | ✅ | decrypts `config/credentials.yml.enc` (provides secret_key_base) |
| `APP_DB_PASSWORD` | ✅ | runtime role `carbonmice_admin_app` |
| `MIGRATOR_DB_PASSWORD` | ✅ | migration role `carbonmice_admin_migrator` |
| `KUBE_CONTEXT` |  | GitLab Agent context, e.g. `group/proj:agent` |
| `DEPLOY_DB_HOST`, `DEPLOY_DB_NAME` |  | optional overrides of chart `env` defaults |

`CI_REGISTRY*`, `CI_COMMIT_SHORT_SHA`, etc. are provided by GitLab. The image is pushed to
`$CI_REGISTRY_IMAGE` and deployed by tag = commit SHA. The deploy job is **manual** on `main`.

## Pipeline stages (`.gitlab-ci.yml`)
- **test** — `ruby:4.0.0-slim` + a `postgres:17` service. Runs `db:test:prepare`
  (loads `structure.sql` for `admin`; `test_helper` loads `core_structure.sql` for the Go
  `public` fixture), then `bin/rails test`, `test:system` (rack_test), `rubocop`, `brakeman`.
  Linux runners don't hit the macOS pg-fork segfault, so parallel test workers can be enabled
  here later (commented `PARALLEL_WORKERS`).
- **build** — `docker build --target production`, push `:$CI_COMMIT_SHORT_SHA` + `:latest`
  to the GitLab Container Registry (main + tags only).
- **deploy** — `helm upgrade --install` with the image tag and secrets passed via `--set-string`.

## Manual deploy (without CI)
```bash
helm upgrade --install carbonmice-admin deploy/helm/carbonmice-admin \
  --namespace carbonmice --create-namespace \
  --set image.repository=registry.gitlab.com/<group>/carbonmice-admin \
  --set image.tag=<sha> \
  --set ingress.host=admin.example.com \
  --set-string secret.railsMasterKey="$(cat config/master.key)" \
  --set-string secret.appDbPassword=... \
  --set-string secret.migratorDbPassword=... \
  --wait
```
Or point at a Secret you manage yourself: `--set secret.existingSecret=carbonmice-admin-secret`
(keys: `rails-master-key`, `app-db-user`, `app-db-password`, `migrator-db-user`,
`migrator-db-password`).

## Validate the chart locally
```bash
helm lint deploy/helm/carbonmice-admin --set secret.railsMasterKey=x --set secret.appDbPassword=x --set secret.migratorDbPassword=x
helm template carbonmice-admin deploy/helm/carbonmice-admin --set ... | kubectl apply --dry-run=client -f -
```

## Status
Designed + chart renders clean (`helm lint` OK, `helm template` → 7 valid manifests). Not yet
applied to a cluster — needs a real namespace, DB roles, registry, and ingress/agent wired up.
