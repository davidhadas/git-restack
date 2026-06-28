#!/usr/bin/env bats

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/git-restack"

# Create a self-contained git environment:
#   - a bare "origin" repo
#   - a local clone with main + one commit on feature
# Sets REPO (local clone) and ORIGIN (bare remote).
setup_repo() {
  ORIGIN="$(mktemp -d)"
  REPO="$(mktemp -d)"

  git init --bare "$ORIGIN" -q
  git -C "$ORIGIN" symbolic-ref HEAD refs/heads/main

  git clone "$ORIGIN" "$REPO" -q
  git -C "$REPO" config user.email "test@test.com"
  git -C "$REPO" config user.name "Test"

  # Initial commit on main
  echo "base" > "$REPO/base.txt"
  git -C "$REPO" add base.txt
  git -C "$REPO" commit -m "init" -q
  git -C "$REPO" push origin main -q
}

# Create feature branch with one commit on top of main
setup_feature() {
  git -C "$REPO" checkout -b feature -q
  echo "feature" > "$REPO/feature.txt"
  git -C "$REPO" add feature.txt
  git -C "$REPO" commit -m "feat: add feature" -q
}

# Advance main on the remote (simulates another contributor merging to main)
advance_main() {
  local msg="${1:-advance main}"
  git -C "$REPO" checkout main -q
  echo "$msg" >> "$REPO/base.txt"
  git -C "$REPO" commit -am "$msg" -q
  git -C "$REPO" push origin main -q
  git -C "$REPO" checkout feature -q
}

run_restack() {
  run bash "$SCRIPT" "$@"
}

setup() {
  setup_repo
  setup_feature
}

teardown() {
  rm -rf "$REPO" "$ORIGIN"
}

# ---------------------------------------------------------------------------
# --help / --version
# ---------------------------------------------------------------------------

@test "--help prints usage and exits 0" {
  cd "$REPO"
  run_restack --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "-h prints usage and exits 0" {
  cd "$REPO"
  run_restack -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "--version prints version and exits 0" {
  cd "$REPO"
  run_restack --version
  [ "$status" -eq 0 ]
  [[ "$output" == *"git-restack"* ]]
}

@test "-V prints version and exits 0" {
  cd "$REPO"
  run_restack -V
  [ "$status" -eq 0 ]
  [[ "$output" == *"git-restack"* ]]
}

# ---------------------------------------------------------------------------
# Safety checks
# ---------------------------------------------------------------------------

@test "fails on detached HEAD" {
  cd "$REPO"
  local sha
  sha=$(git rev-parse HEAD)
  git checkout "$sha" -q 2>/dev/null
  run_restack
  [ "$status" -eq 1 ]
  [[ "$output" == *"detached HEAD"* ]]
}

@test "fails when on base branch" {
  git -C "$REPO" checkout main -q
  cd "$REPO"
  run_restack
  [ "$status" -eq 1 ]
  [[ "$output" == *"Switch to your feature branch"* ]]
}

@test "fails with uncommitted changes" {
  cd "$REPO"
  echo "dirty" >> "$REPO/feature.txt"
  run_restack
  [ "$status" -eq 1 ]
  [[ "$output" == *"uncommitted or staged changes"* ]]
}

@test "fails with staged changes" {
  cd "$REPO"
  echo "staged" >> "$REPO/feature.txt"
  git -C "$REPO" add feature.txt
  run_restack
  [ "$status" -eq 1 ]
  [[ "$output" == *"uncommitted or staged changes"* ]]
}

@test "fails with no origin remote" {
  cd "$REPO"
  git -C "$REPO" remote remove origin
  run_restack
  [ "$status" -eq 1 ]
  [[ "$output" == *"No 'origin' remote"* ]]
}

@test "fails when cherry-pick is in progress" {
  cd "$REPO"
  GIT_DIR=$(git -C "$REPO" rev-parse --git-dir)
  touch "$GIT_DIR/CHERRY_PICK_HEAD"
  run_restack
  [ "$status" -eq 1 ]
  [[ "$output" == *"unfinished Git operation"* ]]
  rm "$GIT_DIR/CHERRY_PICK_HEAD"
}

@test "fails when merge is in progress" {
  cd "$REPO"
  GIT_DIR=$(git -C "$REPO" rev-parse --git-dir)
  touch "$GIT_DIR/MERGE_HEAD"
  run_restack
  [ "$status" -eq 1 ]
  [[ "$output" == *"unfinished Git operation"* ]]
  rm "$GIT_DIR/MERGE_HEAD"
}

@test "fails when rebase is in progress" {
  cd "$REPO"
  GIT_DIR=$(git -C "$REPO" rev-parse --git-dir)
  mkdir -p "$GIT_DIR/rebase-merge"
  run_restack
  [ "$status" -eq 1 ]
  [[ "$output" == *"unfinished Git operation"* ]]
  rmdir "$GIT_DIR/rebase-merge"
}

@test "fails with zero commits to replay (branch already up to date)" {
  # Push feature, then restack once so the commit is on origin/main too
  advance_main
  cd "$REPO"
  run bash "$SCRIPT"   # first restack moves feature onto new origin/main
  # Now push feature so origin knows about it; reset feature to origin/main
  # so there are zero unique commits left
  git -C "$REPO" reset --hard origin/main -q
  run_restack
  [ "$status" -eq 0 ]
  [[ "$output" == *"already up to date"* ]]
}

@test "fails with more than one commit" {
  cd "$REPO"
  echo "second" > "$REPO/second.txt"
  git -C "$REPO" add second.txt
  git -C "$REPO" commit -m "feat: second commit" -q
  run_restack
  [ "$status" -eq 1 ]
  [[ "$output" == *"2 commits to replay"* ]]
  [[ "$output" == *"squash"* ]]
  [[ "$output" == *"single-commit PR workflow"* ]]
}

# ---------------------------------------------------------------------------
# Real run — happy path
# ---------------------------------------------------------------------------

@test "succeeds: replays single commit on top of advanced main" {
  advance_main
  cd "$REPO"
  run_restack
  [ "$status" -eq 0 ]
  [[ "$output" == *"Done!"* ]]
}

@test "real run: branch tip is on top of origin/main after restack" {
  advance_main
  cd "$REPO"
  run_restack
  local parent
  parent=$(git -C "$REPO" log --pretty=%P -1 feature)
  local origin_main
  origin_main=$(git -C "$REPO" rev-parse origin/main)
  [ "$parent" = "$origin_main" ]
}

@test "real run: feature file still present after restack" {
  advance_main
  cd "$REPO"
  run_restack
  [ -f "$REPO/feature.txt" ]
}

@test "real run: backup ref is created" {
  advance_main
  cd "$REPO"
  run_restack
  local backup
  backup=$(git -C "$REPO" branch --list "backup/feature-*")
  [ -n "$backup" ]
}

@test "real run: branch not on origin — suggests plain push" {
  advance_main
  cd "$REPO"
  run_restack
  [[ "$output" == *"git push -u origin feature"* ]]
}

@test "real run: branch already on origin — suggests force-with-lease" {
  git -C "$REPO" push origin feature -q
  advance_main
  cd "$REPO"
  run_restack
  [[ "$output" == *"--force-with-lease"* ]]
}

@test "real run: custom base branch override works" {
  # Create a 'develop' branch on origin as alternate base
  git -C "$REPO" checkout main -q
  git -C "$REPO" checkout -b develop -q
  echo "develop base" > "$REPO/develop.txt"
  git -C "$REPO" add develop.txt
  git -C "$REPO" commit -m "develop init" -q
  git -C "$REPO" push origin develop -q

  # Feature branch from develop
  git -C "$REPO" checkout -b feature2 -q
  echo "f2" > "$REPO/f2.txt"
  git -C "$REPO" add f2.txt
  git -C "$REPO" commit -m "feat: f2" -q

  # Advance develop on remote
  git -C "$REPO" checkout develop -q
  echo "more" >> "$REPO/develop.txt"
  git -C "$REPO" commit -am "advance develop" -q
  git -C "$REPO" push origin develop -q
  git -C "$REPO" checkout feature2 -q

  cd "$REPO"
  run bash "$SCRIPT" develop
  [ "$status" -eq 0 ]
  [[ "$output" == *"Done!"* ]]
}

# ---------------------------------------------------------------------------
# Conflict handling
# ---------------------------------------------------------------------------

@test "real run: exits 1 and prints resolution hints on conflict" {
  # Advance main modifying the same file as feature
  git -C "$REPO" checkout main -q
  echo "conflict" > "$REPO/feature.txt"
  git -C "$REPO" add feature.txt
  git -C "$REPO" commit -m "conflict on main" -q
  git -C "$REPO" push origin main -q
  git -C "$REPO" checkout feature -q

  cd "$REPO"
  run_restack
  [ "$status" -eq 1 ]
  [[ "$output" == *"CONFLICT DETECTED"* ]]
  [[ "$output" == *"cherry-pick --abort"* ]]
  [[ "$output" == *"git reset --hard"* ]]
}

@test "real run: backup ref present even after conflict" {
  git -C "$REPO" checkout main -q
  echo "conflict" > "$REPO/feature.txt"
  git -C "$REPO" add feature.txt
  git -C "$REPO" commit -m "conflict on main" -q
  git -C "$REPO" push origin main -q
  git -C "$REPO" checkout feature -q

  cd "$REPO"
  run_restack
  local backup
  backup=$(git -C "$REPO" branch --list "backup/feature-*")
  [ -n "$backup" ]
}

# ---------------------------------------------------------------------------
# --continue
# ---------------------------------------------------------------------------

@test "--continue fails with no cherry-pick in progress" {
  cd "$REPO"
  run bash "$SCRIPT" --continue
  [ "$status" -eq 1 ]
  [[ "$output" == *"No cherry-pick in progress"* ]]
}

@test "--continue fails with unstaged changes" {
  # Set up a conflict
  git -C "$REPO" checkout main -q
  echo "conflict" > "$REPO/feature.txt"
  git -C "$REPO" add feature.txt
  git -C "$REPO" commit -m "conflict on main" -q
  git -C "$REPO" push origin main -q
  git -C "$REPO" checkout feature -q

  cd "$REPO"
  run bash "$SCRIPT"   # triggers conflict, leaves CHERRY_PICK_HEAD
  # leave conflict unresolved — unstaged changes present
  run bash "$SCRIPT" --continue
  [ "$status" -eq 1 ]
  [[ "$output" == *"unstaged changes"* ]]
}

@test "--continue completes restack after conflict resolved" {
  git -C "$REPO" checkout main -q
  echo "conflict" > "$REPO/feature.txt"
  git -C "$REPO" add feature.txt
  git -C "$REPO" commit -m "conflict on main" -q
  git -C "$REPO" push origin main -q
  git -C "$REPO" checkout feature -q

  cd "$REPO"
  run bash "$SCRIPT"   # triggers conflict
  # resolve conflict manually
  echo "resolved" > "$REPO/feature.txt"
  git -C "$REPO" add feature.txt
  run bash "$SCRIPT" --continue
  [ "$status" -eq 0 ]
  [[ "$output" == *"Restack complete"* ]]
}

@test "conflict message instructs user to run --continue" {
  git -C "$REPO" checkout main -q
  echo "conflict" > "$REPO/feature.txt"
  git -C "$REPO" add feature.txt
  git -C "$REPO" commit -m "conflict on main" -q
  git -C "$REPO" push origin main -q
  git -C "$REPO" checkout feature -q

  cd "$REPO"
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"git restack --continue"* ]]
}

# ---------------------------------------------------------------------------
# --auto-cleanup
# ---------------------------------------------------------------------------

@test "auto-cleanup: backup ref deleted after successful restack" {
  advance_main
  cd "$REPO"
  run bash "$SCRIPT" --auto-cleanup
  [ "$status" -eq 0 ]
  local backup
  backup=$(git -C "$REPO" branch --list "backup/feature-*")
  [ -z "$backup" ]
}

@test "auto-cleanup: backup ref preserved on conflict" {
  git -C "$REPO" checkout main -q
  echo "conflict" > "$REPO/feature.txt"
  git -C "$REPO" add feature.txt
  git -C "$REPO" commit -m "conflict on main" -q
  git -C "$REPO" push origin main -q
  git -C "$REPO" checkout feature -q

  cd "$REPO"
  run bash "$SCRIPT" --auto-cleanup
  [ "$status" -eq 1 ]
  local backup
  backup=$(git -C "$REPO" branch --list "backup/feature-*")
  [ -n "$backup" ]
}

@test "auto-cleanup: prints deletion confirmation" {
  advance_main
  cd "$REPO"
  run bash "$SCRIPT" --auto-cleanup
  [ "$status" -eq 0 ]
  [[ "$output" == *"Backup ref deleted"* ]]
}

@test "auto-cleanup: works with custom base branch" {
  git -C "$REPO" checkout main -q
  git -C "$REPO" checkout -b develop -q
  echo "develop base" > "$REPO/develop.txt"
  git -C "$REPO" add develop.txt
  git -C "$REPO" commit -m "develop init" -q
  git -C "$REPO" push origin develop -q

  git -C "$REPO" checkout -b feature2 -q
  echo "f2" > "$REPO/f2.txt"
  git -C "$REPO" add f2.txt
  git -C "$REPO" commit -m "feat: f2" -q

  git -C "$REPO" checkout develop -q
  echo "more" >> "$REPO/develop.txt"
  git -C "$REPO" commit -am "advance develop" -q
  git -C "$REPO" push origin develop -q
  git -C "$REPO" checkout feature2 -q

  cd "$REPO"
  run bash "$SCRIPT" --auto-cleanup develop
  [ "$status" -eq 0 ]
  local backup
  backup=$(git -C "$REPO" branch --list "backup/feature2-*")
  [ -z "$backup" ]
}

# ---------------------------------------------------------------------------
# Dry run
# ---------------------------------------------------------------------------

@test "dry run: exits 0 and reports SUCCESS on clean replay" {
  advance_main
  cd "$REPO"
  run_restack --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"SUCCESS"* ]]
}

@test "dry run: exits 0 and reports CONFLICT when replay would conflict" {
  git -C "$REPO" checkout main -q
  echo "conflict" > "$REPO/feature.txt"
  git -C "$REPO" add feature.txt
  git -C "$REPO" commit -m "conflict on main" -q
  git -C "$REPO" push origin main -q
  git -C "$REPO" checkout feature -q

  cd "$REPO"
  run_restack --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"CONFLICT"* ]]
}

@test "dry run: leaves feature branch unchanged" {
  advance_main
  local before
  before=$(git -C "$REPO" rev-parse feature)
  cd "$REPO"
  run_restack --dry-run
  local after
  after=$(git -C "$REPO" rev-parse feature)
  [ "$before" = "$after" ]
}

@test "dry run: leaves current branch as feature" {
  advance_main
  cd "$REPO"
  run_restack --dry-run
  local current
  current=$(git -C "$REPO" rev-parse --abbrev-ref HEAD)
  [ "$current" = "feature" ]
}

@test "dry run: no temp branch left behind after clean replay" {
  advance_main
  cd "$REPO"
  run_restack --dry-run
  local temp
  temp=$(git -C "$REPO" branch --list "restack-dryrun-*")
  [ -z "$temp" ]
}

@test "dry run: no temp branch left behind after conflict" {
  git -C "$REPO" checkout main -q
  echo "conflict" > "$REPO/feature.txt"
  git -C "$REPO" add feature.txt
  git -C "$REPO" commit -m "conflict on main" -q
  git -C "$REPO" push origin main -q
  git -C "$REPO" checkout feature -q

  cd "$REPO"
  run_restack --dry-run
  local temp
  temp=$(git -C "$REPO" branch --list "restack-dryrun-*")
  [ -z "$temp" ]
}

@test "dry run: no backup ref created" {
  advance_main
  cd "$REPO"
  run_restack --dry-run
  local backup
  backup=$(git -C "$REPO" branch --list "backup/feature-*")
  [ -z "$backup" ]
}

@test "dry run: accepts custom base branch" {
  git -C "$REPO" checkout main -q
  git -C "$REPO" checkout -b develop -q
  echo "develop base" > "$REPO/develop.txt"
  git -C "$REPO" add develop.txt
  git -C "$REPO" commit -m "develop init" -q
  git -C "$REPO" push origin develop -q

  git -C "$REPO" checkout -b feature2 -q
  echo "f2" > "$REPO/f2.txt"
  git -C "$REPO" add f2.txt
  git -C "$REPO" commit -m "feat: f2" -q

  git -C "$REPO" checkout develop -q
  echo "more" >> "$REPO/develop.txt"
  git -C "$REPO" commit -am "advance develop" -q
  git -C "$REPO" push origin develop -q
  git -C "$REPO" checkout feature2 -q

  cd "$REPO"
  run bash "$SCRIPT" --dry-run develop
  [ "$status" -eq 0 ]
  [[ "$output" == *"SUCCESS"* ]]
}
