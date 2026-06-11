# Public Release Manifest

This manifest defines the clean-tree policy for publishing WhatsApp Revenue Ops Platform as an open reference implementation for self-hosting n8n.

The public repo must be created from a clean copied subtree and a fresh `git init`. Do not publish the historical private multi-project workspace or a filtered version of its history.

After the clean initial release, public updates must still flow through the same clean-tree pipeline:

```text
source project tree -> final-clean tree -> publish-local repo -> ordinary commit -> normal push
```

Do not hand-edit `publish-local`, amend public commits, force push, or rewrite public history without a new standard-path decision.

## Include

Core project files:

- `README.md`
- `LICENSE`
- `.gitignore`
- `.gitattributes`
- `.dockerignore`
- `.github/workflows/ci.yml`
- `pyproject.toml`

Do not publish internal AI coordination entry files unless they are rewritten for the public repo:

- `AGENTS.md`
- `CLAUDE.md`
- `GEMINI.md`

Runtime and deployment files:

- `deploy/docker-compose.yml`
- `deploy/.env.example`
- `deploy/.env.mock`
- `deploy/.env.real.example`
- `deploy/docker/**`
- `deploy/init-db/**`
- `deploy/n8n/bootstrap-entrypoint.sh`
- `deploy/n8n/credentials/phase1c_revenue_ops_postgres.json` because it contains only the local-only demo Postgres credential (`postgres/postgres`) used by the public Compose stack; it is not a production secret and keeps the imported n8n workflow credential binding intact
- `deploy/n8n/workflows/**`
- `deploy/rag-seed/demo-company-policy.pdf`

Application and mock code:

- `mock/**`
- `scripts/**`

Required service source code now lives inside this project:

- `services/sales-agent/**`
- `services/ghl-sync/**`
- `services/rag-api/**`
- `apps/operator-console/**`

Documentation:

- `docs/architecture.md`
- `docs/architecture-diagram.mmd`
- `docs/case-study.md`
- `docs/data-model.md`
- `docs/public-release-manifest.md`
- `docs/portfolio/claims-ledger.md`
- `docs/proposal-packet/proof-points.md`
- selected sanitized `docs/assets/**` only after a separate asset review; no screenshots or videos are included by default

Historical planning, demo narration, and sales/proposal packet drafts are internal by default and must not be published unless separately rewritten for the public reference repo:

- `docs/phase-plan.md`
- `docs/codex-boundaries.md`
- `docs/gemini-checklist.md`
- `docs/demo-script.md`
- `docs/portfolio/recording-guide.md`
- `docs/portfolio/upwork-listing.md`
- `ai/proposal-packet/**`

## Exclude

Repository and internal coordination:

- `.git/`
- old private workspace history
- `ai/**`
- `AGENTS.md`
- `CLAUDE.md`
- `GEMINI.md`
- `experiments/**`
- any `*.bundle`
- historical planning docs listed above
- internal demo narration or proposal-packet drafts that have not passed a public asset review

Secrets and local runtime state:

- `deploy/.env`
- `.env`
- `.env.*` except `.env.example`, `.env.mock`, and `.env.real.example`
- logs
- local database dumps
- runtime volumes
- screenshots or videos containing credentials, real CRM IDs, real emails, real phone numbers, or real client names

Generated and dependency folders:

- `node_modules/`
- `.next/`
- `dist/`
- `build/`
- `__pycache__/`
- `.pytest_cache/`
- `.venv/`
- `tmp/`
- `temp/`

## Required Pre-Push Checks

Run these checks inside the clean release tree before the first public commit:

```powershell
gitleaks dir --redact .
git config user.email # must be a GitHub noreply address ending in @users.noreply.github.com
git status --short
git ls-files
```

Also run manual grep checks for:

- `GEMINI_API_KEY`
- `GHL_API_TOKEN`
- `CLERK_SECRET_KEY`
- `N8N_ENCRYPTION_KEY`
- `_AUTH_SECRET`
- `DATABASE_URL`
- `GHL_LOCATION_ID`
- `GHL_PIPELINE_ID`
- `GHL_STAGE_`
- `GHL_INTENT_FIELD_KEY`
- `ngrok`
- `trycloudflare`
- real phone numbers
- real email addresses
- real client names

## n8n Asset Rules

Workflow JSON files may be published only if they contain:

- no embedded API tokens
- no real webhook secrets
- no encrypted credential payloads
- no instance-specific credential exports
- only intentional env expressions such as `$env.AGENT_AUTH_SECRET`

n8n credential exports should not be published unless they are demonstrably non-sensitive local demo credentials. Prefer README/bootstrap instructions over credential JSON in the public repo.

## Standalone Build Requirement

Before publishing, verify the clean release tree can build without access to the old private multi-project workspace. In practice this means:

- no Dockerfile may `COPY` from a sibling monorepo project path,
- no Compose `build.context` may require `../..`,
- all required service source code must live inside the clean public repo, and
- `docker compose --env-file ./deploy/.env.mock -f ./deploy/docker-compose.yml build` must run from the clean tree before publication.

## License Boundary

The public repo's MIT license covers only this project's own code, docs, scripts, manifests, and mock/custom services.

n8n itself remains governed by n8n's own license terms, including the Sustainable Use License. The public wording must remain "open reference implementation for self-hosting n8n" and must not imply that this repository relicenses n8n.
