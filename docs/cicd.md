# CI/CD

Workflow: `.github/workflows/monitoring-cicd.yml`

## 1. Triggers

| Event | Behaviour |
|---|---|
| `pull_request` targeting `main` | Run the **validate** job only (never deploys) |
| `push` to `main` | Run **validate**, then **deploy** |
| `workflow_dispatch` | Manual run (validate only; deploy is gated to push events) |

A `concurrency` group prevents overlapping runs for the same ref.

## 2. Validate job

Runs on `ubuntu-latest`:

1. Installs `actionlint` (authoritative GitHub Actions workflow linter).
2. Runs `./scripts/validate.sh`, which:
   - renders Prometheus + Alertmanager config from `.env.example`;
   - validates Prometheus config and rules with `promtool`;
   - validates Alertmanager config with `amtool`;
   - validates Docker Compose with `docker compose config`;
   - validates the Grafana dashboard JSON;
   - parses generic YAML;
   - checks shell script syntax;
   - scans for hardcoded secrets;
   - runs `actionlint` if available.

Any failure fails the pipeline, which satisfies "fail the pipeline when invalid
configuration is detected".

## 3. Deploy job (push to main)

Runs only on `push` to `main`, after `validate` succeeds, in the `production`
environment. It connects to the deployment server over SSH using GitHub Secrets and
runs the repository's own `scripts/deploy.sh` (render → pull → up → reload →
health-check). If the deploy secrets are not configured, the job prints a notice and
exits successfully (so a fresh fork does not fail).

## 4. Required GitHub Secrets

Configure these in **Settings → Secrets and variables → Actions** (repository) or in
the `production` environment:

| Secret | Purpose |
|---|---|
| `DEPLOY_HOST` | Deployment server hostname or IP (e.g. the Nexora web tier) |
| `DEPLOY_USER` | SSH user |
| `DEPLOY_PORT` | SSH port (default 22) |
| `DEPLOY_PATH` | Absolute path to this repository on the server |
| `DEPLOY_SSH_KEY` | Private SSH key (PEM/OpenSSH) with access to the server |

On the server, the runtime secrets (Telegram token, SMTP, DB DSN, Grafana password)
live in `.env.deploy`, which is git-ignored and never committed.

> Do not put server IPs or credentials in public files. The workflow reads them only
> from GitHub Secrets.

## 5. Failure-testing preparation

You need to demonstrate one successful run and one failed run caused by invalid
configuration, without leaving invalid config on `main`.

### Successful run

1. Push any valid change to a branch and open a PR to `main`.
2. Observe the **Validate configuration** job pass.

### Failed run (intentional invalid config)

1. Create a branch, e.g. `ci/failure-demo`.
2. Break a rule on purpose, for example change a rule's `expr` to invalid PromQL:

   ```bash
   # prometheus/rules/alerts.yml
   # change:  expr: up{job="nexora-backend"} == 0
   # to:      expr: up{job="nexora-backend" ==== 
   ```

3. Commit and push the branch; open a PR to `main`.
4. The **Validate configuration** job fails at the `promtool check rules` step.
5. **Do not merge.** Close the PR and delete the branch, so `main` stays valid.

Alternatively, break `docker-compose.yml`, the dashboard JSON, or the Alertmanager
config to demonstrate a different validation failure.

Evidence (screenshots of the green and red runs) goes in
`screenshots/github-actions/`.

## 6. Security notes

- Least-privilege `permissions: contents: read`.
- Secrets are masked in logs by GitHub.
- No secrets are ever written to the repository.
- Deploy is gated to `push` on `main` and the `production` environment, so PRs from
  forks cannot deploy.