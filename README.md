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
    ├── .envrc
    ├── liveblocks/
    ├── liveblocks-backend/
    ├── admin/
    ├── liveblocks.io/
    └── zenrouter/
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
   prints the list and asks whether to skip those repos or abort.
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
     preserving relative paths.
   - Runs `git checkout HEAD -- .` to materialize the working tree. Smudge
     filters run now; git-crypt decrypts cleanly.
6. Writes the group's `.envrc`.
7. Prints a `cd` hint.

`worktrees <name>` is **idempotent**. Re-running it on an existing group is
safe: repos that already have their worktree are skipped, repos that don't
get set up now. Use it freely to create, switch back to, or repair a group
after a partial / interrupted create.

### The `.envrc`

The generated `.envrc` does three things when you `cd` into the group dir (via
direnv):

- **Rewrites the `cd*` aliases** (`cdf`, `cdbb`, `cdr`, …) so they jump to the
  group's copy of each repo instead of `~/Projects/liveblocks/...`.
- **Replaces `CDPATH`** with the group's equivalent entries — `cd cloudflare`
  resolves to `<group>/liveblocks-backend/apps/cloudflare`, not the source
  checkout.
- **Marks the shell** so the prompt and (optionally) the Ghostty background
  reflect the active group.

The aliases and CDPATH are scoped to the direnv session; leaving the directory
restores your normal config.

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
ALLOW  → .env, .env.*, .env.local
IGNORE → node_modules, .next, dist, build, .turbo, .cache, coverage, *.log, …
```

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

## Visual markers

Each group gets a stable color derived from its name (hash → palette index),
so `feature-xyz` always looks the same across sessions.

- **Prompt segment**: a colored `[feature-xyz]` chip prepended to the Fish
  prompt.
- **Ghostty background**: a subtle dark tint (dark purple / blue / green /
  brown / …), close enough to black to stay readable but distinct at a glance.
  Emitted via the OSC 11 escape sequence (`\e]11;#RRGGBB\a`).

Background tinting is opt-in and easy to disable per-group or globally — see
_Configuration_ below. It's experimental; if it gets annoying, kill it
without losing the prompt marker.

## Other commands

```sh
worktrees            # interactive picker (planned, see Roadmap)
worktrees ls         # list existing groups
worktrees rm <name>  # remove a group (asks for confirmation)
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
- `TINT_BG` — `true` / `false` (emits OSC 11 to tint the terminal background)
- `PALETTE` — the set of `(prompt-color, bg-color)` pairs to cycle through

## Requirements

The initial version assumes a fixed stack — no portability layer, no
conditionals. If you don't have one of these, the tool won't work; that's
fine for v1.

- [Fish shell](https://fishshell.com/)
- [Ghostty](https://ghostty.org/)
- [direnv](https://direnv.net/) (hooked into Fish)
- [git-toolbelt](https://github.com/nvie/git-toolbelt)
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
