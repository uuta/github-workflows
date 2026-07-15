# Reusable Groq PR review

This repository provides a GitHub native reusable workflow that runs the open-source PR-Agent review and improve tools with Groq. It publishes an aggregate review summary and, when actionable suggestions are found, committable inline code suggestions. Automatic PR description is disabled, and the workflow does not check out or execute pull request code.

The job succeeds only when PR-Agent publishes or updates its `## PR Reviewer Guide` comment during the current run; a silent PR-Agent exit without review feedback fails the workflow.

## Use it from another repository

Create a caller workflow such as `.github/workflows/pr-review.yml`:

```yaml
name: PR Review

on:
  pull_request:
    types: [opened, reopened, synchronize, ready_for_review, review_requested]

permissions:
  contents: read
  issues: write
  pull-requests: write

jobs:
  review:
    uses: uuta/github-workflows/.github/workflows/pr-review.yml@0000000000000000000000000000000000000000
    secrets:
      groq_api_key: ${{ secrets.GROQ_API_KEY }}
```

Replace the all-zero placeholder with the full commit SHA of a released version of this workflow. Pinning a full SHA protects callers from unexpected changes.

Create an API key in the [Groq Console](https://console.groq.com/keys), then save it in the caller repository under **Settings → Secrets and variables → Actions** as a repository secret named `GROQ_API_KEY`. The caller passes only that named secret; do not pass all repository secrets.

The primary model is `groq/openai/gpt-oss-120b`. If that request fails, PR-Agent can fall back to `groq/llama-3.3-70b-versatile`.

Because this is a public reusable workflow, each caller supplies its own Groq secret and uses its own automatically provided `GITHUB_TOKEN` and GitHub Actions quota. This repository never stores a caller's key.

GitHub withholds Actions secrets from pull requests opened from forks. The reusable job therefore skips fork-originated pull requests. Do not substitute `pull_request_target`: combining privileged base-repository secrets with untrusted fork changes can expose those secrets.

For repository-specific review rules, callers may add a `.pr_agent.toml` file to their own repository. Keep model selection and credentials in the reusable workflow and use that file only for review behavior, such as `[pr_reviewer]` settings and `extra_instructions`.
