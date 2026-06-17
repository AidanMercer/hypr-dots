#!/usr/bin/env bash
# hyprlock's `screenshot` background comes back black on this box (nvidia/
# screencopy), so we blur the actual wallpaper instead. The real wallpapers are
# huge (16MP+), and decoding one at lock time makes the lock visibly lag, so we
# keep a small screen-sized copy cached and only rebuild it when awww reports a
# different wallpaper. Normal locks just load the ~60KB cache → instant.
cache="$HOME/.cache/lockwall.jpg"
srcmark="$HOME/.cache/lockwall.src"

wall=$(awww query 2>/dev/null | grep -oP 'image: \K.*' | head -1)
if [ -n "$wall" ] && { [ ! -f "$cache" ] || [ "$(cat "$srcmark" 2>/dev/null)" != "$wall" ] || [ "$wall" -nt "$cache" ]; }; then
    ffmpeg -y -i "$wall" -vf "scale=2560:-1" "$cache" >/dev/null 2>&1 && printf '%s' "$wall" >"$srcmark"
fi

# make sure the themed lock colors exist (hyprlock sources them); cheap if present
[ -f "$HOME/.cache/theme/hypr-colors.conf" ] || "$HOME/dotfiles/.config/hypr/theme-colors.sh" >/dev/null 2>&1

exec hyprlock "$@"
