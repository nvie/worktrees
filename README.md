# worktrees

Spin up a coordinated set of Git worktrees across every Liveblocks repo with
one command. Each worktree group is a self-contained sandbox: one branch, one
directory tree, one envrc, one colored prompt.

The idea: trying out a feature, a bug repro, or a quick `tmp/` experiment
shouldn't mean clobbering your primary checkouts or juggling stashes. Create a
group, work in it, throw it away.

> Initially this is hardcoded to the Liveblocks repo set. Once the shape feels
> right, it'll be generalized to arbitrary repo combinations (see Roadmap).

## Source checkouts

The "real" checkouts (the ones holding the `.git` dirs) live under
`~/Projects/liveblocks/`:

- `liveblocks`
- `liveblocks-backend`
- `admin`
- `liveblocks.io`
- `zenrouter`

`worktrees` never touches the files in those directories — it only creates
additional worktrees pointing at the same `.git`s.

## Worktree groups

A worktree group is a sibling set of worktrees, one per source repo, all on
the same branch, all under one parent directory:

```
~/Desktop/worktrees/
└── feature-xyz/
    ├── .envrc                                   ← group env exports + CDPATH
    ├── CLAUDE.md                                ← group context for Claude
    ├── liveblocks/
    │   └── .claude/settings.local.json          ← additionalDirectories: 4 siblings
    ├── liveblocks-backend/
    │   └── .claude/settings.local.json          ← (same shape)
    ├── admin/
    │   └── .claude/settings.local.json
    ├── liveblocks.io/
    │   └── .claude/settings.local.json
    └── zenrouter/
        └── .claude/settings.local.json
```

Desktop is the default home for groups so they're visible, easy to clean up,
and survive reboots. (`~/Desktop/.worktrees` is under consideration if the
visible dir gets annoying.)

## Usage

```
$ worktrees --help
Coordinated multi-repo git worktrees

Usage:
  worktrees <name> [<base>] [--fetch]                          Create a worktree group
  worktrees ls                                                 List existing groups
  worktrees rm <name> [--force-rm-worktree] [--force-rm-branch]
                                                               Remove a group: worktree dirs + branches
  worktrees prune [--force-rm-branch]                          Finish removal of groups whose dirs are gone
  worktrees path <name>                                        Print a group's path

Environment:
  WORKTREES_DIR   (default: $HOME/Desktop/worktrees)
  SOURCE_ROOT     (default: $HOME/Projects/liveblocks)
  DEFAULT_BASE    (default: origin/main)
```

> The `Environment:` section renders dimmed in the terminal.

### Creating a group

```sh
worktrees <name> [<base-branch>]
```

- `<name>` — name of the group and the branch to create
- `<base-branch>` — branch to fork from (default: `origin/main`)

Example:

```sh
worktrees feature-xyz
worktrees fix-cf-cold-start origin/release-1.5
worktrees tmp
```

### What it does

1. Creates `~/Desktop/worktrees/<name>/` if it doesn't exist.
2. Runs `git fetch` in each source checkout — **only when `--fetch` is
   passed**. Off by default (the slow step; you usually already fetched
   recently). Pass `--fetch` when you want to make sure `<base-branch>` is
   up to date before branching.
3. Verifies `<base-branch>` exists in every repo. If it doesn't exist in some,
   prints the list and aborts — pick a different base, or create the missing
   branches in those source repos first.
4. Verifies that branch `<name>` isn't already checked out anywhere **outside
   this group**. If it is (e.g., currently checked out in a source repo, or
   in a worktree belonging to a different group), aborts with the conflicting
   path so you can resolve it manually. Worktrees belonging to **this** group
   are not a conflict — they're the idempotent-skip case.
5. For each repo that doesn't already have its worktree:
   - If branch `<name>` already exists locally, **reuses it**. Otherwise
     creates it from `<base-branch>`. Never errors on a pre-existing branch.
   - Runs `git worktree add --no-checkout` so smudge filters don't fire yet.
   - Symlinks `<source>/.git/git-crypt/` into the worktree's git dir if the
     source has it, so the worktree shares the source's git-crypt key.
   - Copies every untracked/ignored file that matches `COPY_PATTERNS` from
     the source into the worktree, preserving relative paths (this includes
     `.claude/settings.local.json` when source has one). Anything not
     matching is silently skipped — see [What gets copied](#what-gets-copied-copy_patterns).
   - Runs `git checkout HEAD -- .` to materialize the working tree. Smudge
     filters run now; git-crypt decrypts cleanly.
   - Writes or mutates `.claude/settings.local.json` so its
     `permissions.additionalDirectories` points at the four sibling worktrees
     in this group (see [Claude config](#claude-config)). The `jq` mutation
     runs on **every** create, so re-runs keep the list current.
   - Appends `.claude/settings.local.json` to the worktree's
     `info/exclude` to keep it out of `git status`.
6. Writes the group's `.envrc` and `CLAUDE.md` **only if they don't already
   exist**. On idempotent re-run they're left alone, so any tweaks you've
   made (custom colors, additional env vars, edited CLAUDE.md context) are
   preserved. To refresh from the current template, `rm` the file and re-run.
7. Prints a `cd` hint.

`worktrees <name>` is **idempotent for the happy path**: re-running it on a
group skips repos already set up and sets up any that aren't. Use it freely
to create, switch back to, or extend a group.

If a previous run failed mid-flow and left a **hollow worktree** (git admin
entry exists, working tree empty), recovery is a manual one-liner:

```sh
rm -rf ~/Desktop/worktrees/<name>     # or just the broken sub-repo dir
worktrees <name>                       # re-run
```

That falls into the "orphaned admin entry" case (dir gone, git still aware),
which the tool handles by silently running `git worktree prune` in each
source repo, then proceeding with the full create flow. The branch is
reused if it already exists locally (so no commits are lost). v1
intentionally doesn't try to auto-detect or auto-repair half-applied state
beyond that — `rm -rf + re-run` is the supported recovery path.

### The `.envrc`

The generated `.envrc` is purely declarative — it exports the group's
context and prepends each repo to `CDPATH`:

```sh
# Generated by `worktrees feature-xyz` on 2026-05-14. Edit freely — re-runs leave this file alone. To refresh from template: `rm .envrc && worktrees feature-xyz`.

export WORKTREE_GROUP="feature-xyz"
export WORKTREE_ROOT="$PWD"
export WORKTREE_COLOR_BG="#1a0d2e"    # OSC 11 terminal tint; hashed from name

# Group root + a few container subdirs (mirrors your global CDPATH).
path_add CDPATH "$PWD"
path_add CDPATH "$PWD/liveblocks/packages"
path_add CDPATH "$PWD/liveblocks/tools"
path_add CDPATH "$PWD/liveblocks/schema-lang"
path_add CDPATH "$PWD/liveblocks-backend/apps"
path_add CDPATH "$PWD/liveblocks-backend/shared"
path_add CDPATH "$PWD/liveblocks-backend/tools"
```

The group root (`$PWD`) covers `cd liveblocks`, `cd liveblocks-backend`,
`cd admin`, etc. without needing one entry per repo.

The CDPATH list mirrors your global one (the one in `config.fish`) so
`cd cloudflare` from inside the group resolves to
`$WORKTREE_ROOT/liveblocks-backend/apps/cloudflare` instead of falling
through to the source checkout. The list lives at the top of the script
alongside `REPOS` and `COPY_PATTERNS` — same hardcoded-for-Liveblocks
spirit, same place to edit when something is added.

Everything beyond the env exports and CDPATH — group-aware `cd*` aliases,
prompt chip, terminal tint — is driven off those env vars by the fish
snippet (see [Fish setup](#fish-setup)). direnv unloads the env when you
`cd` out of the group, so the snippet automatically flips back to source
paths, hides the chip, and resets the tint.

## Per-repo bootstrap

A fresh worktree starts from `git worktree add`, which only materializes
**tracked** files. Anything untracked or ignored stays in the source
checkout. Some of that you want in the new worktree (your local `.env`s);
some you very much don't (a 4 GB `node_modules`). `worktrees` resolves
this with one hardcoded special case and two explicit lists.

### git-crypt (hardcoded)

When a source repo has `.git/git-crypt/` — i.e., git-crypt is initialized
and unlocked — the tool symlinks that whole directory into the worktree's
git dir before checkout:

```
<wt>/.git/worktrees/<name>/git-crypt → <source>/.git/git-crypt
```

The smudge filter then finds the source's key, encrypted files decrypt on
checkout, and any `.env`-type file that is itself git-crypt-encrypted (e.g.
`admin/.env`, `liveblocks.io/.env`) comes along for free — no copy needed.

This is intentionally Liveblocks-specific bootstrap behavior. It'll be made
generic when the tool drops its Liveblocks assumptions (see Roadmap).

### Claude config (hardcoded)

The goal: from inside any worktree of a group, a Claude session has **write
access to all five sibling worktrees** — and never to the source checkouts.

What the tool writes per group:

1. **Group-level `CLAUDE.md`** at `<group>/CLAUDE.md`. Tells Claude in plain
   English that this is a worktree group, lists the siblings, and instructs
   it to interpret any `~/Projects/liveblocks/...` references in subordinate
   `CLAUDE.md` files as relative to this group. Claude walks up from the
   cwd to find this.

   Content lives in [`share/CLAUDE.md.template`](share/CLAUDE.md.template).
   The script substitutes `{{name}}` and `{{date}}` placeholders at create
   time. Edit the template to evolve the wording for all future groups; edit
   an individual group's `CLAUDE.md` to customize just that group (write-once
   policy, per [What it does](#what-it-does) step 7).

2. **Per-worktree `.claude/settings.local.json`** at
   `<group>/<repo>/.claude/settings.local.json`. JSON has no comment syntax,
   so this file gets no header note — the regeneration policy lives only in
   this README. Two cases:

   - **Source has `.claude/settings.local.json`** — it travels via the
     `COPY_PATTERNS` step (your `permissions.allow` lists are preserved).
     After copy, the tool uses `jq` to **replace**
     `permissions.additionalDirectories` with the four sibling-worktree paths
     in this group.
   - **Source doesn't have it** — the tool writes a fresh file with just the
     four sibling-worktree paths in `permissions.additionalDirectories`.

   Either way, every worktree ends up with `additionalDirectories` pointing
   at the **other four worktrees in the group**, never at `~/Projects/...`.

3. **`info/exclude` entry** in the linked worktree's git dir. After writing
   `.claude/settings.local.json` the tool appends:

   ```sh
   echo '.claude/settings.local.json' \
     >> <source>/.git/worktrees/<name>/info/exclude
   ```

   `info/exclude` in a linked worktree's git dir is **worktree-aware**: it
   hides the file from `git status` in this worktree only, without touching
   any tracked `.gitignore` and without affecting source or other worktrees.
   Belt-and-suspenders against the file getting picked up in a `git add`.

`jq` is therefore a hard dependency — see [Requirements](#requirements).

### What gets copied (`COPY_PATTERNS`)

Every untracked or ignored path that `git status --ignored` reports in each
source repo is matched by **basename glob** against `COPY_PATTERNS`.
Matches are copied into the worktree at the same relative path. Everything
else is silently skipped — `.DS_Store`, `node_modules`, `*.tsbuildinfo`,
build dirs, IDE state, the long tail.

Initial list (hardcoded at the top of the script):

```
COPY_PATTERNS → .env, .env.*, settings.local.json
```

`settings.local.json` is in here so a source repo's existing
`.claude/settings.local.json` (your Bash allow lists, WebFetch domains, etc.)
travels into the worktree. After the copy, the Claude-config step mutates
its `permissions.additionalDirectories` to point at sibling worktrees — see
[Claude config](#claude-config) below.

The source of truth is `git status --ignored --porcelain` in each repo,
which yields lines like:

```
?? .env.local           ← matches `.env.*` → copied
!! node_modules/        ← no match → skipped
?? .DS_Store            ← no match → skipped
```

Each path is normalized (strip the `?? ` / `!! ` prefix, strip any trailing
`/`, take the basename) and tested against `COPY_PATTERNS` with a bash
`case` block — so the globs are shell-glob, not regex. Matching is against
the **basename only**, so a single `.env.*` entry catches `.env.local`
anywhere in the tree.

If you discover a file type that _should_ travel and currently isn't, add
a glob to `COPY_PATTERNS` at the top of the script.

## Installation

Two one-shot symlinks. No `config.fish` edits.

```sh
ln -s /Users/nvie/Projects/worktrees/bin/worktrees \
      ~/bin/worktrees
ln -s /Users/nvie/Projects/worktrees/share/worktrees.fish \
      ~/.config/fish/conf.d/worktrees.fish
```

`~/bin` is already on your PATH, so `worktrees` becomes available globally.
Fish auto-sources every `*.fish` under `~/.config/fish/conf.d/` on shell
startup, so the snippet loads with no extra config. If you move the project
repo later, `ln -sf` the same two paths from the new location.

## Fish setup

The `share/worktrees.fish` snippet (auto-loaded via the symlink above) makes
`cd*` aliases, the prompt chip, and the terminal tint group-aware — all
driven by the env vars from the group's `.envrc`.

It defines two helpers and one wrapper:

- **`wt_cd <rel-path>`** — routes `cd` to `$WORKTREE_ROOT/<rel>` when in a
  group, `$HOME/Projects/liveblocks/<rel>` otherwise.
- **`--on-variable WORKTREE_GROUP` handler** — emits OSC 11 with
  `$WORKTREE_COLOR_BG` to tint the terminal background when the group sets,
  emits the OSC 11 reset (`\e]111\a`) when it unsets.
- **`worktrees` function wrapper** — after `worktrees tmp2` finishes
  successfully, automatically `cd`s you into the new group dir so the
  `.envrc` loads (and the tint kicks in) without a second command.
  Subcommands (`ls`, `rm`, `path`, `prune`) pass through unchanged.

### Show the group in your prompt

When inside a worktree, render `[worktree:<name>]` + the path within the
current repo. Customize `fish_prompt` in your `config.fish` along these
lines:

```fish
if set -q WORKTREE_GROUP; and string match -q "$WORKTREE_ROOT/*" "$PWD"
    set -l rel (string replace -- "$WORKTREE_ROOT/" '' "$PWD")
    set -l display
    if string match -q '*/*' "$rel"
        set display (string replace -r '^[^/]+/' '' "$rel")
    else
        set display "$rel"
    end
    set_color bryellow
    printf '[worktree:%s]' "$WORKTREE_GROUP"
    set_color normal
    set_color $fish_color_cwd
    printf ' %s' "$display"
    set_color normal
else
    # … your usual cwd + git_prompt …
end
```

## Visual markers

What you get once the fish snippet is sourced and the group's `.envrc` is
loaded:

- **Prompt** — `[worktree:<name>]` (bright yellow) followed by the path
  within the current repo, when you're inside one of the group's worktrees.
  Outside a worktree (or at the group root): your normal prompt.
- **Terminal background** — a subtle dark tint via OSC 11
  (`\e]11;#RRGGBB\a`), reset on direnv unload.

Each group's background color is picked from a palette via a hash of its
name, so `feature-xyz` always looks the same. **Don't like the color
picked?** Edit `$WORKTREE_COLOR_BG` in the group's `.envrc` — the tool
won't touch it on idempotent re-runs (see [What it does](#what-it-does)
step 6). The OSC 11 tint is still subject to a Ghostty smoke test that
hasn't happened yet — if it misbehaves, the snippet's `--on-variable`
handler is the one place to disable it without losing the prompt label.

## Other commands

```sh
worktrees ls         # interactive picker on a TTY; pipe-friendly name list otherwise
worktrees rm <name>  # remove a group
worktrees prune      # finish removal for groups whose dirs are gone
worktrees path <name> # print the group's path (for `cd (worktrees path foo)`)
```

`ls` has two faces. Through the Fish wrapper on a terminal it opens an
interactive picker (the one entry point — it subsumes the old `wg`/`wr`
aliases): `↑/↓` to move, `⏎` to `cd` into a group, `d` to remove one (with a
confirm dialog whose two checkboxes map to the `--force-rm-*` flags), or drop
onto the trailing row to create a new group (optionally picking a base branch
from every local branch across all repos, uniq'd).

When stdout isn't a terminal — `worktrees ls | fzf`, `… | xargs`, `… | head` —
it falls back to printing one group name per line, alphabetical, on
**stdout**: no path, no status, no header.

On **stderr**, `ls` emits a one-line warning per group whose worktrees
aren't all on the group's own branch. Reading `<source>/.git/worktrees/<name>/HEAD`
for each repo (one tiny file read each) tells us the current branch
without spawning git. Mismatches surface like:

```
warning: feature-xyz: 1 of 5 worktrees off-branch (liveblocks-backend → main)
```

Stdout stays clean — `worktrees ls | fzf` never sees the warning. Cases
that trigger it: someone `git checkout`ed inside the worktree and forgot to
switch back, a worktree on detached HEAD, or an orphaned admin entry. If
the warnings become noise for a long-lived `tmp`-style group, we can add
`--quiet` or a per-group marker later.

`rm` is a two-step cleanup:

1. **Remove worktree dirs** under `~/Desktop/worktrees/<name>/` and the
   corresponding `git worktree` admin entries in every source repo.
2. **Delete the branches** the worktrees were on, in every source repo.

Step 2 is **evidence-based**: a branch is only deleted if there's a
`git worktree` admin entry whose path is under `~/Desktop/worktrees/<name>/`
pointing to it. `rm` never matches branches by name alone — if you've already
manually `rm -rf`'d the group dir, the admin entries that *survived* are
what tell us which branches to clean. (Once `worktrees prune` has removed
those admin entries too, the evidence is gone for good — see below.)

Three safety gates, all checked **upfront across every repo** before
touching anything:

- **Drift** — a worktree on a branch other than `<name>` (you `git checkout`ed
  inside). Aborts, no override. Resolve manually (`git checkout <name>`
  inside the worktree, or rename and pick a different group name) and retry.
- **Dirty** — a worktree with uncommitted changes (filtering tool-created
  `?? .claude/`). Aborts. Pass `--force-rm-worktree` to remove the working
  tree anyway (uncommitted data lost).
- **Unmerged** — a branch whose tip isn't reachable from its upstream (or
  `HEAD` if no upstream). Same check `git branch -d` does, run as a
  preflight. Aborts. Pass `--force-rm-branch` to `git branch -D` (commits
  lost).

The two `--force-*` flags are orthogonal: dirty worktree + clean branch
needs only `--force-rm-worktree`; clean worktree + unmerged branch needs
only `--force-rm-branch`. There is intentionally no umbrella `--force`.

**`rm` is idempotent.** If some repos are in a healthy state and others are
already half-removed (orphan admin entries pointing at a deleted dir),
re-running picks up where the previous run left off. The relevant states
per repo:

| State | Dir | Admin | Action |
|---|---|---|---|
| `HEALTHY` | ✓ | ✓ | `git worktree remove` + `git branch -d` |
| `DIR_ONLY` | ✓ | ✗ | `rm -rf` + skip branch (no evidence) |
| `ORPHAN_ADMIN` | ✗ | ✓ | `git worktree prune` + `git branch -d` |
| `GONE` | ✗ | ✗ | nothing |

If *all* repos are `GONE` and the group dir is also gone, `rm` errors out
("already fully cleaned, or never existed"). The `DIR_ONLY` case is a
recovery edge: the dir exists but admin is gone — `rm` removes the dir but
can't safely infer a branch to delete; it prints the exact `git -C <src>
branch -d <name>` to run by hand.

`prune` is the deferred step 2: "I deleted a group's directory by hand,
now finish the cleanup". Before delegating to `git worktree prune` (which
*destroys* the path→branch admin evidence), it walks every source repo's
admin entries, finds the ones pointing at `~/Desktop/worktrees/<X>/...`
paths that no longer exist, groups them by `<X>`, and for each group whose
dir is also gone (= fully removed by hand), deletes the linked branches in
each repo. Then it prunes the admin entries.

Skips with a warning (rather than aborting like `rm`):

- **Drift in an orphan entry** — admin says the worktree was on a branch
  other than its group name. We don't second-guess what to delete.
- **Unmerged branches** — same check as `rm`. Pass `--force-rm-branch` to
  `git branch -D`.

`--force-rm-worktree` is accepted on `prune` for flag-surface consistency
with `rm`, but is a no-op there (no working tree left to be dirty).

After the per-group cleanup, `prune` finishes by running `git worktree
prune -v` in every source repo and piping git's output through unchanged.
Each repo's section is prefixed with a one-line header:

```
$ worktrees prune
=== liveblocks ===
=== liveblocks-backend ===
Removing worktrees/feature-xyz: gitdir file points to non-existent location
=== admin ===
=== liveblocks.io ===
=== zenrouter ===
```

**Order matters.** `rm -rf ~/Desktop/worktrees/foo` followed by
`worktrees prune` is a complete cleanup, branches and all. But
`rm -rf ~/Desktop/worktrees/foo` followed by a bare
`git worktree prune` (in any source repo) destroys the evidence — the
branches survive as orphans only reachable by name match, which this tool
deliberately won't do for you. If you find yourself in that state, clean
the branches by hand.

`path` prints the group's directory to stdout and exits 0. If the group
doesn't exist, it prints an error to stderr and exits 1 (so wrappers like
`cd (worktrees path foo)` fail fast with a clear message instead of `cd`ing
into a phantom path).

## Configuration

Defaults live at the top of the script. Likely things to tweak:

- `WORKTREES_DIR` — default `~/Desktop/worktrees`
- `SOURCE_ROOT` — default `~/Projects/liveblocks`
- `REPOS` — the list of repo dir names to include
- `DEFAULT_BASE` — default `origin/main`
- `PALETTE` — 8 dark background hex values for the OSC 11 terminal tint. A
  deterministic hash of the group name picks one and is exported as
  `$WORKTREE_COLOR_BG` in the group's `.envrc`. The fish snippet renders
  the tint from that. Default palette:

  ```bash
  PALETTE=(
    "#1a0d2e"   # purple
    "#0d1a2e"   # blue
    "#0d1f0d"   # green
    "#1f1a0d"   # brown
    "#2e0d1a"   # plum
    "#1f1f0d"   # olive
    "#2e1f0d"   # amber
    "#0d2e1a"   # teal
  )
  ```

  Hash: `printf '%s' "$name" | md5sum | head -c 2` → hex byte → mod 8 → index.
  Same name always picks the same entry. To override per-group, edit
  `$WORKTREE_COLOR_BG` in the group's `.envrc` (see
  [Visual markers](#visual-markers)). The prompt label `[worktree:…]` is
  hardcoded bright yellow regardless.

## Requirements

The initial version assumes a fixed stack — no portability layer, no
conditionals. If you don't have one of these, the tool won't work; that's
fine for v1.

- [Claude Code](https://docs.claude.com/en/docs/claude-code) — the tool
  generates Claude-specific config (`CLAUDE.md`, `.claude/settings.local.json`);
  no fallback or alternative agent support
- [Fish shell](https://fishshell.com/)
- [Ghostty](https://ghostty.org/)
- [direnv](https://direnv.net/) (hooked into Fish)
- [git-toolbelt](https://github.com/nvie/git-toolbelt)
- [`jq`](https://jqlang.org/) — for in-place mutation of `.claude/settings.local.json`
- All five source repos cloned under `SOURCE_ROOT`

## Roadmap

### Later

- **Generalize beyond Liveblocks.** Drop the hard-coded repo list and let any
  combination of repos be grouped — either via a config file or by selecting
  repos interactively at create time. The Liveblocks set becomes one preset
  among many.
- **Generalize beyond fixed tools.** Drop the hard assumption of Fish +
  Ghostty + direnv + git-toolbelt. Support at least Bash/Zsh prompts, generic
  OSC 11 (or none), and a pure-`git` fallback for the dirty-check. The tool's
  capabilities degrade gracefully based on what's actually installed.

## Non-goals

- Replacing or wrapping `git worktree` for general use. This is a workflow
  tool for _coordinated multi-repo_ worktrees, not a worktree manager.
- Syncing branches or commits between worktrees. Each worktree is just a
  normal checkout — push, pull, rebase as usual.
