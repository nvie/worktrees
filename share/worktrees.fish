# worktrees — fish-side companion. Sourced from ~/.config/fish/conf.d/.
#
# Drives behavior when a group's .envrc is loaded:
#   $WORKTREE_GROUP     set → in a group
#   $WORKTREE_ROOT      group dir
#   $WORKTREE_COLOR_BG  hex (#RRGGBB) for OSC 11 terminal tint


# ─── wt_cd: group-aware cd helper ──────────────────────────────────────────
#
# Use in your cd* aliases like:
#   function cdf;  wt_cd 'liveblocks-backend/apps/cloudflare'; end
#   function cdbb; wt_cd 'liveblocks-backend';                  end
#
# When $WORKTREE_GROUP is set, routes into the group; otherwise into source.

function wt_cd --argument-names rel
    if set -q WORKTREE_GROUP
        cd "$WORKTREE_ROOT/$rel"
    else
        cd "$HOME/Projects/liveblocks/$rel"
    end
end


# ─── Terminal background tint reset via OSC 111 ────────────────────────────
#
# Resets the terminal background when WORKTREE_GROUP becomes undefined.
# Group entry's OSC 11 is emitted from the .envrc itself — fish events would
# race with direnv's randomized variable emit order.

function __wt_on_group --on-variable WORKTREE_GROUP
    set -q WORKTREE_GROUP; or printf '\e]111\a' >/dev/tty
end


# ─── `worktrees` wrapper: cd into the group after init/switch ──────────────
#
# `cd` is a shell-side concept, so switching lives here. We resolve the target
# path via the script's hidden `--print-path` flag (same path code the script
# would use for itself), then `cd` into it:
#
#   worktrees switch <name>   →  cd into that group         (alias: go)
#   worktrees switch          →  cd into the most recent group
#   worktrees init <name>     →  run the script, then cd into the new group
#   worktrees ls / list       →  interactive picker on a TTY; ⏎ cd's into the
#                                chosen group, create's path is cd'd into too
#
# Everything else (rm / prune / -h / …) passes through.

function worktrees
    set -l first $argv[1]

    switch "$first"
        case switch go
            set -l target_path (command worktrees switch --print-path $argv[2..-1])
            or return $status
            cd "$target_path"
            return 0

        case ls list
            set -l rest $argv[2..-1]

            # `wl <name>` jumps straight to that group, like the old `wg <name>`.
            if test (count $rest) -ge 1; and not string match -q -- '-*' $rest[1]
                set -l target_path (command worktrees switch --print-path $rest[1])
                or return $status
                cd "$target_path"
                return 0
            end

            # Bare `ls`/`list` on a real terminal opens the interactive picker.
            # Piped/redirected (or with flags) it falls through to the plain
            # name-dumping behavior so scripts keep working. The picker draws to
            # /dev/tty and prints just the chosen group's path on stdout, which
            # we cd into (⏎ on a group, or after creating one).
            if test (count $rest) -eq 0; and isatty stdout
                set -l target_path (command worktrees ls --interactive)
                or return $status
                test -n "$target_path"; and cd "$target_path"
                return 0
            end
            command worktrees $argv
            return $status

        case init create
            command worktrees $argv
            or return $status
            for arg in $argv[2..-1]
                if not string match -q -- '--*' $arg
                    set -l target_path (command worktrees switch --print-path $arg 2>/dev/null)
                    test -n "$target_path"; and cd "$target_path"
                    return 0
                end
            end
            return 0

        case '*'
            command worktrees $argv
            return $status
    end
end
