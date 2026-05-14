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
  worktrees <name> [<base-branch>]   Create a worktree group
  worktrees ls                       List existing groups
  worktrees rm <name> [--force]      Remove a group
  worktrees prune                    Sync source repos after manual cleanup
  worktrees path <name>              Print a group's path

Environment:
  WORKTREE_ROOT   (default: $HOME/Desktop/worktrees)
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
2. Runs `git fetch` in each source checkout.
3. Verifies `<base-branch>` exists in every repo. If it doesn't exist in some,
   prints the list and aborts — pick a different base, or create the missing
   branches in those source repos first.
4. Classifies every untracked or ignored file across the source repos against
   the `ALLOW` / `IGNORE` lists (see [Per-repo bootstrap](#per-repo-bootstrap)).
   Aborts upfront with a clear list if anything is unclassified — before
   touching any worktree.
5. For each repo that doesn't already have its worktree:
   - If branch `<name>` already exists locally, **reuses it**. Otherwise
     creates it from `<base-branch>`. Never errors on a pre-existing branch.
   - Runs `git worktree add --no-checkout` so smudge filters don't fire yet.
   - Symlinks `<source>/.git/git-crypt/` into the worktree's git dir if the
     source has it, so the worktree shares the source's git-crypt key.
   - Copies every `ALLOW`-listed file from the source into the worktree,
     preserving relative paths (this includes `.claude/settings.local.json`
     when source has one).
   - Runs `git checkout HEAD -- .` to materialize the working tree. Smudge
     filters run now; git-crypt decrypts cleanly.
   - Writes or mutates `.claude/settings.local.json` so its
     `permissions.additionalDirectories` points at the four sibling worktrees
     in this group (see [Claude config](#claude-config)).
   - Appends `.claude/settings.local.json` to the worktree's
     `info/exclude` to keep it out of `git status`.
6. Writes the group's `.envrc` and `CLAUDE.md`.
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
export WORKTREE_GROUP="feature-xyz"
export WORKTREE_ROOT="$PWD"
export WORKTREE_COLOR_FG="208"        # ANSI index, hashed from name
export WORKTREE_COLOR_BG="#1a0d2e"    # hex, hashed from name

# Subdir patterns hardcoded in the script (mirrors your global CDPATH).
path_add CDPATH "$PWD/liveblocks/packages"
path_add CDPATH "$PWD/liveblocks/tools"
path_add CDPATH "$PWD/liveblocks/schema-lang"
path_add CDPATH "$PWD/liveblocks-backend/apps"
path_add CDPATH "$PWD/liveblocks-backend/shared"
path_add CDPATH "$PWD/liveblocks-backend/tools"
path_add CDPATH "$PWD/liveblocks"
path_add CDPATH "$PWD/liveblocks-backend"
path_add CDPATH "$PWD/admin"
path_add CDPATH "$PWD/liveblocks.io"
path_add CDPATH "$PWD/zenrouter"
```

The CDPATH list mirrors your global one (the one in `config.fish`) so
`cd cloudflare` from inside the group resolves to
`$WORKTREE_ROOT/liveblocks-backend/apps/cloudflare` instead of falling
through to the source checkout. The list lives at the top of the script
alongside `REPOS` and the `ALLOW`/`IGNORE` patterns — same hardcoded-for-
Liveblocks spirit, same place to edit when something is added.

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

2. **Per-worktree `.claude/settings.local.json`** at
   `<group>/<repo>/.claude/settings.local.json`. Two cases:

   - **Source has `.claude/settings.local.json`** — it travels via the
     `ALLOW` copy step (your `permissions.allow` lists are preserved). After
     copy, the tool uses `jq` to **replace** `permissions.additionalDirectories`
     with the four sibling-worktree paths in this group.
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

### `ALLOW` / `IGNORE` classification

Every untracked or ignored path that `git status --ignored` reports in a
source repo must classify as one of:

- **`ALLOW`** — copied into the worktree at the same relative path
- **`IGNORE`** — left in the source, not copied

Anything matching neither aborts the create with a clear list of the
unclassified paths. The fix is to add a glob to the appropriate list in the
script and re-run. The lists are deliberately small and explicit so that the
first time you encounter something unfamiliar — a new ignored build dir, an
unfamiliar env file — you make a one-line decision about whether it
travels.

Initial lists (hardcoded in the script):

```
ALLOW  → .env, .env.*, .env.local, settings.local.json
IGNORE → node_modules, .next, dist, build, .turbo, .cache, coverage, *.log, …
```

`settings.local.json` lands in ALLOW so a source repo's existing
`.claude/settings.local.json` (your Bash allow lists, WebFetch domains, etc.)
travels into the worktree. After the copy, the Claude-config step mutates
its `permissions.additionalDirectories` to point at sibling worktrees — see
[Claude config](#claude-config) below.

The source of truth is `git status --ignored --porcelain` in each repo,
which yields lines like:

```
?? .env.local
!! node_modules/
!! examples/foo/build/output.log
```

Each path is normalized (strip the `?? ` / `!! ` prefix, strip any trailing
`/`, take the basename) and matched against the lists with a bash `case`
block — so the globs are shell-glob, not regex. Matching is against the
**basename only**, so a single `node_modules` entry catches both
`<repo>/node_modules` and `<repo>/examples/foo/node_modules`, and `*.log`
matches any file ending in `.log` regardless of where it sits in the tree.

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

It defines three helpers:

- **`wt_cd <rel-path>`** — routes `cd` to `$WORKTREE_ROOT/<rel>` when in a
  group, `$HOME/Projects/liveblocks/<rel>` otherwise.
- **`wt_prompt_segment`** — emits `[feature-xyz]` colored by
  `$WORKTREE_COLOR_FG` when in a group; outputs nothing otherwise. You call
  it from your `fish_prompt`.
- **`--on-variable WORKTREE_GROUP` handler** — emits OSC 11 with
  `$WORKTREE_COLOR_BG` to tint the terminal background when the group sets,
  emits the OSC 11 reset (`\e]111\a`) when it unsets.

### Refactor your `cd*` aliases

Rewrite each from a hardcoded path to a `wt_cd` call:

```fish
# Before
alias cdf 'cd ~/Projects/liveblocks/liveblocks-backend/apps/cloudflare'
alias cdrc 'cd ~/Projects/liveblocks/liveblocks/packages/liveblocks-react-ui'

# After
function cdf;  wt_cd 'liveblocks-backend/apps/cloudflare'; end
function cdrc; wt_cd 'liveblocks/packages/liveblocks-react-ui'; end
```

~30 mechanical edits in one sitting. The rel-path is now the only varying
piece — no more typing `~/Projects/liveblocks/` everywhere.

### Add the chip to your prompt

Drop a call to `wt_prompt_segment` into your `fish_prompt`, wherever you want
the `[group-name]` chip to appear (typically right after the cwd):

```fish
function fish_prompt
  # … cwd, git status, etc. …
  wt_prompt_segment
  # … rest of prompt …
end
```

## Visual markers

What you get once the fish snippet is sourced and the group's `.envrc` is
loaded:

- **Prompt chip** — `[feature-xyz]` rendered in the group's color (stable
  across sessions, hashed from the name) by `wt_prompt_segment`.
- **Terminal background** — a subtle dark tint via OSC 11
  (`\e]11;#RRGGBB\a`), reset on direnv unload.

Each group's color is picked from a palette via a hash of its name, so
`feature-xyz` always looks the same. The OSC 11 tint is still subject to a
Ghostty smoke test that hasn't happened yet — if it misbehaves, the snippet's
`--on-variable` handler is the one place to disable it without losing the
chip.

## Other commands

```sh
worktrees            # interactive picker (planned, see Roadmap)
worktrees ls         # list existing groups
worktrees rm <name>  # remove a group
worktrees prune      # `git worktree prune` in every source repo
worktrees path <name> # print the group's path (for `cd (worktrees path foo)`)
```

`rm` first checks **all** worktrees in the group for uncommitted changes and
bails out before touching anything if any are dirty. Only once the whole
group is verified clean does it run `git worktree remove` per repo and
delete the group directory. Pass `--force` to skip the dirty check (and
force-remove the worktree dir if `worktree remove` itself refuses — losing
the worktree is recoverable; we can always re-create it). At the end, `rm`
runs `git worktree prune` in each source repo as a safety net.

**`rm` never deletes branches.** That's deliberate — a branch may carry
unpushed commits that are genuinely worth keeping even when the worktree is
gone, and losing real work to a bash one-liner is the kind of regret we'd
rather avoid. Not even `--force` deletes branches. If you want a branch
gone too, run `git branch -d <name>` (safe — refuses if unmerged) or
`git branch -D <name>` (forces) in each source repo by hand. Or: just
re-run `worktrees <name>` later — it'll reuse the existing branch.

A `--force-delete-branch` flag may land later. For now, keeping branches is
the conservative default.

`prune` is the escape hatch for "I deleted a group's directory by hand and
now my source repos think the worktrees still exist." It runs `git worktree prune` in every repo listed in `REPOS`. Like `rm`, it leaves branches alone.

## Configuration

Defaults live at the top of the script. Likely things to tweak:

- `WORKTREE_ROOT` — default `~/Desktop/worktrees`
- `SOURCE_ROOT` — default `~/Projects/liveblocks`
- `REPOS` — the list of repo dir names to include
- `DEFAULT_BASE` — default `origin/main`
- `PALETTE` — `(fg-ansi-index, bg-hex)` pairs; a hash of the group name picks
  one and is exported as `$WORKTREE_COLOR_FG` / `$WORKTREE_COLOR_BG` in the
  group's `.envrc`. The fish snippet renders the chip and the OSC 11 tint
  from those.

## Requirements

The initial version assumes a fixed stack — no portability layer, no
conditionals. If you don't have one of these, the tool won't work; that's
fine for v1.

- [Fish shell](https://fishshell.com/)
- [Ghostty](https://ghostty.org/)
- [direnv](https://direnv.net/) (hooked into Fish)
- [git-toolbelt](https://github.com/nvie/git-toolbelt)
- [`jq`](https://jqlang.org/) — for in-place mutation of `.claude/settings.local.json`
- All five source repos cloned under `SOURCE_ROOT`

## Roadmap

### Soon

- **Interactive TUI.** Running `liveblocks-worktree` with no args opens a
  picker listing existing groups. `↑/↓` to navigate, `enter` to `cd`, `x` to
  delete (with confirmation), `n` to create a new one.

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
