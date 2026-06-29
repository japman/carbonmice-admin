# carbonmice-admin — PEA Deploy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prepare a complete, offline-validated PEA deployment for `carbonmice-admin` (Rails) using the PEA values-only + shared-chart + shared-CI model, ready to apply once VPN/GitLab access returns.

**Architecture:** One image (the `production` target of the repo `Dockerfile`) deployed as a single **web** workload (Puma with Solid Queue folded in via `SOLID_QUEUE_IN_PUMA=true`, `SKIP_DB_MIGRATE=true`, app DB role) plus a **migrate Job** injected through the shared chart's `extraObjects` (migrator DB role, ArgoCD `PreSync` hook). Build/scan/tag/trigger handled by the shared `developer/share/ci` templates; image tags written into the deployment repo's `values.<env>.yml` by its `update-job`, then synced by ArgoCD.

**Tech Stack:** Rails 8.1 / Ruby 4.0.0, Puma, Solid Queue, PostgreSQL (shared with Go BE), Docker (nerdctl on PEA), Harbor registry, HashiCorp Vault, Helm (shared chart, not in our repos), ArgoCD, GitLab CI.

## Global Constraints

- **Edit only** `carbonmice-admin` (app) and `carbonmice-admin-deployment` (values). **Never** modify `carbonmice-main-fe`, `carbonmice-main-go-be`, `carbonmice-main-deployment`, the shared chart, or `developer/share/ci`.
- **Values-only:** do not author a Helm chart/templates in the deployment repo; use the shared chart via values keys proven by `carbonmice-main-deployment` and `developer_hhh_deployment/api/hhh-be`.
- **Registry / image:** `${HARBOR_URL}/mice-admin/fullstack/mice-admin-console-fs` (resolves to `harbor-app.pea.co.th/...`); pull secret `harbor-regcred`.
- **Vault:** mount `mice-admin`, path `<env>/fullstack/mice-admin-console-fs-secret`, K8s Secret name `mice-admin-console-fs-secret`, keys: `RAILS_MASTER_KEY`, `DB_USER`, `DB_PASSWORD` (app role), `MIGRATOR_DB_USER`, `MIGRATOR_DB_PASSWORD`.
- **GitOps = ArgoCD:** migrate Job annotations `argocd.argoproj.io/hook: PreSync` + `argocd.argoproj.io/hook-delete-policy: BeforeHookCreation`.
- **Runtime:** Puma port `3000`; health endpoint `GET /up`; `replicas: 1`, autoscaling off.
- **Env→branch/tag:** `develop`→dev (tag = commit short SHA), tag `uat-vX.Y.Z`→uat, tag `vX.Y.Z`→prod.
- **GitLab paths:** app = `developer/mice-admin/fullstack/mice-admin-console-fs`; deployment repo = `developer/mice-admin/deployment` (default branch `main`); values path within it = `fullstack/mice-admin-console-fs/values.<env>.yml`.
- **CONFIRM-with-platform markers** (carried from the spec; written as the documented default, flagged inline): the shared Postgres in-cluster DNS (`DB_HOST`), whether the chart runs `tpl` over `extraObjects`, and apt reachability on PEA runners. These do not block writing/validating config offline.

---

## File Structure

**`carbonmice-admin` (app repo):**
- Modify `Dockerfile` — base image via `${PROXY_IMAGE_PREFIX}` build arg (PEA mirror), docker.io default kept for local builds.
- Create `.gitlab-ci.yml` — include shared CI templates; wire variables + env jobs.
- Modify `deploy/README.md` — add "Deploying on PEA" section (prereqs + offline validation runbook) reconciling the app's own-chart notes with the PEA model.

**`carbonmice-admin-deployment` (values repo):**
- Modify `fullstack/mice-admin-console-fs/values.dev.yml` — Approach A (web + migrate Job).
- Modify `fullstack/mice-admin-console-fs/values.uat.yml` — env diffs.
- Modify `fullstack/mice-admin-console-fs/values.prod.yml` — env diffs.
- Modify `.gitlab-ci.yml` (`update-job`) — also bump the `extraObjects` migrate Job image.

> **Two git repos.** Tasks 1, 2, 6 commit to `carbonmice-admin`. Tasks 3, 4, 5 commit to `carbonmice-admin-deployment`. Each task's commit step names its repo. Do not push to `peaorigin` in any task (push is gated separately on GitLab permission); commit locally + push `origin` only if asked.

> **Verification note (offline).** The shared chart is not accessible, so we cannot `helm template`/`lint` the PEA values against it. Baseline gate for every YAML deliverable: it parses (`python3 -c "import yaml; list(yaml.safe_load_all(open(P)))"`). Stronger gates (docker build, `kubectl --dry-run=client`, `helm lint` of the app's own chart, `yq` simulation) are run when the tool is installed; if a tool is missing, note it and fall back to the parse gate.

---

## Task 1: Dockerfile — pull base image through the PEA mirror

**Files:**
- Modify: `carbonmice-admin/Dockerfile` (the single `FROM ... AS base` line + one new `ARG`)

**Interfaces:**
- Consumes: build args `PROXY_IMAGE_PREFIX` (passed by shared `build.yml`), `RUBY_VERSION`.
- Produces: a `production`-target image buildable both locally (docker.io default) and on PEA runners (mirror). No new symbols for later tasks.

**Why:** The shared `build.yml` runs `nerdctl build -f Dockerfile --build-arg PROXY_IMAGE_PREFIX=docker-registry-mirror.pea.co.th/library ...`. Today the Dockerfile hardcodes `FROM ruby:4.0.0-slim` (docker.io), which PEA runners cannot reach. Make the base image prefix a build arg with a docker.io default.

- [ ] **Step 1: Edit the base stage**

In `carbonmice-admin/Dockerfile`, change the top of the file from:

```dockerfile
ARG RUBY_VERSION=4.0.0

########################  base  ########################
FROM ruby:${RUBY_VERSION}-slim AS base
```

to:

```dockerfile
ARG RUBY_VERSION=4.0.0
# PEA build.yml passes PROXY_IMAGE_PREFIX=docker-registry-mirror.pea.co.th/library
# (runners cannot reach docker.io). Default keeps local builds working.
ARG PROXY_IMAGE_PREFIX=docker.io/library

########################  base  ########################
FROM ${PROXY_IMAGE_PREFIX}/ruby:${RUBY_VERSION}-slim AS base
```

Leave every other stage unchanged (only this one `FROM` references an external image; the rest are `FROM base`/`FROM build`/`FROM build_prod`).

- [ ] **Step 2: Verify it still builds locally (production target)**

Run: `cd carbonmice-admin && docker build --target production -t carbonmice-admin:plantest .`
Expected: build completes; final line `naming to docker.io/library/carbonmice-admin:plantest` (or equivalent success). The `RUN ... assets:precompile` stage runs without error.
If Docker is unavailable, fall back to: `docker build --no-cache --target base --build-arg PROXY_IMAGE_PREFIX=docker.io/library . 2>&1 | head` to confirm the `FROM` interpolates, and note Docker was unavailable for the full build.

- [ ] **Step 3: Verify the mirror override resolves syntactically**

Run: `cd carbonmice-admin && docker build --target base --build-arg PROXY_IMAGE_PREFIX=docker-registry-mirror.pea.co.th/library . 2>&1 | head -5`
Expected: the build attempts `FROM docker-registry-mirror.pea.co.th/library/ruby:4.0.0-slim` (it will fail to pull off-VPN — that is fine; we are confirming the interpolation, not network). Confirm the pulled reference in the output matches the mirror path.

- [ ] **Step 4: Commit (repo: carbonmice-admin)**

```bash
cd carbonmice-admin
git add Dockerfile
git commit -m "build: parameterize base image prefix for PEA mirror"
```

---

## Task 2: App `.gitlab-ci.yml` — wire the shared CI pipeline

**Files:**
- Create: `carbonmice-admin/.gitlab-ci.yml`

**Interfaces:**
- Consumes: shared templates from `developer/share/ci` (`build.yml`, `sqa-sonarqube.yml`, `sqa-trivy.yml`, `artifact.yml`, `update-deployment-template.yml`, `tag-uat.yml`, `tag-production.yml`); CI/CD variables `HARBOR_URL`, `HARBOR_ROBOT_NAME`, `HARBOR_ROBOT_TOKEN`, `DEPLOY_ACCESS_TOKEN` (set at group/project level, not in the file).
- Produces: pushes image `${HARBOR_URL}/mice-admin/fullstack/mice-admin-console-fs:<sha>`; triggers downstream `developer/mice-admin/deployment` with `UPSTREAM_VALUES_FILE_FULL_PATH` + `UPSTREAM_ENVIRONMENT_IMAGE_TAG` (consumed by Task 5's `update-job`).

**Why:** Mirror `carbonmice-main-fe/.gitlab-ci.yml` exactly, substituting admin's group/paths and `ref: main` (the generic Dockerfile-based templates — there is no Ruby branch and the build is language-agnostic). Omit `build-base.yml` (admin's Dockerfile is self-contained; no `Dockerfile.base`).

- [ ] **Step 1: Create `carbonmice-admin/.gitlab-ci.yml`**

```yaml
# carbonmice-admin — first Ruby/Rails project on PEA.
# Uses the generic (main-branch) shared CI templates; the build is Dockerfile-based.
include:
  - project: "developer/share/ci"
    ref: main
    file: "build.yml"
  - project: "developer/share/ci"
    ref: main
    file: "sqa-sonarqube.yml"
  - project: "developer/share/ci"
    ref: main
    file: "sqa-trivy.yml"
  - project: "developer/share/ci"
    ref: main
    file: "artifact.yml"
  - project: "developer/share/ci"
    ref: main
    file: "update-deployment-template.yml"
  - project: "developer/share/ci"
    ref: main
    file: "tag-uat.yml"
  - project: "developer/share/ci"
    ref: main
    file: "tag-production.yml"

variables:
  IMAGE_REPOSITORY: "${HARBOR_URL}/mice-admin/fullstack/mice-admin-console-fs"
  VALUES_FILE_PATH: "fullstack/mice-admin-console-fs"
  DOWNSTREAM_DEPLOYMENT_PATH: developer/mice-admin/deployment
  GROUP_NAME: "mice-admin"

# First Rails project: SonarQube/Trivy not yet provisioned — keep non-blocking.
sonarqube:
  allow_failure: true
trivy:
  allow_failure: true

stages:
  - build
  - sqa
  - artifact
  - update-deployment
  - tag-uat
  - update-deployment-uat
  - tag-production
  - update-deployment-production

workflow:
  rules:
    - if: '$CI_COMMIT_BRANCH == "develop"'
    - if: '$CI_COMMIT_BRANCH == "main"'
    - if: "$CI_COMMIT_TAG"

update-deployment-dev:
  extends: .update-deployment-template-dev
  variables:
    UPSTREAM_VALUES_FILE_FULL_PATH: "${VALUES_FILE_PATH}/values.dev.yml"
  only: null
  except: null
  rules:
    - if: '$CI_COMMIT_BRANCH == "develop"'

update-deployment-uat:
  extends: .update-deployment-template-uat
  variables:
    UPSTREAM_VALUES_FILE_FULL_PATH: "${VALUES_FILE_PATH}/values.uat.yml"

update-deployment-production:
  extends: .update-deployment-template-production
  variables:
    UPSTREAM_VALUES_FILE_FULL_PATH: "${VALUES_FILE_PATH}/values.prod.yml"
```

- [ ] **Step 2: YAML parses**

Run: `cd carbonmice-admin && python3 -c "import yaml; list(yaml.safe_load_all(open('.gitlab-ci.yml'))); print('OK')"`
Expected: `OK`

- [ ] **Step 3: Structural diff against the reference**

Run: `diff <(grep -oE '^(stages|workflow|variables|update-deployment-[a-z]+|sonarqube|trivy):' carbonmice-admin/.gitlab-ci.yml) <(grep -oE '^(stages|workflow|variables|update-deployment-[a-z]+|sonarqube|trivy):' carbonmice-main-fe/.gitlab-ci.yml)`
Expected: the only differences are admin omitting `build-base`-related lines (none at top level) — the job/stage skeleton otherwise matches main-fe. Manually confirm `IMAGE_REPOSITORY`, `VALUES_FILE_PATH`, `DOWNSTREAM_DEPLOYMENT_PATH`, `GROUP_NAME` all use admin values.
> Note: GitLab CI Lint (online, `/ci/lint`) is the authoritative check and must be run once access returns; record this in Task 6's runbook.

- [ ] **Step 4: Commit (repo: carbonmice-admin)**

```bash
cd carbonmice-admin
git add .gitlab-ci.yml
git commit -m "ci: add GitLab pipeline using shared developer/share/ci templates"
```

---

## Task 3: `values.dev.yml` — Approach A (web + migrate Job)

**Files:**
- Modify (overwrite skeleton): `carbonmice-admin-deployment/fullstack/mice-admin-console-fs/values.dev.yml`

**Interfaces:**
- Consumes: shared chart value keys (`deployment`, `service`, `ingress`, `vaultStaticSecret`, `extraObjects`) as used by `developer_hhh_deployment/api/hhh-be/values.dev.yml`; Vault Secret `mice-admin-console-fs-secret` (Global Constraints).
- Produces: a web Deployment (Puma) + a PreSync migrate Job. The `update-job` (Task 5) overwrites `.deployment.enabled`, `.deployment.image.repository`, `.deployment.image.tag`, `.deployment.env.APP_VERSION.value`, and the migrate Job image on each deploy.

**Why:** This is the canonical env file; uat/prod (Task 4) are this file with env-specific lines changed.

- [ ] **Step 1: Overwrite `values.dev.yml`**

```yaml
applicationName: "mice-admin-console-fs"

### WEB (Puma + Solid Queue in-puma; app DB role) ###
deployment:
  enabled: true
  replicas: 1
  imagePullSecrets: "harbor-regcred"
  podLabels:
    role: web
  image:
    repository: "harbor-app.pea.co.th/mice-admin/fullstack/mice-admin-console-fs"
    tag: ''            # set by deployment update-job (commit short SHA in dev)
    pullPolicy: IfNotPresent
  # No `command`: image ENTRYPOINT (bin/docker-entrypoint) waits for Postgres,
  # then runs CMD (Puma). SKIP_DB_MIGRATE=true => web never migrates.
  resources:
    requests:
      memory: 384Mi
      cpu: 100m
    limits:
      memory: 768Mi
      cpu: "1"
  readinessProbe:
    enabled: true
    httpGet:
      path: /up
      port: 3000
    initialDelaySeconds: 10
    periodSeconds: 10
  livenessProbe:
    enabled: true
    httpGet:
      path: /up
      port: 3000
    initialDelaySeconds: 20
    periodSeconds: 15
  ports:
    - containerPort: 3000
      name: http
      protocol: TCP
  envFrom:
    - name: mice-admin-console-fs-secret   # RAILS_MASTER_KEY, DB_USER/DB_PASSWORD (app role)
      type: secret
  env:
    RAILS_ENV:
      value: "production"
    RAILS_LOG_TO_STDOUT:
      value: "1"
    RAILS_SERVE_STATIC_FILES:
      value: "1"
    SOLID_QUEUE_IN_PUMA:
      value: "true"
    SKIP_DB_MIGRATE:
      value: "true"
    DB_HOST:
      value: "postgres.carbonmice.svc.cluster.local"   # CONFIRM: shared Go-BE Postgres DNS
    DB_PORT:
      value: "5432"
    DB_NAME:
      value: "carbon-mice"
    ADMIN_SESSION_TTL_DAYS:
      value: "30"
    APP_VERSION:
      value: ''        # set by update-job = image tag

### MIGRATE JOB (ArgoCD PreSync; migrator DB role) ###
extraObjects:
  - apiVersion: batch/v1
    kind: Job
    metadata:
      name: mice-admin-console-fs-migrate
      labels:
        app: mice-admin-console-fs
        component: migrate
      annotations:
        argocd.argoproj.io/hook: PreSync
        argocd.argoproj.io/hook-delete-policy: BeforeHookCreation
    spec:
      backoffLimit: 2
      template:
        metadata:
          labels:
            app: mice-admin-console-fs
            component: migrate
        spec:
          restartPolicy: Never
          imagePullSecrets:
            - name: harbor-regcred
          containers:
            - name: migrate
              image: "harbor-app.pea.co.th/mice-admin/fullstack/mice-admin-console-fs:latest"  # tag bumped by update-job
              imagePullPolicy: IfNotPresent
              # Keep image ENTRYPOINT (waits for Postgres); override only CMD.
              # db:migrate creates schema `admin` if missing; never touches `public`.
              args: ["./bin/rails", "db:migrate"]
              env:
                - name: RAILS_ENV
                  value: "production"
                - name: DB_HOST
                  value: "postgres.carbonmice.svc.cluster.local"   # CONFIRM (match web)
                - name: DB_PORT
                  value: "5432"
                - name: DB_NAME
                  value: "carbon-mice"
                - name: DB_USER
                  valueFrom:
                    secretKeyRef:
                      name: mice-admin-console-fs-secret
                      key: MIGRATOR_DB_USER
                - name: DB_PASSWORD
                  valueFrom:
                    secretKeyRef:
                      name: mice-admin-console-fs-secret
                      key: MIGRATOR_DB_PASSWORD
                - name: RAILS_MASTER_KEY
                  valueFrom:
                    secretKeyRef:
                      name: mice-admin-console-fs-secret
                      key: RAILS_MASTER_KEY
              resources:
                requests:
                  memory: 384Mi
                  cpu: 100m
                limits:
                  memory: 768Mi
                  cpu: "1"

### SERVICE ###
service:
  enabled: true
  type: ClusterIP
  ports:
    - port: 80
      name: http
      protocol: TCP
      targetPort: 3000

### INGRESS ###
ingress:
  enabled: true
  ingressClassName: 'nginx'
  annotations:
    nginx.ingress.kubernetes.io/proxy-body-size: "100m"
  hosts:
    - host: mice-admin-dev.pea.co.th
      paths:
        - path: /
          pathType: Prefix
          serviceName: mice-admin-console-fs
          servicePort: http

### VAULT ###
vaultStaticSecret:
  enabled: true
  name: mice-admin-console-fs-secret
  mount: mice-admin
  path: dev/fullstack/mice-admin-console-fs-secret
```

- [ ] **Step 2: YAML parses**

Run: `cd carbonmice-admin-deployment && python3 -c "import yaml; list(yaml.safe_load_all(open('fullstack/mice-admin-console-fs/values.dev.yml'))); print('OK')"`
Expected: `OK`

- [ ] **Step 3: Extract the migrate Job and dry-run it**

Run:
```bash
cd carbonmice-admin-deployment
python3 -c "import yaml; d=yaml.safe_load(open('fullstack/mice-admin-console-fs/values.dev.yml')); yaml.safe_dump(d['extraObjects'][0], open('/tmp/migrate-job.yaml','w'))"
kubectl apply --dry-run=client -f /tmp/migrate-job.yaml
```
Expected: `job.batch/mice-admin-console-fs-migrate created (dry run)`.
If `kubectl` is unavailable, note it; the YAML parse in Step 2 is the fallback gate.

- [ ] **Step 4: Key-set sanity vs known-good values**

Run: `diff <(grep -oE '^[a-zA-Z]+:' carbonmice-admin-deployment/fullstack/mice-admin-console-fs/values.dev.yml | sort -u) <(grep -oE '^[a-zA-Z]+:' developer_hhh_deployment/api/hhh-be/values.dev.yml | sort -u)`
Expected: admin's top-level keys are a subset of hhh's (`applicationName, deployment, extraObjects, ingress, service, vaultStaticSecret`); admin omits `additionalDeployments`. No admin-only top-level key that hhh lacks. Confirm visually.

- [ ] **Step 5: Commit (repo: carbonmice-admin-deployment)**

```bash
cd carbonmice-admin-deployment
git add fullstack/mice-admin-console-fs/values.dev.yml
git commit -m "deploy(dev): web (Puma+SQ-in-puma) + PreSync migrate Job values"
```

---

## Task 4: `values.uat.yml` and `values.prod.yml` — env overlays

**Files:**
- Modify: `carbonmice-admin-deployment/fullstack/mice-admin-console-fs/values.uat.yml`
- Modify: `carbonmice-admin-deployment/fullstack/mice-admin-console-fs/values.prod.yml`

**Interfaces:**
- Consumes: identical chart keys as Task 3.
- Produces: per-env web + migrate Job. Differences vs dev are exactly: ingress `host`, `vaultStaticSecret.path`, and the migrate Job `image` tag suffix (`/uat`, `/prod`); the `update-job` rewrites image repo/tag at deploy time per `DEPLOY_ENVIRONMENT`.

**Why:** uat/prod are dev with three lines changed. Full files given so the file is correct read in isolation.

- [ ] **Step 1: Write `values.uat.yml`** (identical to `values.dev.yml` except the lines below)

Copy `values.dev.yml` content verbatim, then apply these three changes:
1. `ingress.hosts[0].host`: `mice-admin-dev.pea.co.th` → `mice-admin-uat.pea.co.th`
2. `vaultStaticSecret.path`: `dev/fullstack/...` → `uat/fullstack/mice-admin-console-fs-secret`
3. `extraObjects[0].spec.template.spec.containers[0].image`: `.../mice-admin-console-fs:latest` → `harbor-app.pea.co.th/mice-admin/fullstack/mice-admin-console-fs/uat:latest`

The full resulting `values.uat.yml`:

```yaml
applicationName: "mice-admin-console-fs"

deployment:
  enabled: true
  replicas: 1
  imagePullSecrets: "harbor-regcred"
  podLabels:
    role: web
  image:
    repository: "harbor-app.pea.co.th/mice-admin/fullstack/mice-admin-console-fs"
    tag: ''            # set by update-job (uat-vX.Y.Z) — repo gets /uat suffix via DEPLOY_ENVIRONMENT
    pullPolicy: IfNotPresent
  resources:
    requests:
      memory: 384Mi
      cpu: 100m
    limits:
      memory: 768Mi
      cpu: "1"
  readinessProbe:
    enabled: true
    httpGet:
      path: /up
      port: 3000
    initialDelaySeconds: 10
    periodSeconds: 10
  livenessProbe:
    enabled: true
    httpGet:
      path: /up
      port: 3000
    initialDelaySeconds: 20
    periodSeconds: 15
  ports:
    - containerPort: 3000
      name: http
      protocol: TCP
  envFrom:
    - name: mice-admin-console-fs-secret
      type: secret
  env:
    RAILS_ENV:
      value: "production"
    RAILS_LOG_TO_STDOUT:
      value: "1"
    RAILS_SERVE_STATIC_FILES:
      value: "1"
    SOLID_QUEUE_IN_PUMA:
      value: "true"
    SKIP_DB_MIGRATE:
      value: "true"
    DB_HOST:
      value: "postgres.carbonmice.svc.cluster.local"   # CONFIRM
    DB_PORT:
      value: "5432"
    DB_NAME:
      value: "carbon-mice"
    ADMIN_SESSION_TTL_DAYS:
      value: "30"
    APP_VERSION:
      value: ''

extraObjects:
  - apiVersion: batch/v1
    kind: Job
    metadata:
      name: mice-admin-console-fs-migrate
      labels:
        app: mice-admin-console-fs
        component: migrate
      annotations:
        argocd.argoproj.io/hook: PreSync
        argocd.argoproj.io/hook-delete-policy: BeforeHookCreation
    spec:
      backoffLimit: 2
      template:
        metadata:
          labels:
            app: mice-admin-console-fs
            component: migrate
        spec:
          restartPolicy: Never
          imagePullSecrets:
            - name: harbor-regcred
          containers:
            - name: migrate
              image: "harbor-app.pea.co.th/mice-admin/fullstack/mice-admin-console-fs/uat:latest"
              imagePullPolicy: IfNotPresent
              args: ["./bin/rails", "db:migrate"]
              env:
                - name: RAILS_ENV
                  value: "production"
                - name: DB_HOST
                  value: "postgres.carbonmice.svc.cluster.local"   # CONFIRM
                - name: DB_PORT
                  value: "5432"
                - name: DB_NAME
                  value: "carbon-mice"
                - name: DB_USER
                  valueFrom:
                    secretKeyRef:
                      name: mice-admin-console-fs-secret
                      key: MIGRATOR_DB_USER
                - name: DB_PASSWORD
                  valueFrom:
                    secretKeyRef:
                      name: mice-admin-console-fs-secret
                      key: MIGRATOR_DB_PASSWORD
                - name: RAILS_MASTER_KEY
                  valueFrom:
                    secretKeyRef:
                      name: mice-admin-console-fs-secret
                      key: RAILS_MASTER_KEY
              resources:
                requests:
                  memory: 384Mi
                  cpu: 100m
                limits:
                  memory: 768Mi
                  cpu: "1"

service:
  enabled: true
  type: ClusterIP
  ports:
    - port: 80
      name: http
      protocol: TCP
      targetPort: 3000

ingress:
  enabled: true
  ingressClassName: 'nginx'
  annotations:
    nginx.ingress.kubernetes.io/proxy-body-size: "100m"
  hosts:
    - host: mice-admin-uat.pea.co.th
      paths:
        - path: /
          pathType: Prefix
          serviceName: mice-admin-console-fs
          servicePort: http

vaultStaticSecret:
  enabled: true
  name: mice-admin-console-fs-secret
  mount: mice-admin
  path: uat/fullstack/mice-admin-console-fs-secret
```

- [ ] **Step 2: Write `values.prod.yml`** (same as uat with host `mice-admin-prod.pea.co.th`, vault path `prod/...`, Job image suffix `/prod`)

The full resulting `values.prod.yml` is identical to the `values.uat.yml` block above except these three lines:
- `ingress.hosts[0].host`: `mice-admin-prod.pea.co.th`
- `vaultStaticSecret.path`: `prod/fullstack/mice-admin-console-fs-secret`
- `extraObjects[0]...containers[0].image`: `harbor-app.pea.co.th/mice-admin/fullstack/mice-admin-console-fs/prod:latest`

Write the complete file with exactly those three substitutions (all other lines byte-identical to `values.uat.yml`).

- [ ] **Step 3: Both parse + dry-run**

Run:
```bash
cd carbonmice-admin-deployment
for e in uat prod; do
  f="fullstack/mice-admin-console-fs/values.$e.yml"
  python3 -c "import yaml; list(yaml.safe_load_all(open('$f'))); print('$e OK')"
  python3 -c "import yaml; d=yaml.safe_load(open('$f')); yaml.safe_dump(d['extraObjects'][0], open('/tmp/job-$e.yaml','w'))"
  kubectl apply --dry-run=client -f /tmp/job-$e.yaml || echo "($e) kubectl unavailable — parse gate only"
done
```
Expected: `uat OK`, `prod OK`, and (if kubectl present) two `... (dry run)` lines.

- [ ] **Step 4: Confirm only the 3 intended lines differ across envs**

Run:
```bash
cd carbonmice-admin-deployment/fullstack/mice-admin-console-fs
diff values.dev.yml values.uat.yml
diff values.uat.yml values.prod.yml
```
Expected: each `diff` shows exactly the host line, the vault `path` line, and the migrate Job `image` line (dev↔uat also shows the `/` → `/uat` image change). No other differences.

- [ ] **Step 5: Commit (repo: carbonmice-admin-deployment)**

```bash
cd carbonmice-admin-deployment
git add fullstack/mice-admin-console-fs/values.uat.yml fullstack/mice-admin-console-fs/values.prod.yml
git commit -m "deploy(uat,prod): env overlays for web + migrate Job"
```

---

## Task 5: Deployment repo `update-job` — also bump the migrate Job image

**Files:**
- Modify: `carbonmice-admin-deployment/.gitlab-ci.yml`

**Interfaces:**
- Consumes: trigger vars `UPSTREAM_VALUES_FILE_FULL_PATH`, `UPSTREAM_ENVIRONMENT_IMAGE_TAG`, `DEPLOY_ENVIRONMENT` (from Task 2's downstream trigger), plus repo CI var `IMAGE_REPOSITORY` and `DEPLOY_ACCESS_TOKEN`.
- Produces: each deploy rewrites web image repo/tag/APP_VERSION (existing behaviour) **and** the `extraObjects` migrate Job image (new), so the Job never runs a stale image.

**Why:** The existing `update-job` only bumps `.deployment.*` (and `additionalDeployments` for `api/*`). Our migrate Job lives in `extraObjects`, which is not templated by the chart (per spec assumption #3) and not touched by the current job — so its image would go stale. Add one `yq` step matching the Job by `kind`.

- [ ] **Step 1: Add the `extraObjects` bump to `update-job`**

In `carbonmice-admin-deployment/.gitlab-ci.yml`, inside `script:`, immediately after the line:

```yaml
    - yq -i '.deployment.env.APP_VERSION.value = strenv(IMAGE_TAG)' $VALUES_FILE_FULL_PATH
```

add:

```yaml
    # Migrate Job lives in extraObjects (not templated by the chart) — bump its
    # image to the same env-suffixed repo:tag as the web deployment.
    - yq -i '(.extraObjects[] | select(.kind == "Job") | .spec.template.spec.containers[0].image) = strenv(IMAGE_REPOSITORY) + ":" + strenv(IMAGE_TAG)' $VALUES_FILE_FULL_PATH
```

(`IMAGE_REPOSITORY` is already exported with the `${DEPLOY_ENVIRONMENT}` suffix earlier in `before_script`, so the Job image gets the same `/uat`/`/prod` path as the web image.)

- [ ] **Step 2: YAML parses**

Run: `cd carbonmice-admin-deployment && python3 -c "import yaml; list(yaml.safe_load_all(open('.gitlab-ci.yml'))); print('OK')"`
Expected: `OK`

- [ ] **Step 3: Simulate the bump locally (if `yq` installed)**

Run:
```bash
cd carbonmice-admin-deployment
cp fullstack/mice-admin-console-fs/values.dev.yml /tmp/sim.yml
IMAGE_REPOSITORY="harbor-app.pea.co.th/mice-admin/fullstack/mice-admin-console-fs" \
IMAGE_TAG="abc1234" \
yq -i '(.extraObjects[] | select(.kind == "Job") | .spec.template.spec.containers[0].image) = strenv(IMAGE_REPOSITORY) + ":" + strenv(IMAGE_TAG)' /tmp/sim.yml
yq '.extraObjects[0].spec.template.spec.containers[0].image' /tmp/sim.yml
```
Expected: prints `harbor-app.pea.co.th/mice-admin/fullstack/mice-admin-console-fs:abc1234`.
If `yq` is not installed, note it; the production runner installs `yq` (`apk add yq`) so this only validates the expression syntax locally.

- [ ] **Step 4: Commit (repo: carbonmice-admin-deployment)**

```bash
cd carbonmice-admin-deployment
git add .gitlab-ci.yml
git commit -m "ci: bump extraObjects migrate Job image alongside web image"
```

---

## Task 6: PEA deploy docs + offline validation runbook

**Files:**
- Modify: `carbonmice-admin/deploy/README.md` (append a "Deploying on PEA" section)

**Interfaces:**
- Consumes: nothing at runtime.
- Produces: the hand-off checklist platform/DBA need (Vault keys, DB roles, Harbor, ArgoCD, GitLab vars) and the exact offline validation commands used in Tasks 1–5.

**Why:** The app's existing `deploy/README.md` documents the app's *own* chart (generic K8s, `helm upgrade`). PEA uses values-only + shared chart + ArgoCD. Add a clearly separated section so operators know which path applies, what must be provisioned first, and how this config was validated offline.

- [ ] **Step 1: Append the PEA section to `deploy/README.md`**

Append the following (keep the existing content above it intact):

````markdown

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

## One-time prerequisites (per environment) — platform/DBA
1. **DB roles:** apply `db/roles/least_privilege.sql` to the shared carbonmice
   Postgres; set passwords for `carbonmice_admin_app` and `carbonmice_admin_migrator`.
   Confirm the in-cluster Postgres DNS used by the Go backend and set it as
   `DB_HOST` in the values (currently `postgres.carbonmice.svc.cluster.local`).
2. **Vault:** create `mice-admin/<env>/fullstack/mice-admin-console-fs-secret` with keys:
   `RAILS_MASTER_KEY`, `DB_USER`, `DB_PASSWORD` (app role),
   `MIGRATOR_DB_USER`, `MIGRATOR_DB_PASSWORD`. The chart's `vaultStaticSecret`
   syncs these into the K8s Secret `mice-admin-console-fs-secret`.
3. **Harbor:** project `mice-admin`; a robot account for CI push; the
   `harbor-regcred` pull secret present in the target namespace.
4. **ArgoCD:** an Application pointing the shared chart at this repo's
   `values.<env>.yml` for the right namespace. Confirm it honours
   `argocd.argoproj.io/hook: PreSync` on `extraObjects`.
   **Sequencing:** run the app CI once (push `develop`) so `update-job` writes a
   real image tag before creating/enabling the Application (avoids an empty-tag sync).
5. **GitLab CI/CD variables:**
   - App repo (`developer/mice-admin/fullstack/mice-admin-console-fs`):
     `HARBOR_URL`, `HARBOR_ROBOT_NAME`, `HARBOR_ROBOT_TOKEN` (masked).
   - Deployment repo (`developer/mice-admin/deployment`): `IMAGE_REPOSITORY`
     (= `harbor-app.pea.co.th/mice-admin/fullstack/mice-admin-console-fs`),
     `DEPLOY_ACCESS_TOKEN` (masked). Default branch must be `main`.

## Assumptions to confirm with platform
- Whether the shared chart runs `tpl` over `extraObjects` (if yes, the migrate Job
  tag could be templated instead of bumped by `update-job` — current design bumps
  it, which is safe either way).
- apt/Debian mirror reachability on PEA runners for the Rails base image build.
- TLS/cert convention for `mice-admin-<env>.pea.co.th` (cert-manager issuer vs
  pre-created secret) — match how `carbonmice-main` hosts get certificates.

## Offline validation performed
- `Dockerfile`: `docker build --target production` (docker.io base fallback).
- `values.<env>.yml`: YAML parse + extract `extraObjects[0]` → `kubectl apply --dry-run=client`.
- App's own chart sanity: `helm lint deploy/helm/carbonmice-admin --set secret.railsMasterKey=x --set secret.appDbPassword=x --set secret.migratorDbPassword=x`.
- `.gitlab-ci.yml` (both repos): YAML parse + structural diff vs `carbonmice-main-fe`.
- Pending online: GitLab CI Lint, `helm template` against the real shared chart, a cluster apply.
````

- [ ] **Step 2: Doc parses as Markdown / no broken fences**

Run: `cd carbonmice-admin && python3 -c "t=open('deploy/README.md').read(); assert t.count('\`\`\`') % 2 == 0, 'unbalanced code fences'; print('fences OK')"`
Expected: `fences OK`

- [ ] **Step 3: App-chart lint sanity (proxy that env/secret shape is coherent)**

Run: `cd carbonmice-admin && helm lint deploy/helm/carbonmice-admin --set secret.railsMasterKey=x --set secret.appDbPassword=x --set secret.migratorDbPassword=x`
Expected: `1 chart(s) linted, 0 chart(s) failed`.
If `helm` is unavailable, note it and skip (this is a sanity proxy, not a gate on the PEA values).

- [ ] **Step 4: Commit (repo: carbonmice-admin)**

```bash
cd carbonmice-admin
git add deploy/README.md
git commit -m "docs: add PEA values-only/ArgoCD deploy + offline validation runbook"
```

---

## Self-Review (completed by plan author)

**Spec coverage:**
- Approach A web (Puma + SQ-in-puma + SKIP_DB_MIGRATE, app role, /up, replicas 1) → Task 3.
- Migrate Job via extraObjects (migrator role, ArgoCD PreSync) → Task 3 (+ tag bump Task 5).
- Dockerfile PEA mirror → Task 1. App CI → Task 2. Per-env values → Tasks 3–4.
- Registry/Vault/secret keys/ingress hosts → Global Constraints + Tasks 3–4.
- Prereqs (Vault, DB roles, Harbor, ArgoCD, GitLab vars) + offline validation plan + assumptions → Task 6.
- Out-of-scope items (no main edits, no chart authoring, optional CI test stage) → respected; the CI `test` stage is intentionally deferred (noted in spec §5A) and not added here.

**Placeholder scan:** No "TBD/TODO/handle appropriately". `CONFIRM` markers are concrete documented defaults flagged for platform confirmation (DB_HOST), not gaps. Committed `tag: ''` / Job `:latest` are deliberate, overwritten by `update-job` (documented).

**Type/identifier consistency:** Secret name `mice-admin-console-fs-secret`, keys `RAILS_MASTER_KEY`/`DB_USER`/`DB_PASSWORD`/`MIGRATOR_DB_USER`/`MIGRATOR_DB_PASSWORD`, applicationName `mice-admin-console-fs`, service port name `http`, image repo `harbor-app.pea.co.th/mice-admin/fullstack/mice-admin-console-fs`, downstream path `developer/mice-admin/deployment`, values path `fullstack/mice-admin-console-fs/values.<env>.yml` — all consistent across Tasks 2–6 and the Global Constraints.
