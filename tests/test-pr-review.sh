#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workflow="$repository_root/.github/workflows/pr-review.yml"
fixtures="$repository_root/tests/fixtures"
mock_bin="$repository_root/tests/support"
test_tmp="$(mktemp -d)"
trap 'rm -rf "$test_tmp"' EXIT

extract_run_step() {
  local step_name="$1"
  local output="$2"

  awk -v step_name="$step_name" '
    $0 == "      - name: " step_name { found_step = 1; next }
    found_step && $0 == "        run: |" { in_script = 1; next }
    in_script && /^          / { sub(/^          /, ""); print; next }
    in_script && /^$/ { print; next }
    in_script { exit }
  ' "$workflow" > "$output"

  if [ ! -s "$output" ]; then
    printf 'Could not extract workflow step: %s\n' "$step_name" >&2
    exit 1
  fi
}

assert_output() {
  local output_file="$1"
  local expected="$2"
  if ! grep -Fx "$expected" "$output_file" >/dev/null; then
    printf 'Missing output %q in %s\n' "$expected" "$output_file" >&2
    exit 1
  fi
}

run_diff_case() {
  local case_name="$1"
  local changed_files="$2"
  local pull_files="$3"
  local expected_review="$4"
  local expected_reason="$5"
  local expected_posts="$6"
  local output_file="$test_tmp/${case_name}.output"
  local post_log="$test_tmp/${case_name}.posts"
  : > "$output_file"
  : > "$post_log"

  PATH="$mock_bin:$PATH" \
    MOCK_CHANGED_FILES="$changed_files" \
    MOCK_DIFF_FAILURE="${MOCK_DIFF_FAILURE:-false}" \
    MOCK_PULL_FILES="$pull_files" \
    MOCK_POST_LOG="$post_log" \
    GH_TOKEN=test-token \
    REPOSITORY=example/repository \
    PR_NUMBER=42 \
    MAX_CHANGED_LINES=20000 \
    GITHUB_OUTPUT="$output_file" \
    bash "$test_tmp/diff-check.sh"

  assert_output "$output_file" "review_expected=$expected_review"
  assert_output "$output_file" "skip_reason=$expected_reason"
  if [ "$(grep -c '^api --method POST' "$post_log" || true)" -ne "$expected_posts" ]; then
    printf 'Unexpected skip comment count for %s\n' "$case_name" >&2
    exit 1
  fi
}

extract_run_step "Inspect pull request diff" "$test_tmp/diff-check.sh"
extract_run_step "Verify PR-Agent published a review" "$test_tmp/verify-review.sh"

invalid_output="$test_tmp/invalid-limit.output"
invalid_posts="$test_tmp/invalid-limit.posts"
: > "$invalid_output"
: > "$invalid_posts"
if PATH="$mock_bin:$PATH" \
  MOCK_CHANGED_FILES=$'design/screenshot.png\nassets/demo.gif' \
  MOCK_DIFF_FAILURE=false \
  MOCK_PULL_FILES="$fixtures/binary-only-files.json" \
  MOCK_POST_LOG="$invalid_posts" \
  GH_TOKEN=test-token \
  REPOSITORY=example/repository \
  PR_NUMBER=42 \
  MAX_CHANGED_LINES=0 \
  GITHUB_OUTPUT="$invalid_output" \
  bash "$test_tmp/diff-check.sh"; then
  echo 'Invalid max_changed_lines unexpectedly passed for a binary-only diff.' >&2
  exit 1
fi
if [ -s "$invalid_output" ] || [ -s "$invalid_posts" ]; then
  echo 'Invalid max_changed_lines reached an intentional skip path.' >&2
  exit 1
fi

run_diff_case \
  binary-only \
  $'design/screenshot.png\nassets/demo.gif' \
  "$fixtures/binary-only-files.json" \
  false \
  no_reviewable_text \
  0

MOCK_DIFF_FAILURE=true run_diff_case \
  oversized \
  '' \
  "$fixtures/oversized-files.json" \
  false \
  oversized \
  1
grep -F 'changes 20001 text lines, exceeding the configured limit of 20000' \
  "$test_tmp/oversized.posts" >/dev/null

run_diff_case \
  normal \
  $'src/reviewable.ts\npackage-lock.json' \
  "$fixtures/normal-files.json" \
  true \
  '' \
  0

PATH="$mock_bin:$PATH" \
  MOCK_COMMENTS="$fixtures/review-comment.json" \
  GH_TOKEN=test-token \
  REPOSITORY=example/repository \
  PR_NUMBER=42 \
  REVIEW_STARTED_AT=2026-09-06T01:00:00Z \
  bash "$test_tmp/verify-review.sh"

if PATH="$mock_bin:$PATH" \
  MOCK_COMMENTS="$fixtures/no-review-comment.json" \
  GH_TOKEN=test-token \
  REPOSITORY=example/repository \
  PR_NUMBER=42 \
  REVIEW_STARTED_AT=2026-09-06T01:00:00Z \
  bash "$test_tmp/verify-review.sh"; then
  echo 'Missing reviewer-guide comment unexpectedly passed verification.' >&2
  exit 1
fi

grep -F "if: steps.diff_check.outputs.review_expected == 'true'" "$workflow" | \
  grep -q .
if [ "$(grep -Fc "if: steps.diff_check.outputs.review_expected == 'true'" "$workflow")" -ne 3 ]; then
  echo 'PR-Agent review path is not guarded exactly three times.' >&2
  exit 1
fi

echo 'All PR review workflow cases passed.'
