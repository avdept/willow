# quickshell

A custom [Quickshell](https://quickshell.outfoxxed.me/) desktop shell for
Hyprland (built on top of Omarchy): top bar, spotlight-style launcher,
notification toasts + drawer, an on-screen display (OSD) for volume / mic /
brightness / lock, and calendar reminders.

Run it with `qs` (the entry point is `shell.qml`); it's typically started from
Hyprland's `autostart.conf`.

## Hyprland settings

The shell renders fine on its own, but a few Hyprland settings make it look and
behave as intended. These live in your **user** Hyprland config
(`~/.config/hypr/`), not the Omarchy defaults.

### Transparency & blur

The shell's surfaces are drawn with translucent backgrounds (see *Surface
opacity* below), so Hyprland can blur what's behind them for a frosted-glass
look. Each surface is a layer-shell window with a stable namespace:

| Surface             | Namespace                          |
| ------------------- | ---------------------------------- |
| Launcher            | `quickshell-launcher`              |
| OSD                 | `quickshell-osd`                   |
| Notification toasts | `quickshell-notification-toasts`   |
| Notification drawer | `quickshell-notification-drawer`   |

Enable blur globally and add a `layerrule` per surface (e.g. in
`~/.config/hypr/looknfeel.conf`):

```ini
decoration {
    blur {
        enabled = true
        size = 4      # higher = softer/wider; 5+ can wash surfaces out to grey
        passes = 2
    }
}

# Blur behind the Quickshell surfaces. ignore_alpha 0.5 blurs only the card /
# popup body (bg alpha ~0.8–0.92) and skips the transparent window margins and
# the soft drop shadow (alpha ≤ 0.22) — without it the whole rectangular
# surface gets an ugly blurred halo around the rounded cards.
layerrule = blur on, ignore_alpha 0.5, match:namespace quickshell-launcher
layerrule = blur on, ignore_alpha 0.5, match:namespace quickshell-osd
layerrule = blur on, ignore_alpha 0.5, match:namespace quickshell-notification-toasts
layerrule = blur on, ignore_alpha 0.5, match:namespace quickshell-notification-drawer
```

Notes:
- The `layerrule = ... match:namespace ...` form is current Hyprland syntax.
  Older versions used `layerrule = blur,<namespace>` and
  `layerrule = ignorealpha 0.5,<namespace>` — check `hyprctl configerrors`
  after editing.
- Blur over a **window** behind a surface is obvious (sharp content goes soft);
  blur over just the **wallpaper** is subtle, because a wallpaper is already
  smooth — that's expected, not a bug.
- Validate after changes: `hyprctl reload && hyprctl configerrors`.

### Surface opacity

The translucency itself is set in QML (no Hyprland config needed — Hyprland
composites the alpha automatically). Tune these if surfaces look too
see-through or too solid:

| What            | File / property                          | Value  |
| --------------- | ---------------------------------------- | ------ |
| Launcher        | `Launcher.qml` → `cardAlpha`             | `0.92` |
| OSD pill        | `modules/osd/Osd.qml` (pill `color`)     | `0.92` |
| Toast card      | `NotificationCard.qml` (card `color`)    | `0.8`  |
| Drawer header   | `NotificationDrawer.qml` (header `color`)| `0.92` |

Keep these **above** the `ignore_alpha` threshold (0.5) or Hyprland won't blur
them.

### Corner radius

A single token controls rounding for all cards/containers/buttons:
`Theme.qml` → `radius` (default `4`).

### Keybindings & IPC

The shell is driven over IPC (`qs ipc call …`). Suggested binds in
`~/.config/hypr/bindings.conf`:

```ini
# Launcher
bindd = CTRL, SPACE, Quickshell launcher, exec, qs ipc call launcher toggle

# Trigger views (override Omarchy's capture/share menus, optional)
bindd = SUPER CTRL, C, Trigger menu,  exec, qs ipc call launcher showBareProvider trigger
bindd = SUPER CTRL, S, Share menu,    exec, qs ipc call launcher showBareProviderView trigger share

# Notification drawer
bindd = SUPER, N, Notifications, exec, qs ipc call notifs toggle

# Settings window
bindd = SUPER, COMMA, Settings, exec, qs ipc call settings toggle
```

## Settings window

`SettingsWindow.qml` is a standalone settings window — a real toplevel
(`FloatingWindow`), not a layer-shell popup like the launcher/drawer.

Open it with the **settings** entry in the launcher's footer hint bar (next to
*navigate* / *open*), or `qs ipc call settings toggle`.

It edits the `Config` singleton (`shared/Config.qml`), which persists to
`$XDG_CONFIG_HOME/quickshell/settings.json` (created on first run) and is read
live by the rest of the shell:

| Setting             | Affects                                              |
| ------------------- | --------------------------------------------------- |
| Font                | All shell text (`fontFamily`)                        |
| Corner radius       | `Theme.radius` — cards/containers/buttons            |
| Surface opacity     | `Theme.surfaceOpacity` — launcher, OSD, drawer       |
| Toast duration      | `NotificationToasts.toastDurationMs`                 |
| OSD timeout         | `Osd.hideMs`                                          |
| Reminder lead times | `CalendarReminders.leadsMin`                          |

Because it's an ordinary window, Hyprland tiles it by default. To float and
center it, add a windowrule keyed on the title (in `~/.config/hypr/`):

```ini
windowrulev2 = float, title:^(Quickshell Settings)$
windowrulev2 = center, title:^(Quickshell Settings)$
windowrulev2 = size 480 600, title:^(Quickshell Settings)$
```

### OSD (media keys)

The OSD replaces SwayOSD. Disable the SwayOSD server/binds and reroute the
media keys to act directly; volume and mic are reactive (Pipewire), brightness
is triggered over IPC:

```ini
# Volume (OSD reacts to the Pipewire change automatically)
unbind = , XF86AudioRaiseVolume
bindeld = , XF86AudioRaiseVolume, Volume up,   exec, wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+
unbind = , XF86AudioLowerVolume
bindeld = , XF86AudioLowerVolume, Volume down, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-
unbind = , XF86AudioMute
bindeld = , XF86AudioMute, Mute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle

# Brightness (explicitly poke the OSD over IPC)
unbind = , XF86MonBrightnessUp
bindeld = , XF86MonBrightnessUp,   Brightness up,   exec, brightnessctl -c backlight set 5%+ && qs ipc call osd brightness
unbind = , XF86MonBrightnessDown
bindeld = , XF86MonBrightnessDown, Brightness down, exec, brightnessctl -c backlight set 5%- && qs ipc call osd brightness
```

## Calendar reminders

`shared/CalendarReminders.qml` fires notifications ahead of timed calendar
events, read from the same vdirsyncer cache as the launcher calendar (see
`launcher/calendar/SETUP.md`). Lead times are configured in `shell.qml`
(`leadsMin`). Requires `vdirsyncer` syncing on a timer
(`systemctl --user enable --now vdirsyncer.timer`).
