# worktrees — fish-side companion. Sourced from ~/.config/fish/conf.d/.
#
# Drives behavior when a group's .envrc is loaded:
#   $WORKTREE_GROUP     set → in a group
#   $WORKTREE_ROOT      group dir
#   $WORKTREE_COLOR_FG  ANSI 256 index
#   $WORKTREE_COLOR_BG  hex (#RRGGBB)


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


# ─── wt_prompt_segment: chip for fish_prompt ───────────────────────────────
#
# Call from your fish_prompt to render `[group-name] ` colored by the
# group's foreground color. Outputs nothing when not in a group.

function wt_prompt_segment
    set -q WORKTREE_GROUP; or return
    set_color $WORKTREE_COLOR_FG
    printf ' [%s]' "$WORKTREE_GROUP"
    set_color normal
end


# ─── Terminal background tint via OSC 11 ───────────────────────────────────
#
# Fires when WORKTREE_GROUP is set or erased. Tints the terminal background
# on group entry, resets on exit. Writes to /dev/tty so direnv / pipelines
# can't swallow the escape sequence.

function __wt_on_group --on-variable WORKTREE_GROUP
    if set -q WORKTREE_GROUP; and test -n "$WORKTREE_COLOR_BG"
        printf '\e]11;%s\a' "$WORKTREE_COLOR_BG" > /dev/tty
    else
        printf '\e]111\a' > /dev/tty
    end
end
