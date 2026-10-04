#!/bin/sh
# Launch Home Invasion from a terminal.
#
# This runs the PROJECT, not the exported .app. Two reasons to prefer it:
#   - it starts faster and always runs the current source, no rebuild
#   - Godot prints errors and warnings to this terminal, which the packaged
#     build hides completely
#
# Usage:
#   ./run.sh                                   play the game
#   ./run.sh --shot=/tmp/shot.png --shotgun    render, save a PNG, quit
#   ./run.sh --help                            (goes to Godot)
#
# Anything you pass is forwarded to the game. Godot only sees user arguments
# after a "--" separator, so this adds that for you.

set -e

GODOT="$HOME/.dsh/tools/godot/Godot.app/Contents/MacOS/Godot"
HERE="$(cd "$(dirname "$0")" && pwd)"

if [ ! -x "$GODOT" ]; then
	echo "run.sh: no Godot at $GODOT" >&2
	exit 1
fi

if [ "$#" -gt 0 ]; then
	# --quit-after is a safety net: a failed screenshot capture would otherwise
	# leave the game running forever and look like a hang.
	exec "$GODOT" --path "$HERE" --quit-after 900 -- "$@"
fi

exec "$GODOT" --path "$HERE"
