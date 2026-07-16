# TODO

## Theming (wallpaper-driven)
- [x] frostify themed with the wallpaper theme
- [x] kitty better themed to the wallpaper (theme-colors.sh retints on switch)
- [x] super fuzzel launcher should be custom themed (theme-colors.sh too)
- [x] better lockscreen / per-theme lockscreens (lock.qml slot, bareLock takeover)
- [x] video wallpapers (mp4 per variant, VideoWall + lock map still→mp4 by suffix)
- [x] video themes (avalon + vinland, bare lock, per-theme .qsb shaders)
- [ ] themed sddm greeter (matches current wallpaper theme, boot→desktop cohesion)
- [ ] GTK/qt5ct retint (extend theme-colors.sh so foreign apps follow the theme too)

## Apps / widgets
- [x] custom file explorer (mica — PySide6+QML miller-columns manager, live world80 theming, Super+E)
- [x] multi-mode launcher (prefix modes in the Super launcher: `e ` emoji, `w ` window switch/kill, `c ` clipboard, `u `/inline unit convert, `=` calc; live currency still TODO)
- [x] command palette (Super+P — fuzzy over theme apply/next/prev, open any panel, toggles (autolock/sysinfo/ui-scale/lyrics), window + session actions; each fires the matching `qs ipc call …` or hypr dispatch)
- [x] live lyrics (LyricsEngine in the shell + lyrics.qml per theme)
- [x] better Super+M menu (popup.qml chrome slot)
- [x] control center (bluetooth/network/display/sound/power tabs)
- [x] media controls widget (MPRIS)
- [ ] audio EQ (pipewire filter-chain presets, themed panel — control center sound tab or frostify)
- [ ] themed screenshot + annotation (grim region-select overlay with arrows/blur/crop, satty replacement)
- [ ] calendar / agenda popup on the clock (per-theme slot, month view)
- [x] clipboard history popup (cliphist)
- [x] volume / brightness OSD

## Custom apps
- [x] frostify — music player
- [x] mica — file explorer
- [x] text / markdown editor (vellum — PySide6+QML modal vim editor + live themed markdown preview; follows world80 like mica/frostify, ~/dev/vellum)
- [x] browser (beryl — vim-driven QtWebEngine, hardened-private, multi-window, Super+B, ~/dev/beryl)
- [ ] image / gallery viewer (keyboard-driven, themed, pairs with mica)
- [x] pdf / document reader (vellum reads pdfs now — read-only reading view, / n N search w/ highlights, zoom, live reload on disk change)
- [x] system dashboard (pulse — full-window btop-style cpu/mem/net/disks/procs, keyboard-driven, Super+Escape, ~/dev/pulse)
- [x] extensions store (Super+/ 4th tab — install/update/remove the app suite via ext-install.sh; installs wire the desktop entry, cheat-sheet row and mica's picker portal; the Settings update pulls installed apps too)

## Theme settings & layout
- [x] per-theme settings in the Super+Shift+/ sheet (clock/visualizer/sysinfo/lyrics toggles, ThemeSettings singleton, loaders unmount live)
- [x] auto-sizing for large monitor vs laptop/work screen (pal.uiScale, all themes)
- [x] interface scale slider (80–140%, UiScale singleton)

## Wallpapers & theme browsing
- [x] more custom wallpapers + push to github (10 themes, multi-wallpaper variants in the switcher)
- [x] gallery theme switcher (Super+/, vertical wallpaper-variant rail)
- [x] theme marketplace — browse + download themes from github (Super+/ 3rd tab)
- [x] custom theme-switch transition (chrome bows out → awww wipes the wallpaper daemon-side, immune to qs compile stalls → new chrome + already-playing video emerge during the wipe's tail; ControlBus.swapping gates every theme loader)

## Slot parity (older themes missing newer slots)
- [x] moon: lock.qml + notif.qml (breach-deck bare lock, HUD notif cards)
- [x] shiro: popup.qml (washi card) + sysinfo.qml (margin-notes slip)
- [x] avalon: sysinfo.qml (hanging vitals ledger)
- [x] lonely-train: sysinfo.qml (arrivals board)

## Motion / eye-candy (all togglable via Super+Shift+/)
- [x] workspace overview / zoom-out exposé (Super+Tab — focused window dead-center, every other window fanned around it on a ring as live ScreencopyView thumbnails; arrows move by direction, enter/click switches, ring shrinks past ~8 windows)
- [ ] cursor parallax (subtle wallpaper depth-shift between workspaces)
- [x] theme-native ambient particles (particles.qml slot, all 11 themes — avalon petals, vinland snow, moon data-static, lonely-train passing lights…; Bottom layer, occlusion-gated, Super+Shift+/ toggle)

## System / desktop polish
- [x] captive portal watcher (nmcli monitor → sticky card → open login page)
- [x] sysinfo hover-pin (Super+., overlay layer)
- [x] notification center — history + do-not-disturb (Super+I drawer; every card snapshotted to a stateDir JSON, DND via Super+Shift+I/panel pill sends all but critical straight to history; per-theme panel chrome in each theme's notif.qml — panelBg/panelTitle/panelBackdrop slot props)
- [x] battery-low notifications (BAT* poll in Notifications.qml → sticky cards: low 20% / critical 10% while discharging, latched; plugging in clears them silently — no charge spam; `qs ipc call battery test low|crit`)

## Misc
- [ ] custom fastfetch
