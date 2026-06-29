# carbonmice-admin — PEA build & deploy design

**Date:** 2026-06-29
**Status:** Design (approved in brainstorming; pending user review of this spec)
**Scope:** Make `carbonmice-admin` build and deploy on PEA infrastructure, matching
the existing PEA pattern used by `carbonmice-main`. Only `carbonmice-admin` (app)
and `carbonmice-admin-deployment` (values) are modified. `carbonmice-main-*`
(fe, go-be, deployment) are reference only — **never edited**.

---

## 1. Goal & constraints

- **Goal:** Prepare a complete, correct deployment configuration so that
  `carbonmice-admin` can deploy on PEA the same way `carbonmice-main` does, and
  validate it as far as possible **offline**. Actual `apply`/push happens later,
  once VPN to `gitlab.pea.co.th` / the cluster is back and the GitLab push
  permission is fixed.
- **Definition of done (this round):** config written + validated offline
  (YAML lint, local `docker build`, `kubectl --dry-run=client` on standalone
  manifests, app-chart `helm lint` as a sanity proxy). "Ready to apply", not
  "applied".
- **Hard constraint:** do not modify `carbonmice-main-fe`, `carbonmice-main-go-be`,
  or `carbonmice-main-deployment`.
- **Editable repos:** `carbonmice-admin` (the Rails app) and
  `carbonmice-admin-deployment` (Helm values consumed by the shared chart).
- **First-of-its-kind:** this is the **first Ruby/Rails project on PEA**. The
  shared chart, shared CI templates, and Harbor image mirror have not previously
  been exercised with a Rails app, so a few infra assumptions must be confirmed
  with the platform team (Section 7).

---

## 2. What carbonmice-admin actually is

A **Rails 8.1.3 / Ruby 4.0.0** server-rendered admin panel (Puma), **not** a
Node/Next.js frontend. Key runtime facts (from the repo `Dockerfile`,
`bin/docker-entrypoint`, and `deploy/helm/carbonmice-admin/`):

- Serves HTTP on **port 3000** (Puma). Health endpoint `/up` returns 200 once booted.
- Shares the **carbonmice Postgres with the Go backend**. Owns only the `admin`
  schema; reads (no writes via app role) the Go-owned `public` schema.
- Background jobs via **Solid Queue** (`bin/jobs` = supervisor + recurring
  scheduler that fires `purge_sessions`). Can run **inside Puma** via
  `SOLID_QUEUE_IN_PUMA=true`.
- **Two least-privilege DB roles** (the security model the app was designed
  around):
  - `carbonmice_admin_app` — runtime DML on `admin` only; cannot rewrite the
    append-only `audit_logs` (enforced by a `REVOKE`); `SELECT` on `public`.
  - `carbonmice_admin_migrator` — owns the `admin` schema; runs DDL/migrations.
- Migrations: `bin/docker-entrypoint` runs `db:migrate` on boot **unless**
  `SKIP_DB_MIGRATE=true`. `db:migrate` is enhanced (`lib/tasks/admin_schema.rake`)
  to `CREATE SCHEMA IF NOT EXISTS admin` first and never touches `public`.
- Required secrets: `RAILS_MASTER_KEY` (decrypts `config/credentials.yml.enc`),
  plus DB credentials for both roles.
- Required non-secret env: `RAILS_ENV`, `RAILS_LOG_TO_STDOUT`,
  `RAILS_SERVE_STATIC_FILES`, `DB_HOST`, `DB_PORT`, `DB_NAME`,
  `ADMIN_SESSION_TTL_DAYS`.

The app already ships its own generic-K8s Helm chart at
`deploy/helm/carbonmice-admin/` (web + worker + migrate-hook). **That chart is
the source of truth for what the app needs; it is NOT what PEA deploys** — PEA
uses a central shared chart fed by values files (Section 4).

---

## 3. The PEA deploy model (from carbonmice-main + developer/share/ci + hhh-be)

End-to-end, mirroring `carbonmice-main`:

1. Push to the **app repo** (`mice-admin-console-fs` on GitLab) triggers
   `.gitlab-ci.yml`, which `include`s shared templates from `developer/share/ci`.
2. **build** (`build.yml`): `nerdctl build -f Dockerfile` (final stage =
   `production`), save image tar. Base images are pulled through the PEA mirror
   `docker-registry-mirror.pea.co.th/library` via the `PROXY_IMAGE_PREFIX*`
   build args. **artifact** (`artifact.yml`): push `IMAGE_REPOSITORY:<short-sha>`
   to Harbor.
3. **sqa** (`sqa-sonarqube.yml`, `sqa-trivy.yml`): code quality + image scan.
4. **update-deployment** (`update-deployment-template.yml`): triggers the
   **deployment repo** (`carbonmice-admin-deployment`) on its `main` branch with
   `UPSTREAM_ENVIRONMENT_IMAGE_TAG` + `UPSTREAM_VALUES_FILE_FULL_PATH`. That
   repo's `update-job` uses `yq` to bump `deployment.image.tag` (and
   `APP_VERSION`) in the right `values.<env>.yml`, committing `[skip ci]`.
5. **ArgoCD** watches the deployment repo, renders the **shared chart** with the
   updated values, and syncs to the cluster.
6. Branch/tag → env mapping (same as main):
   - `develop` → dev (tag = commit short SHA)
   - tag `uat-vX.Y.Z` → uat (`tag-uat.yml` re-tags image `.../uat:<tag>`)
   - tag `vX.Y.Z` → prod (`tag-production.yml` re-tags `.../prod:<tag>`)

**Registry / image (confirmed):**
`harbor-app.pea.co.th/mice-admin/fullstack/mice-admin-console-fs`
(pull secret `harbor-regcred`). The skeleton's
`registry.pea.co.th/developer/mice-admin/...` is a placeholder and will be
corrected.

**Secrets:** HashiCorp Vault via the chart's `vaultStaticSecret` block. Mount
`mice-admin`, path `<env>/fullstack/mice-admin-console-fs-secret`, synced into a
K8s Secret consumed by pods.

**Shared chart capabilities (observed in `developer_hhh_deployment/api/hhh-be`):**
the chart is far richer than the admin skeleton implies. It supports:
`deployment.command` override, full probes/volumes/env/envFrom/resources/ports,
`service`, `ingress` (multi-host/path), `vaultStaticSecret`,
**`additionalDeployments`** (N extra deployments, e.g. workers), and
**`extraObjects`** (a list of raw manifests injected verbatim — hhh uses it for
Redis + Gotenberg). `extraObjects` is the mechanism we use for the migrate Job.

---

## 4. Chosen architecture — Approach A (single web workload + migrate Job)

One image, one Vault secret, two Kubernetes objects, expressed entirely through
the deployment repo's `values.<env>.yml` (values-only; the shared chart is not
modified).

```
┌──────────────────────────────── shared chart (values-only) ────────────────────────────────┐
│                                                                                              │
│  deployment (web)                              extraObjects[0]: kind: Job (migrate)          │
│  ─────────────────                             ────────────────────────────────────         │
│  image: harbor-app.pea.co.th/mice-admin/       image: <same repo>:<same tag>                 │
│         fullstack/mice-admin-console-fs        command: ["./bin/rails","db:migrate"]         │
│  command: Puma (bin/rails server -p 3000)      DB creds = MIGRATOR role (secretKeyRef)        │
│  env: SOLID_QUEUE_IN_PUMA=true   ← worker      ArgoCD PreSync hook → runs before web rollout │
│       SKIP_DB_MIGRATE=true       ← no migrate  hook-delete-policy: BeforeHookCreation         │
│  DB creds = APP role (via envFrom)             (re-runs every sync; deletes prior hook)       │
│  replicas: 1, autoscaling OFF                                                                 │
│  probe: GET /up :3000                                                                        │
│  service 80 → 3000                                                                           │
│  ingress: mice-admin-<env>.pea.co.th (nginx)                                                 │
│                                                                                              │
│  vaultStaticSecret → Secret "mice-admin-console-fs-secret"                                    │
│     keys: RAILS_MASTER_KEY, DB_USER, DB_PASSWORD (app role),                                  │
│           MIGRATOR_DB_USER, MIGRATOR_DB_PASSWORD                                               │
└──────────────────────────────────────────────────────────────────────────────────────────┘
```

### Why this shape

- **Worker folded into web** via `SOLID_QUEUE_IN_PUMA=true`. Solid Queue dedups
  recurring jobs at the DB level, so even with >1 replica it is safe; we keep
  `replicas: 1` anyway (admin panel, light traffic).
- **Migrate split into its own Job** (the app's intended separation), expressed
  via `extraObjects`. Because it is a separate object we give it the
  **migrator** role while the web pod keeps the **app** role — the
  least-privilege model is preserved **with no change to `bin/docker-entrypoint`**.
- **`SKIP_DB_MIGRATE=true` on web** so the web pod never migrates (it lacks DDL
  rights anyway).
- **ArgoCD PreSync hook** on the Job: ArgoCD runs it before syncing the rest, so
  migrations complete before the new web pods roll out. `hook-delete-policy:
  BeforeHookCreation` makes it re-run on every sync and clean up the prior Job.

### Role → credentials wiring

The Vault-synced Secret carries both role credential sets. The web `deployment`
takes the **app** role by consuming the secret with `envFrom` (the secret's
`DB_USER`/`DB_PASSWORD` default to the app role). The migrate Job (a raw manifest
we author in `extraObjects`) overrides `DB_USER`/`DB_PASSWORD` with
`valueFrom.secretKeyRef` → `MIGRATOR_DB_USER`/`MIGRATOR_DB_PASSWORD`, and pulls
`RAILS_MASTER_KEY` from the same secret.

### Per-environment values

Three near-identical `values.{dev,uat,prod}.yml`, differing only in:
- `deployment.image.tag` (dev = commit SHA, uat = `uat-vX.Y.Z`, prod = `vX.Y.Z`)
  and the image path suffix (`/uat`, `/prod`) per the main re-tag convention.
- `ingress` host: `mice-admin-dev.pea.co.th` / `-uat` / `-prod`.
- `vaultStaticSecret.path`: `dev|uat|prod/fullstack/mice-admin-console-fs-secret`.
- Optionally resources/replicas (keep replicas: 1 in all; prod may raise limits).

---

## 5. Deliverables

### A. `carbonmice-admin` (app repo)

1. **`Dockerfile`** — make base-image references resolve through the PEA mirror
   so `build.yml` can build it on PEA runners. Today it is `FROM ruby:4.0.0-slim`
   (docker.io, unreachable from PEA runners). Change the `FROM` lines to accept
   the build args the shared `build.yml` passes, e.g.
   `FROM ${PROXY_IMAGE_PREFIX:-docker.io/library}/ruby:${RUBY_VERSION}-slim`,
   keeping a docker.io default so local builds still work. The final stage stays
   `production` (build.yml builds the last stage; no `--target`). No
   `Dockerfile.base` is needed (admin's Dockerfile is self-contained;
   `build-base.yml` only runs on `Dockerfile.base` changes).
   - **Verify apt reachability** on PEA runners (the base/build stages run
     `apt-get install`); if the runners have no Debian mirror/proxy, this is a
     build blocker to raise with platform.
2. **`.gitlab-ci.yml`** (new) — `include` the shared templates from
   `developer/share/ci` (`ref: main` — the generic templates; no Ruby branch
   exists and the build is Dockerfile-generic). Wire:
   - `stages` from `stages.yml`; jobs from `build.yml`, `artifact.yml`,
     `sqa-sonarqube.yml`, `sqa-trivy.yml`, `update-deployment-template.yml`,
     `tag-uat.yml`, `tag-production.yml`.
   - Variables: `IMAGE_REPOSITORY`, `HARBOR_URL`, `HARBOR_ROBOT_NAME`,
     `HARBOR_ROBOT_TOKEN`, `GROUP_NAME`, `DOWNSTREAM_DEPLOYMENT_PATH`,
     `VALUES_FILE_FULL_PATH` (the three extend the `.update-deployment-template-*`
     anchors for dev/uat/prod), set as project/group CI/CD variables.
   - **Optional (recommended) `test` stage** mirroring the app README: `ruby`
     image + `postgres:17` service, `db:test:prepare`, `bin/rails test`,
     `test:system`, `rubocop`, `brakeman`. Marked optional to keep this round's
     scope on deployability; can be added in the same file.
   - `sonar-project.properties` if SonarQube requires it.

### B. `carbonmice-admin-deployment` (values repo)

3. **`fullstack/mice-admin-console-fs/values.{dev,uat,prod}.yml`** — replace the
   skeleton with the Approach-A shape (Section 4):
   - `deployment.enabled: true`, correct `image.repository`
     (`harbor-app.pea.co.th/mice-admin/fullstack/mice-admin-console-fs`),
     `command` (Puma), env (`RAILS_ENV`, `RAILS_LOG_TO_STDOUT`,
     `RAILS_SERVE_STATIC_FILES`, `DB_HOST`, `DB_PORT`, `DB_NAME`,
     `ADMIN_SESSION_TTL_DAYS`, `SKIP_DB_MIGRATE=true`, `SOLID_QUEUE_IN_PUMA=true`,
     `APP_VERSION`), `envFrom` the Vault secret, probes `GET /up:3000`,
     `replicas: 1`, resources, `containerPort: 3000`.
   - `service` 80 → 3000; `ingress.enabled: true` host `mice-admin-<env>.pea.co.th`
     (nginx, `proxy-body-size` as needed, TLS per platform convention).
   - `vaultStaticSecret`: mount `mice-admin`, path
     `<env>/fullstack/mice-admin-console-fs-secret`.
   - `extraObjects`: the migrate **Job** (ArgoCD PreSync hook, migrator creds via
     `secretKeyRef`, same image; image tag tracking per Section 7 item 3).
4. **`.gitlab-ci.yml` (update-job)** — keep the standard bump-job already in the
   skeleton. If the shared chart does **not** run `tpl` over `extraObjects`
   (Section 7 item 3), extend the `yq` step to also bump the migrate Job's image
   tag so it never goes stale.

### C. Documentation (in the app repo, reconciling `deploy/README.md`)

5. A short "Deploying on PEA" note: the Vault keys to populate per env, the SQL
   prerequisite (`db/roles/least_privilege.sql`), the GitLab CI/CD variables, and
   the ArgoCD Application wiring — i.e. the prerequisites in Section 6.

---

## 6. Prerequisites outside our two repos (document, hand off — not done by us)

These are platform/DBA tasks; we document exact values so they can be applied:

1. **Vault** — create path `mice-admin/<env>/fullstack/mice-admin-console-fs-secret`
   with keys: `RAILS_MASTER_KEY`, `DB_USER`, `DB_PASSWORD` (app role),
   `MIGRATOR_DB_USER`, `MIGRATOR_DB_PASSWORD`.
2. **DB roles** — apply `db/roles/least_privilege.sql` to the shared carbonmice
   Postgres and set the two role passwords; confirm `DB_HOST`/`DB_NAME` the
   cluster uses (the Go backend's Postgres service).
3. **Harbor** — project `mice-admin`, a robot account for CI push, and the
   `harbor-regcred` pull secret present in the target namespace.
4. **ArgoCD** — an Application pointing the shared chart at this repo's
   `values.<env>.yml` for the right namespace; confirm it honors
   `argocd.argoproj.io/hook: PreSync`.
5. **GitLab** — app-repo CI/CD variables (Section 5A) and the deployment repo's
   `DEPLOY_ACCESS_TOKEN`; the deployment repo's default branch must be `main`
   (the `update-deployment` trigger targets `branch: main`).

---

## 7. Assumptions to confirm with platform (do not block writing the plan)

1. **Shared chart secret/env model** — exact key names the chart expects and
   whether `deployment.env` supports `valueFrom`/`secretKeyRef` or only static
   `.value`. (We sidestep this for the migrate Job by authoring it as a raw
   `extraObjects` manifest with full control of its env.)
2. **apt/base-image reachability on PEA runners** for the Rails Debian image
   (Section 5A item 1).
3. **`extraObjects` templating** — does the chart run `tpl` over `extraObjects`
   (so the Job image tag can be `{{ .Values.deployment.image.tag }}` and track
   automatically)? If not, the deployment-repo `update-job` must bump the Job tag
   too (Section 5B item 4).
4. **ArgoCD honors PreSync hooks** for objects injected via `extraObjects`.
5. **TLS convention** for the ingress host (cert-manager issuer vs pre-created
   secret), matching how main's hosts get certificates.

---

## 8. Offline validation plan (this round)

Because the **shared chart is not accessible to us**, we cannot
`helm template`/`helm lint` the PEA values against it. We validate what we can:

- **YAML lint** all `values.<env>.yml` and `.gitlab-ci.yml`.
- **`docker build --target production`** locally (with a docker.io base fallback)
  to prove the Dockerfile change still builds and `assets:precompile` runs.
- **`kubectl apply --dry-run=client`** on the standalone migrate Job manifest
  (extracted from `extraObjects`).
- **`helm lint` / `helm template`** the app's **own** chart
  (`deploy/helm/carbonmice-admin`) as a sanity proxy that the env/secret/command
  shape is internally consistent.
- A **structural diff** of our `values.<env>.yml` against the working
  `hhh-be/values.*.yml` and `carbonmice-main-*` values to confirm we use only
  keys the shared chart is known to support.

Anything that requires the cluster, Vault, the shared chart, or GitLab is
explicitly **deferred to "apply time"** and listed as a prerequisite (Section 6).

---

## 9. Out of scope

- Any change to `carbonmice-main-fe`, `carbonmice-main-go-be`,
  `carbonmice-main-deployment`.
- Modifying the shared Helm chart or the shared CI templates
  (`developer/share/ci`).
- Provisioning Vault, DB roles, Harbor, ArgoCD, or the cluster (documented as
  prerequisites, executed by platform/DBA).
- Actually applying/pushing to PEA (gated on VPN + GitLab push permission;
  tracked separately).
