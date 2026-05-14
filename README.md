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
4. Creates `git worktree add -b <name> <path> <base-branch>` for each repo.
5. Writes an `.envrc` at the group root (see below).
6. Prints a `cd` hint to drop into the new group.

If the group already exists, the command is a no-op (no clobbering) and just
prints the path.

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
worktrees path <name> # print the group's path (for `cd (worktrees path foo)`)
```

`rm` first checks **all** worktrees in the group for uncommitted changes and
bails out before touching anything if any are dirty. Only once the whole group
is verified clean does it run `git worktree remove` per repo and delete the
group directory. Pass `--force` to skip the dirty check.

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
