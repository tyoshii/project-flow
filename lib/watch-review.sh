#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/init.sh"

LOG_FILE="$LOG_DIR/review.log"
log_info "Review watcher started" | tee -a "$LOG_FILE"

MAX_REVIEW_ROUNDS=3

# Create a worktree for the PR branch and return the path
# Usage: setup_worktree <branch_name>
setup_worktree() {
  local branch_name="$1"
  local repo_path
  repo_path=$(get_repo_path)
  local worktree_path="${repo_path}/.worktrees/review-${branch_name}"

  # Clean up if exists from previous run
  if [[ -d "$worktree_path" ]]; then
    git -C "$repo_path" worktree remove "$worktree_path" --force 2>/dev/null || rm -rf "$worktree_path"
  fi

  git -C "$repo_path" fetch origin "$branch_name" main 2>>"$LOG_FILE" || {
    log_error "Failed to fetch origin/${branch_name}" | tee -a "$LOG_FILE"
    return 1
  }
  git -C "$repo_path" worktree add -B "$branch_name" "$worktree_path" "origin/${branch_name}" 2>>"$LOG_FILE"

  echo "$worktree_path"
}

# Remove worktree
cleanup_worktree() {
  local worktree_path="$1"
  local repo_path
  repo_path=$(get_repo_path)

  if [[ -d "$worktree_path" ]]; then
    git -C "$repo_path" worktree remove "$worktree_path" --force 2>/dev/null || rm -rf "$worktree_path"
  fi
}

# Run a single review round against the worktree.
# Sets $action and $claude_output in caller scope.
run_review() {
  local worktree_path="$1"
  local pr_number="$2"
  local pr_url="$3"
  local issue_number="$4"
  local title="$5"
  local body="$6"
  local comments="$7"
  local round="$8"
  local base_branch="$9"
  local pr_info="${10:-}"
  local prev_feedback="${11:-}"

  # Get diff from worktree against PR base branch
  local pr_diff
  pr_diff=$(git -C "$worktree_path" diff "origin/${base_branch}...HEAD" 2>/dev/null || echo "")

  local round_context=""
  if [[ "$round" -gt 1 ]]; then
    round_context="
## Review Round ${round}
This is review round ${round}. Previous feedback was applied locally. Check if the issues were properly fixed.

## Previous Feedback
${prev_feedback}
"
  fi

  local prompt
  prompt="$(cat "$PROMPTS_DIR/review.md")

## Issue #${issue_number}
Title: ${title}
Body:
${body}
${round_context}
## PR #${pr_number}
URL: ${pr_url}
PR Info:
${pr_info}

## Diff
\`\`\`diff
${pr_diff}
\`\`\`

## Issue Comments (context):
${comments}
"

  log_info "Running Claude to review PR #${pr_number} (round ${round})..." | tee -a "$LOG_FILE"

  claude_output=$(run_claude \
    "Review #${issue_number} (PR #${pr_number}, round ${round})" \
    "$prompt" \
    '"Bash(read-only:*)" "Read" "Glob" "Grep"' \
    "$worktree_path") || {
    log_error "Claude review failed for PR #${pr_number} (round ${round})" | tee -a "$LOG_FILE"
    claude_output=""
    action="[ERROR]"
    return
  }

  echo "$claude_output" >> "$LOG_FILE"
  action=$(echo "$claude_output" | grep -oE '\[(LGTM|CHANGES_REQUESTED)\]' | head -1 || echo "[LGTM]")
}

# Run fix in the worktree (commit only, no push)
run_fix() {
  local worktree_path="$1"
  local issue_number="$2"
  local pr_number="$3"
  local feedback="$4"

  local branch_name
  branch_name=$(git -C "$worktree_path" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")

  local prompt
  prompt="$(cat "$PROMPTS_DIR/review-fix.md")

## Issue #${issue_number}
## PR #${pr_number}
Branch: ${branch_name}

## Review Feedback to Address
${feedback}
"

  log_info "Running Claude to fix review feedback on PR #${pr_number}..." | tee -a "$LOG_FILE"

  local fix_output
  fix_output=$(run_claude \
    "ReviewFix #${issue_number} (PR #${pr_number})" \
    "$prompt" \
    '"Bash" "Read" "Edit" "Write" "Glob" "Grep"' \
    "$worktree_path") || {
    log_error "Claude fix failed for PR #${pr_number}" | tee -a "$LOG_FILE"
    return 1
  }

  echo "$fix_output" >> "$LOG_FILE"
}

# Push worktree branch to remote
push_worktree() {
  local worktree_path="$1"
  local branch_name
  branch_name=$(git -C "$worktree_path" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")

  if [[ -z "$branch_name" ]]; then
    log_error "Cannot push: branch name is empty" | tee -a "$LOG_FILE"
    return 1
  fi

  log_info "Pushing ${branch_name}..." | tee -a "$LOG_FILE"
  git -C "$worktree_path" push origin "$branch_name" 2>>"$LOG_FILE"
}

while true; do
  log_debug "Checking for Review issues..." >> "$LOG_FILE"

  items=$(get_items_by_status "$STATUS_REVIEW")
  count=$(echo "$items" | jq 'length')

  if [[ "$count" -eq 0 ]]; then
    log_debug "No issues in Review" >> "$LOG_FILE"
  else
    log_info "Found ${count} issue(s) in Review" | tee -a "$LOG_FILE"

    echo "$items" | jq -c '.[]' | while read -r item; do
      item_id=$(echo "$item" | jq -r '.itemId')
      issue_number=$(echo "$item" | jq -r '.number')
      issue_title=$(echo "$item" | jq -r '.title')

      # ループ検出: Review の試行回数チェック
      if check_retry_limit "$issue_number" "$item_id" "Review"; then
        continue
      fi

      log_info "Starting review for issue #${issue_number} (${issue_title})..." | tee -a "$LOG_FILE"

      pr_url=$(get_linked_pr "$issue_number")

      if [[ -z "$pr_url" ]]; then
        log_warn "Issue #${issue_number}: No linked PR found -> moving back to Dev" | tee -a "$LOG_FILE"
        add_issue_comment "$issue_number" "🤖 Review: $(msg "review.no_pr")"
        move_item_to_status "$item_id" "$STATUS_DEV"
        continue
      fi

      pr_number=$(echo "$pr_url" | grep -oE '[0-9]+$')
      branch_name=$(gh pr view "$pr_number" --repo "$REPO" --json headRefName --jq '.headRefName' 2>/dev/null || echo "")

      if [[ -z "$branch_name" ]]; then
        log_error "Issue #${issue_number}: Could not get branch name for PR #${pr_number}" | tee -a "$LOG_FILE"
        continue
      fi

      details=$(get_issue_details "$issue_number")
      title=$(echo "$details" | jq -r '.title')
      body=$(echo "$details" | jq -r '.body // ""')
      comments=$(echo "$details" | jq -r '.comments.nodes[] | "[\(.author.login) at \(.createdAt)]: \(.body)"' 2>/dev/null || echo "")

      # Fetch PR metadata once (reused across rounds)
      base_branch=$(gh pr view "$pr_number" --repo "$REPO" --json baseRefName --jq '.baseRefName' 2>/dev/null || echo "main")
      pr_info=$(gh pr view "$pr_number" --repo "$REPO" --json title,body,files,commits 2>/dev/null || echo "{}")

      # Setup worktree for the review-fix cycle
      worktree_path=""
      worktree_path=$(setup_worktree "$branch_name") || {
        log_error "Issue #${issue_number}: Failed to setup worktree for ${branch_name}" | tee -a "$LOG_FILE"
        continue
      }

      # Review-fix loop (all local, no push until done)
      all_feedback=""
      final_action=""

      for round in $(seq 1 "$MAX_REVIEW_ROUNDS"); do
        action=""
        claude_output=""

        run_review "$worktree_path" "$pr_number" "$pr_url" "$issue_number" "$title" "$body" "$comments" "$round" "$base_branch" "$pr_info" "$all_feedback"

        if [[ "$action" == "[LGTM]" ]]; then
          final_action="LGTM"
          break
        fi

        if [[ "$action" == "[ERROR]" ]]; then
          final_action="ERROR"
          break
        fi

        # Accumulate feedback
        all_feedback="${all_feedback}

---
### Round ${round}
${claude_output}"

        log_info "PR #${pr_number}: Round ${round} changes requested. Attempting fix..." | tee -a "$LOG_FILE"
        if ! run_fix "$worktree_path" "$issue_number" "$pr_number" "$claude_output"; then
          final_action="FIX_FAILED"
          break
        fi

        if [[ "$round" -ge "$MAX_REVIEW_ROUNDS" ]]; then
          final_action="MAX_ROUNDS"
        fi
      done

      # Push the result (whether LGTM or gave up)
      has_local_commits=false
      if [[ "$(git -C "$worktree_path" rev-list "origin/${branch_name}..HEAD" --count 2>/dev/null || echo 0)" -gt 0 ]]; then
        has_local_commits=true
      fi

      if [[ "$has_local_commits" == true ]]; then
        push_worktree "$worktree_path" || { log_warn "Push failed for PR #${pr_number}" | tee -a "$LOG_FILE"; }
      fi

      # Cleanup worktree
      cleanup_worktree "$worktree_path"

      case "$final_action" in
        "LGTM")
          log_info "PR #${pr_number}: LGTM -> moving to QA" | tee -a "$LOG_FILE"

          review_body="🤖 Auto-review: LGTM

${claude_output}"
          if [[ -n "$all_feedback" ]]; then
            review_body="${review_body}

### $(msg "review.fix_history")
${all_feedback}"
          fi

          gh pr review "$pr_number" --repo "$REPO" --approve --body "$review_body" 2>/dev/null || true
          add_issue_comment "$issue_number" "🤖 Review: $(printf "$(msg "review.lgtm")" "$pr_number")"
          move_item_to_status "$item_id" "$STATUS_QA"
          ;;

        "MAX_ROUNDS"|"FIX_FAILED"|"ERROR")
          log_info "PR #${pr_number}: Could not fully resolve after ${MAX_REVIEW_ROUNDS} rounds -> moving to QA for human review" | tee -a "$LOG_FILE"

          pr_comment="🤖 Auto-review: $(printf "$(msg "review.escalate")" "$MAX_REVIEW_ROUNDS")

${all_feedback}"
          gh pr comment "$pr_number" --repo "$REPO" --body "$pr_comment" 2>/dev/null || true
          add_issue_comment "$issue_number" "🤖 Review: $(printf "$(msg "review.escalate_qa")" "$pr_number")"
          move_item_to_status "$item_id" "$STATUS_QA"
          ;;
      esac

      log_debug "Issue #${issue_number} processing complete" >> "$LOG_FILE"
    done
  fi

  log_debug "Next check in ${POLL_INTERVAL}s..." >> "$LOG_FILE"
  sleep "$POLL_INTERVAL"
done
