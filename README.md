# git-restack

Keep a single-commit PR branch current with `main` — safely, in one command.

```sh
git restack
```

git-restack is designed for two complementary uses:
- **Manually** by a developer keeping their PR branch up to date
- **Automatically** by a CI workflow that restacks every open PR whenever a commit lands on `main`

---

## When to use it

Your branch has **one commit**, `main` has moved, and you need to rebase before merging. That's the exact scenario `git restack` is built for.

It fetches the latest `origin/main`, resets your branch on top of it, replays your commit via cherry-pick, and tells you the right push command. No interactive prompts, no accidental force-pushes.

## When NOT to use it

- **Multiple commits on your branch** — squash first, then restack (see below).
- **Long-lived branches** that track `main` over weeks — use `git rebase` or `git merge`.
- **Stacked PRs** — restack only understands one base branch; stacked dependencies need a dedicated stacking tool.
- **No `origin` remote** — restack always fetches from `origin`.

---

## Automated use: keep all PRs current automatically

The primary value of git-restack is as part of a CI workflow. Every time a commit lands on `main`, a GitHub Actions workflow runs `git restack` on every open PR branch in the repo — keeping them all current without any developer action.

### How it works

1. A commit is merged to `main`
2. The workflow fires, iterates all PR branches, and runs `git restack --auto-cleanup` on each
3. **Clean branches** are pushed automatically — the PR stays current
4. **Conflicting branches** are left untouched — the workflow posts a PR comment with resolution instructions and sets a failed commit status to block merging until the author resolves it

When the author resolves the conflict and pushes, the workflow fires again, succeeds, and the merge block is cleared automatically.

### Setup

**Step 1 — Add the workflow files to your repo**

Copy `examples/restack-prs.yml`, `examples/ci.yml`, and `examples/release.yml` from this repo into your `.github/workflows/` directory.

The workflows use `github.event.repository.fork` to automatically determine where they should run:
- `restack-prs.yml` runs **only in forks** — no-op in the origin
- `ci.yml` and `release.yml` run **only in the origin** — no-op in forks

No repo names are hardcoded. No secrets or tokens need to be configured — GitHub provides `GITHUB_TOKEN` automatically to every workflow run.

**Step 2 — Add `git-restack` as a required status check**

In your repo's branch protection settings, add `git-restack` as a required status check on `main`. This ensures a conflicting PR cannot be merged until the author resolves the conflict and the workflow passes.

Without this step the workflow still posts a failed status and a comment, but the merge button remains unblocked.

**Step 3 — Fork owners sync `main`**

Fork owners inherit the workflow automatically when they sync `main` from upstream. No action required beyond the normal fork sync.

### Conflict resolution (for PR authors)

When the workflow posts a conflict warning on your PR:

```sh
git pull                     # get the latest state of your branch
git restack                  # replays your commit — shows the conflicting files
# fix conflicts in your editor
git add .
git restack --continue       # completes the cherry-pick
git push --force-with-lease origin <branch>
```

The workflow fires on your push, restacks cleanly, and clears the merge block.

---

## Manual use

```sh
# You're on a feature branch with one commit, main has moved:
git restack

# Preview without touching anything:
git restack --dry-run

# Use a different base branch:
git restack develop
```

After a successful restack, git-restack prints the push command — it never pushes for you.

## Installation

```sh
curl -o /usr/local/bin/git-restack \
  https://raw.githubusercontent.com/<you>/git-restack/main/git-restack
chmod +x /usr/local/bin/git-restack
```

Git treats any executable named `git-<cmd>` on your `PATH` as a subcommand, so `git restack` works immediately.

---

## The one-commit rule

`git restack` enforces exactly **one commit per branch**. This is a design constraint, not a bug.

The intended workflow is **one branch = one logical change = one commit**. This keeps rebasing trivial, conflicts isolated, and history linear.

If your branch has multiple commits, squash before restacking:

```sh
git reset --soft origin/main
git commit -m "feat: describe the whole change"
git restack
```

If the commits represent truly independent changes, split them into separate branches/PRs instead.

## Safety

Before doing anything destructive, git-restack:

- Checks for in-progress merges, rebases, or cherry-picks
- Requires a clean working tree (no uncommitted or staged changes)
- Creates a backup ref `backup/<branch>-<epoch>` you can reset to at any time
- Never pushes — only prints the correct push command

When your branch already exists on `origin`, it suggests `--force-with-lease` rather than `--force`. `--force-with-lease` fails safely if someone else pushed to the branch since your last fetch.

## Reference

```
git restack [base]              Replay the single commit not in base (default: main)
git restack --continue          Complete a restack after resolving conflicts manually
git restack --dry-run [base]    Simulate without touching your branch or local base
git restack --auto-cleanup      Delete the backup ref after a successful restack (for CI use)
git restack --help              Show help
git restack --version           Show version
```

**Requirements:** Bash 3.2+, Git 2.x

**License:** Apache 2.0
