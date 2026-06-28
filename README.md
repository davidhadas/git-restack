# git-restack

Keep a single-commit PR branch current with `main` — safely, in one command.

```sh
git restack
```

---

## When to use it

Your branch has **one commit**, `main` has moved, and you need to rebase before merging. That's the exact scenario `git restack` is built for.

It fetches the latest `origin/main`, resets your branch on top of it, replays your commit via cherry-pick, and tells you the right push command. No interactive prompts, no accidental force-pushes.

## When NOT to use it

- **Multiple commits on your branch** — squash first, then restack (see below).
- **Long-lived branches** that track `main` over weeks — use `git rebase` or `git merge`.
- **Stacked PRs** — restack only understands one base branch; stacked dependencies need a dedicated stacking tool.
- **No `origin` remote** — restack always fetches from `origin`.

## Quickstart

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

## Conflict recovery

If cherry-pick conflicts during a restack:

```sh
# Resolve conflicts in your editor, then:
git add .
git cherry-pick --continue

# Or abort entirely and restore your previous state:
git cherry-pick --abort
git reset --hard backup/<branch>-<epoch>
```

## Reference

```
git restack [base]            Replay the single commit not in base (default: main)
git restack --dry-run [base]  Simulate without touching your branch or local base
git restack --help            Show help
git restack --version         Show version
```

**Requirements:** Bash 3.2+, Git 2.x

**License:** Apache 2.0
