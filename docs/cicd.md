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
environment, on a **self-hosted GitHub Actions runner installed on the EC2 host**
(labels `self-hosted`, `linux`, `x64`). The job updates `/opt/nexora/monitoring` to
`origin/main` and runs the repository's own `scripts/deploy.sh` (render → pull → up →
reload → health-check with retry).

A self-hosted runner is used instead of SSH because GitHub-hosted runners use
thousands of dynamic Azure IP ranges that cannot be enumerated in a security group.
This keeps inbound SSH closed.

## 4. Deployment credentials

Runtime secrets (Telegram token, SMTP, DB DSN, Grafana password) live in the server's
git-ignored `.env.deploy`, never in git. The self-hosted runner executes locally on the
EC2, so no `DEPLOY_*` SSH secrets are required.

> Do not put server IPs or credentials in public files. Runtime secrets stay in
> `.env.deploy` on the server.

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