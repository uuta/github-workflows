# Reusable OpenRouter PR review

This repository provides a GitHub native reusable workflow that runs the open-source PR-Agent tools with OpenRouter. Automatic PR description is disabled, and the workflow does not check out or execute pull request code.

The recommended setup is command-driven: an authorized maintainer posts `/review` in the pull request conversation to start a review. Pushing commits to the pull request does not start model inference in this mode. Command-driven `/review` runs only PR-Agent's review tool and publishes the `## PR Reviewer Guide` summary; it does not produce committable inline code suggestions.

Automatic review on `pull_request` events remains supported for callers that intentionally keep it. In that mode the workflow runs both the review and improve tools: it publishes the aggregate review summary and, when actionable suggestions are found, committable inline code suggestions.

The job succeeds only when PR-Agent publishes or updates its `## PR Reviewer Guide` comment during the current run; a silent PR-Agent exit without review feedback fails the workflow.

## Recommended: command-driven reviews with `/review`

Create a caller workflow such as `.github/workflows/pr-review.yml`:

```yaml
name: PR Review

on:
  issue_comment:
    types: [created]

permissions:
  contents: read
  issues: write
  pull-requests: write

jobs:
  review:
    uses: uuta/github-workflows/.github/workflows/pr-review.yml@0000000000000000000000000000000000000000
    secrets:
      OPENROUTER_API_KEY: ${{ secrets.OPENROUTER_API_KEY }}
```

Replace the all-zero placeholder with the full commit SHA of a released version of this workflow. Pinning a full SHA protects callers from unexpected changes.

`issue_comment` workflows only run from the version of the workflow file on the repository's **default branch**. The caller workflow above must be merged to the default branch before GitHub dispatches any `/review` comment to it.

### How `/review` is authorized and interpreted

The guards live in this reusable workflow, not only in the caller, so a caller cannot accidentally widen access:

- The comment must be a top-level comment on a **pull request** conversation. Comments on ordinary issues are ignored.
- The comment author's association must be `OWNER`, `MEMBER`, or `COLLABORATOR`, and the author must not be a bot. Anything else is rejected before PR-Agent starts, so untrusted users cannot consume OpenRouter credits.
- The trimmed comment body must start with the `/review` command. Optional PR-Agent review arguments may follow it, for example `/review --pr_reviewer.extra_instructions="focus on error handling"`. Only the review command is invoked; other PR-Agent commands are not exposed.
- Non-command comments never reach PR-Agent or the model.

`/review` runs only PR-Agent's review tool: it publishes or updates the `## PR Reviewer Guide` summary comment. It does not run the improve tool, so it posts no committable inline code suggestions. Callers that want automatic committable suggestions must retain or add the `pull_request` trigger described below; the two triggers can be combined in one caller workflow.

These checks run in a secret-free gate job; only a comment that passes all of them reaches the review job, which holds the cancellable per-PR concurrency group. If a second authorized `/review` is posted while a review for the same pull request is still running, the older review is cancelled and replaced. Rejected comments — bots, untrusted users, ordinary issues, non-command comments — never start model inference and never cancel a review that is already running.

Because a maintainer explicitly requests each review, command-driven mode also works on pull requests opened from forks; the workflow still never checks out or executes pull request code.

## Optional: automatic reviews on pull request events

Callers that intentionally want automatic reviews can keep a `pull_request` trigger instead of (or in addition to) `issue_comment`:

```yaml
name: PR Review

on:
  pull_request:
    types: [opened, reopened, ready_for_review, review_requested]

permissions:
  contents: read
  issues: write
  pull-requests: write

jobs:
  review:
    uses: uuta/github-workflows/.github/workflows/pr-review.yml@0000000000000000000000000000000000000000
    secrets:
      OPENROUTER_API_KEY: ${{ secrets.OPENROUTER_API_KEY }}
```

Adding `synchronize` to the trigger types still works but is no longer recommended: it launches a full model review for every commit pushed to an open pull request, which is expensive and noisy for review-fix commits.

Existing callers that already subscribe to `pull_request` keep working unchanged. To migrate to command-driven mode, replace the `on: pull_request` trigger with `on: issue_comment: types: [created]` and merge that change to the default branch. Note that this migration also stops the automatic committable inline suggestions produced by the improve tool, because `/review` runs the review tool only; keep both triggers if you want on-demand `/review` plus automatic reviews with committable suggestions.

GitHub withholds Actions secrets from pull requests opened from forks. The reusable job therefore skips fork-originated `pull_request` events. Do not substitute `pull_request_target`: combining privileged base-repository secrets with untrusted fork changes can expose those secrets.

## OpenRouter API key

Create an API key in the [OpenRouter settings](https://openrouter.ai/settings/keys), then save it in the caller repository under **Settings → Secrets and variables → Actions** as a repository secret named `OPENROUTER_API_KEY`. The caller passes only that named secret; do not pass all repository secrets.

The primary model is `openrouter/z-ai/glm-5.2`. If that request fails, PR-Agent can fall back to `openrouter/minimax/minimax-m3`. PR-Agent allows up to 64,000 model tokens and uses a 1,000,000-token custom-model context limit for fitting pull request content.

Because this is a public reusable workflow, each caller supplies its own OpenRouter secret and uses its own automatically provided `GITHUB_TOKEN` and GitHub Actions quota. This repository never stores a caller's key.

## Repository-specific review rules

For repository-specific review rules, callers may add a `.pr_agent.toml` file to their own repository. Keep model selection and credentials in the reusable workflow and use that file only for review behavior, such as `[pr_reviewer]` settings and `extra_instructions`.
