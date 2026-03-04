# Opinionated Production Release System

Opinionated Production Release System for Kubernetes-based services built with GitHub Actions, semantic versioning, and immutable Docker images.

---

## Problem

Most teams ship to production without a controlled release process:

- no clear separation between dev, staging, and production environments
- manual git tags and GitHub Releases, prone to human error
- unpredictable versioning — no consistent semver across releases
- no explicit promotion step before production deploy
- direct pushes to production branches with no review gate

---

## Solution

This repository demonstrates a production-grade release system built on GitHub Actions and Kubernetes.

The system enforces a structured release workflow where:
- versions are calculated automatically from commit history
- release candidate branches and PRs are created by automation, not by hand
- git tags and GitHub Releases are created by a bot on merge, not manually
- production artifacts are explicitly promoted from a verified stage image
- deployment to production is a deliberate, two-step manual action

---

## Key Features

- deterministic semantic versioning from commit history
- automated creation of release candidate branches
- automated Git tag and GitHub Release creation
- Kubernetes deployments for dev and stage environments
- controlled promotion of artifacts to production
- immutable Docker images stored in GHCR
- separation between build, release, and deploy stages

This repository focuses on release engineering rather than application code.

---

## Overview

- Development happens in the `dev` branch
- Releases are created via the `dev-to-stage` workflow (manual trigger)
- Testing happens in the `stage` environment
- Production deployment is a two-step manual process: promotion + deploy

Docker images are stored in GitHub Container Registry (GHCR).
Git tags and GitHub Releases are created automatically on merge to `stage`.

---

## Repository Structure

```
.github/workflows/  — CI/CD pipelines
k8s/                — Kubernetes manifests used for deployments
repository-rules/   — GitHub repository protection rulesets
scripts/            — helper scripts used by workflows
README.md           — system documentation
```

---

## Release Flow

```
Developer
  │
  │ push / merge (SQUASH commit)
  ▼
BRANCH: dev
  │
  │ auto: build-deploy-dev-stage.yml (on push dev)
  │      - build + push image
  │      - deploy to dev namespace
  ▼
ENV: dev (Kubernetes)

DEVELOPER
  │
  │ decides feature set is ready for testing
  │
  │ manual: run workflow dev-to-stage.yml
  │      - calculates next semver from commits
  │      - creates branch release/rc/X.Y.Z
  │      - opens PR branch release/rc/X.Y.Z → branch stage
  ▼
PR: branch release/rc/X.Y.Z → branch stage
  │
  │ Developers
  │ resolve merge conflicts (if any)
  │ between branch dev and branch stage
  ▼
Manager
  │
  │ review PR
  │ approve release
  │ merge PR into branch stage
  ▼
BRANCH: stage
  │
  │ auto: create-release-tag.yml (on push stage)
  │      - reads PR label tag:vX.Y.Z
  │      - creates git tag vX.Y.Z + GitHub Release
  │
  │ auto: build-deploy-dev-stage.yml (on push stage)
  │      - waits for tag vX.Y.Z on this commit
  │      - builds/pushes image vX.Y.Z
  │      - deploys to stage namespace
  ▼
ENV: stage (Kubernetes)
  │
  │ QA testing
  │
  │ if everything is OK → continue to production promotion
  │
  │ if a bug is found →
  │    return to the beginning of the process
  │    developer fixes the issue in branch dev
  │    and starts the dev → stage workflow again
  │
  │    the next release will automatically receive
  │    the next version number (based on existing git tags)
  ▼

RELEASE MANAGER
  │
  │ manual: run promote-release-to-production.yml
  │      - creates git tag production/vX.Y.Z
  │      - tags image: vX.Y.Z → production-vX.Y.Z
  ▼
PRODUCTION ARTIFACT READY (image production-vX.Y.Z)

RELEASE MANAGER
  │
  │ manual: run deploy-stage-to-prod.yml
  │      - choose prod environment (namespace)
  │      - choose production-vX.Y.Z
  │      - deploy
  ▼
ENV: prod-region-* (Kubernetes namespaces)
```

---

## Roles

| Role | Responsibilities |
|---|---|
| **Developer** | Pushes to `dev`, resolves merge conflicts in RC PRs, runs `dev-to-stage` workflow |
| **Release Manager** | Reviews and merges RC PR into `stage`, runs `promote-release-to-production` and `deploy-stage-to-prod` workflows |
| **QA** | Tests in `stage` environment, gives go/no-go for production promotion |

Release Manager and the PR reviewer can be the same person.

---

## Branch Model

| Branch | Purpose |
|---|---|
| `dev` | Active development, auto-deployed to `dev` Kubernetes namespace on every push |
| `stage` | Staging, auto-deployed to `stage` Kubernetes namespace on merge of RC PR |
| `release/rc/X.Y.Z` | Temporary RC branch, created by `dev-to-stage` workflow, deleted after PR is merged or closed |

Production has **no dedicated branch**. It is a deployment environment (Kubernetes namespace), not a git branch.

---

## Versioning

### Version calculation

`dev-to-stage.yml` uses `@semantic-release/commit-analyzer` with the `conventionalcommits` preset to analyze commits between `stage` and `dev`:

| Commit type | Version bump |
|---|---|
| `fix:` | patch |
| `feat:` | minor |
| `feat!:` / `BREAKING CHANGE` | major |

The base version is taken from the latest `vX.Y.Z` git tag already merged into `stage`. Fallback: `v0.0.0`.

### Label `tag:vX.Y.Z`

When `dev-to-stage` creates the RC PR, it adds two labels:
- `release`
- `tag:vX.Y.Z` — the exact version to be released

### Git tag creation

`create-release-tag.yml` triggers on push to `stage`. It:
1. Finds the merged RC PR for that commit
2. Reads the `tag:vX.Y.Z` label
3. Creates an annotated git tag `vX.Y.Z` via the GitHub App (release bot)
4. Creates a GitHub Release with the PR body as release notes

### Docker image tagging

`build-deploy-dev-stage.yml` on push to `stage`:
- Waits up to 120 seconds for a `vX.Y.Z` tag to appear on the current commit (24 attempts × 5 sec)
- Pushes three image tags:
  - `ghcr.io/{owner}/backend_service:{branch}-{sha7}` — always
  - `ghcr.io/{owner}/backend_service:stage-latest` — always
  - `ghcr.io/{owner}/backend_service:vX.Y.Z` — when version tag found

### Production image promotion

`promote-release-to-production.yml`:
- Pulls `ghcr.io/{owner}/backend_service:vX.Y.Z`
- Retags as `ghcr.io/{owner}/backend_service:production-vX.Y.Z`
- Pushes the production image
- Creates git tag `production/vX.Y.Z`

Only `production-vX.Y.Z` images are deployed to production namespaces.

---

## Environments

| Environment | Infrastructure | Trigger |
|---|---|---|
| `dev` | Kubernetes namespace `dev` | push to `dev` branch |
| `stage` | Kubernetes namespace `stage` | push to `stage` branch |
| `prod-region-*` | Kubernetes namespaces | manual workflow dispatch |

### dev / stage

Deployed via `build-deploy-dev-stage.yml`. Uses `kubectl` with kubeconfig from `KUBECONFIG_EU_1` secret.
Optionally runs a database migration job (`backend-migration`) before deployment when `RUN_MIGRATION: 'true'`.

### production

Deployed via `deploy-stage-to-prod.yml`. Target namespace is chosen at workflow dispatch time.
Optionally runs migration before deploy (`run_migration` input, default: `false`).

---

## Required Secrets and Variables

### GitHub App (release bot)

Used by `dev-to-stage`, `create-release-tag`, and `promote-release-to-production`:

| Secret | Description |
|---|---|
| `RELEASE_BOT_APP_ID` | GitHub App ID |
| `RELEASE_BOT_PRIVATE_KEY` | GitHub App private key |

### Repository variables

| Variable | Used by | Description |
|---|---|---|
| `CODEOWNERS_LOGINS` | `cicd-guard` | Comma-separated GitHub logins of CI/CD owners |
| `ALLOWED_ACTORS` | `promote-release-to-production` | Comma-separated GitHub logins allowed to promote to production |
| `COMPOSE_DIR` | `deploy-pre-dev-compose` | Absolute path to Docker Compose directory on the pre-dev server |

---

## ReleaseBot

ReleaseBot is a GitHub App used by the CI/CD pipeline for release operations.

Used by workflows to:
- create git tags
- create GitHub Releases
- open and manage Pull Requests
- set labels on PRs
- interact with GitHub Actions workflows
- delete old container images from GitHub Container Registry

**Permissions required for ReleaseBot (GitHub App):**

| Permission | Level |
|---|---|
| Contents | Read & write |
| Pull requests | Read & write |
| Issues | Read & write |
| Workflows | Read & write |
| Packages | Read, Write, Delete |

> GitHub App is created at the organization level. Permissions are configured when creating the app.

---

## Supporting CI/CD Workflows

These workflows are not part of the main release flow but are required for the pipeline to function correctly.

### `deploy-pre-dev-compose.yml`

- **Trigger:** push to `pre-dev`
- **Purpose:** builds Docker image and deploys to Ubuntu server via Docker Compose over SSH
- **Part of release pipeline:** no — independent pre-dev environment

### `cicd-guard.yml`

- **Trigger:** pull_request (opened, synchronize, reopened, ready_for_review, edited) targeting `dev`, `stage`, `prod-*`
- **Purpose:** detects changes to CI/CD-related files (`.github/workflows/`, `k8s/`, `Dockerfile`, `.releaserc.json`), applies label `ci/cd`, requests review from CODEOWNERS, blocks merge until a CODEOWNER approves
- **Part of release pipeline:** yes — required status check on protected branches

### `cicd-guard-rerun-on-approve.yml`

- **Trigger:** pull_request_review submitted (any PR)
- **Purpose:** when a review is submitted, automatically re-runs the `cicd-guard` workflow for the current PR head SHA so the required status check turns green after CODEOWNER approval
- **Part of release pipeline:** yes — makes `cicd-guard` approval-aware

### `cleanup-closed-release-prs.yml`

- **Trigger:** pull_request closed (without merge) targeting `stage` or `dev`
- **Purpose:** automatically deletes the `release/rc/*` branch when its PR is closed without merging, preventing branch accumulation
- **Part of release pipeline:** supporting — keeps the repository clean

### `ghcr-image-retention.yml`

- **Trigger:** workflow_dispatch (manual)
- **Purpose:** deletes old non-production GHCR image versions, keeping the last N (configurable). Images tagged `production-v*` are never deleted.
- **Part of release pipeline:** no — maintenance workflow, run on demand

---

## Repository Protection Rules

Rulesets are defined in [`repository-rules/`](repository-rules/) and applied via GitHub repository rulesets.

### `protect-cicd.json`

- **Applies to:** `dev`, `stage`, `pre-dev`, `prod-*`
- **Rules:**
  - Direct push blocked — PR required
  - Branch deletion blocked
  - Force-push blocked
  - Required status check: `cicd_guard` must pass before merge

### `prod-merge-requires-approval.json`

- **Applies to:** `prod-*` branches
- **Rules:**
  - PR required with at least **1 approving review**
  - Branch deletion blocked
  - Force-push blocked

### `release-rc-protected.json`

- **Applies to:** `release/rc/*`
- **Rules:**
  - Branch deletion blocked (only GitHub App / admins can delete)
  - Force-push blocked
- **Why:** prevents accidental deletion of in-flight RC branches; `cleanup-closed-release-prs.yml` deletes them automatically via the GitHub App after PR close

### `restrict-tag-creation.json`

- **Applies to:** all tags (`*`)
- **Rules:**
  - Tag creation, update, and deletion restricted to bypass actors only
  - Bypass actors: GitHub App (release bot), organization admins, repository admins
- **Why:** prevents manual tag creation; all `vX.Y.Z` and `production/vX.Y.Z` tags are created exclusively by workflows via the GitHub App

---

### Optional Docker Compose environment

`pre-dev` is an optional environment for experiments or early integration testing. It is not part of the main CI/CD pipeline.

Deployment is handled by `deploy-pre-dev-compose.yml` and uses Docker Compose over SSH (not Kubernetes).

Required secrets: `SSH_HOST`, `SSH_USER`, `SSH_PRIVATE_KEY`, `GHCR_USER`, `GHCR_TOKEN`.
Required variable: `COMPOSE_DIR` (absolute path on the server).
