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

---

# Deploying on PEA (values-only + shared chart + ArgoCD)

> This is the **PEA path**, separate from the generic chart above. On PEA the app
> is deployed by the **central shared Helm chart**, fed by `values.<env>.yml` in
> `developer/mice-admin/deployment` (`fullstack/mice-admin-console-fs/`), built by
> the shared `developer/share/ci` templates, and synced by **ArgoCD**.

## Architecture (Approach A)
- **web** — one Deployment: Puma on `:3000`, `SOLID_QUEUE_IN_PUMA=true` (worker
  folded in), `SKIP_DB_MIGRATE=true`, **app** DB role, `replicas: 1`, probe `/up`.
- **migrate** — a Job injected via the chart's `extraObjects`, `argocd.argoproj.io/hook: PreSync`,
  **migrator** DB role, `args: ["./bin/rails","db:migrate"]` (image ENTRYPOINT still
  waits for Postgres). Runs before each sync; cleaned up by `hook-delete-policy`.

> **Security note — web pod sees migrator credentials:** The web Deployment uses `envFrom`
> on the whole `mice-admin-console-fs-secret`, which also contains `MIGRATOR_DB_USER` and
> `MIGRATOR_DB_PASSWORD`. Those migrator credentials therefore land in the web pod's
> environment even though the web pod only uses the app-role `DB_USER`/`DB_PASSWORD`.
> The least-privilege role split holds for **normal operation**, but is **not** a hard
> security boundary as currently wired — a compromised or exec'd web pod could read
> `MIGRATOR_DB_PASSWORD` and perform DDL or rewrite the append-only `audit_logs`.
> Harden before/at the hardening sprint by one of:
> (a) if the shared chart's `deployment.env` supports `valueFrom`/`secretKeyRef`, give
>     the web pod ONLY the three app keys (`RAILS_MASTER_KEY`, `DB_USER`, `DB_PASSWORD`)
>     via `secretKeyRef` instead of `envFrom`; or
> (b) store migrator creds in a separate Vault path + a second `VaultStaticSecret` that
>     ONLY the migrate Job references.

## One-time prerequisites (per environment) — platform/DBA
1. **DB roles:** apply `db/roles/least_privilege.sql` to the shared carbonmice
   Postgres; set passwords for `carbonmice_admin_app` and `carbonmice_admin_migrator`.
   Confirm the in-cluster Postgres DNS used by the Go backend and set it as
   `DB_HOST` in the values (currently `postgres.carbonmice.svc.cluster.local`).
   **`DB_HOST` and `DB_NAME` must be sourced from the same place the Go backend gets
   them** — its per-environment Vault `DATABASE_URL`. These values very likely differ
   per environment and are likely NOT the placeholder in-cluster address. The Go
   backend's prod reference shows an external IP and DB name `carbonmice` (no hyphen),
   which differs from the placeholder `carbon-mice`. The operator MUST set the correct
   per-env `DB_HOST`/`DB_NAME` before the first apply; both values currently carry a
   `# CONFIRM` marker in the values files.
2. **Vault:** create `mice-admin/<env>/fullstack/mice-admin-console-fs-secret` with keys:
   `RAILS_MASTER_KEY`, `DB_USER`, `DB_PASSWORD` (app role),
   `MIGRATOR_DB_USER`, `MIGRATOR_DB_PASSWORD`. The chart's `vaultStaticSecret`
   syncs these into the K8s Secret `mice-admin-console-fs-secret`.
3. **Harbor:** project `mice-admin`; a robot account for CI push; the
   `harbor-regcred` pull secret present in the target namespace.
4. **ArgoCD:** an Application pointing the shared chart at this repo's
   `values.<env>.yml` for the right namespace. Confirm it honours
   `argocd.argoproj.io/hook: PreSync` on `extraObjects`.
   **First-deploy order:**
   1. Ensure the K8s Secret `mice-admin-console-fs-secret` EXISTS in the target
      namespace **before** the first ArgoCD sync, so the PreSync migrate Job can
      start. The `VaultStaticSecret` resource is part of the chart's manifests and
      ArgoCD only applies it during the Sync phase — *after* PreSync — so on a
      first-ever sync the Secret does not yet exist and the PreSync Job would fail.
      Provision the Secret out-of-band via either: (a) apply the chart's
      `VaultStaticSecret` manifest directly (so the Vault Secrets Operator
      reconciles it into the Secret), then confirm with
      `kubectl get secret mice-admin-console-fs-secret -n <namespace>`; or
      (b) have the platform pre-create the Secret. As an illustrative example,
      some operators trigger VSO reconcile via annotation:
      ```bash
      kubectl annotate vaultstaticsecret mice-admin-console-fs-secret \
        force-sync=$(date +%s) --overwrite
      ```
      **Confirm PEA's Vault Secrets Operator reconcile method (annotation/patch)
      — the exact trigger may differ.**
   2. Push `develop` once so `update-job` writes a real image tag into the values
      (avoids an empty-tag sync).
   3. Create/enable the ArgoCD Application for its first sync.
   **Image availability:** the same "image must exist first" ordering applies to
   uat/prod — the committed `/uat:latest` / `/prod:latest` placeholders do not exist
   in Harbor until that environment's tag pipeline (`uat-vX.Y.Z` / `vX.Y.Z`) has run.
   Do not enable the ArgoCD Application for an environment before its image exists.
   Steady-state syncs are unaffected — the Secret exists before any subsequent
   PreSync.
5. **GitLab CI/CD variables:**
   - App repo (`developer/mice-admin/fullstack/mice-admin-console-fs`):
     `HARBOR_URL`, `HARBOR_ROBOT_NAME`, `HARBOR_ROBOT_TOKEN` (masked).
   - Deployment repo (`developer/mice-admin/deployment`): `IMAGE_REPOSITORY`
     (= `harbor-app.pea.co.th/mice-admin/fullstack/mice-admin-console-fs`),
     `DEPLOY_ACCESS_TOKEN` (masked). Default branch must be `main`.
   > **Note — `DEPLOY_ENVIRONMENT`:** The image-path suffix (`/uat`, `/prod`;
   > empty for dev) comes from `DEPLOY_ENVIRONMENT`, which the shared
   > `update-deployment-template` sets and forwards via the pipeline trigger —
   > operators don't set it manually; confirm with the platform team.

## Assumptions to confirm with platform
- Whether the shared chart runs `tpl` over `extraObjects` (if yes, the migrate Job
  tag could be templated instead of bumped by `update-job` — current design bumps
  it, which is safe either way).
- apt/Debian mirror reachability on PEA runners for the Rails base image build.
- TLS/cert convention for `mice-admin-<env>.pea.co.th` (cert-manager issuer vs
  pre-created secret) — match how `carbonmice-main` hosts get certificates.
- **Tailwind/bundle reachability:** `docker build --target production` could NOT
  be validated offline — it fails at `assets:precompile`. This is NOT a Node
  dependency issue. The app uses importmap-rails + tailwindcss-rails 4.4.0, whose
  `tailwindcss-ruby` gem ships a per-platform standalone CLI binary (e.g.
  `4.3.0-x86_64-linux-gnu`) vendored within the gem itself. The actual requirement:
  the PEA build runner's `bundle install` must be able to fetch the platform-specific
  `tailwindcss-ruby` gem (including its binary) from the gem source or mirror.
  **Action:** verify the end-to-end image build on a VPN-connected machine / PEA
  runner before first deploy.

## Offline validation performed
- `Dockerfile`: syntax review and `docker build --target production` attempted
  (docker.io base fallback); build was **not completed offline** — fails at
  `assets:precompile` due to the `tailwindcss-ruby` gem's platform binary requiring
  network access to the gem source/mirror. See "Assumptions" above.
- `values.<env>.yml`: YAML parse + extract `extraObjects[0]` → `kubectl apply --dry-run=client`.
- App's own chart sanity: `helm lint deploy/helm/carbonmice-admin --set secret.railsMasterKey=x --set secret.appDbPassword=x --set secret.migratorDbPassword=x`.
- `.gitlab-ci.yml` (both repos): YAML parse + structural diff vs `carbonmice-main-fe`.
- `developer/share/ci` (`main` branch, cloned locally): verified that `build.yml` passes
  `--build-arg PROXY_IMAGE_PREFIX=${PROXY_IMAGE_PREFIX}` (the arg name Task 1's Dockerfile
  relies on) and that the `.update-deployment-template-{dev,uat,production}` anchors exist
  on that branch. The residual online check is only to confirm the GitLab-hosted `main` has
  not drifted — do this via GitLab CI Lint before first deploy.
- Pending online: GitLab CI Lint (drift check on hosted `main`), `helm template` against the real shared chart, a cluster apply.
