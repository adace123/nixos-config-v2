#!/usr/bin/env nu
#
# Keep the bar's repo-owned widgets on the active profile, and pin its look.
#
# OmniShell writes GUI layout changes into ~/.config/omniwm/shell/shell.toml, so
# this merges rather than owns the file: every lane list is read from the file
# itself (else from its profile folder's shell.toml, else from the bundled
# default/), widgets are added or removed, the theme, bar surface, island,
# weather location and per-widget options are set when given, and everything
# else in the file is written back untouched. TOML comments do not survive the
# round trip; OmniWM writes this file itself, so there are normally none to
# lose.

# A key a profile folder's shell.toml supplies, or null when it has none.
def layer-in [file: path, key: string] {
    if ($file | path exists) {
        try { open --raw $file | from toml | get --optional $key } catch { null }
    } else {
        null
    }
}

# The lane the profile currently uses: its own override, else the profile
# folder's shell.toml, else the bundled default, else `fallback`.
def lane-in [settings: record, layer: path, bundled: path, key: string, fallback: list] {
    let own = ($settings | get --optional $key)
    if $own != null {
        $own
    } else {
        let inherited = (layer-in $layer $key)
        if $inherited != null {
            $inherited
        } else {
            let shared = (layer-in $bundled $key)
            if $shared != null { $shared } else { $fallback }
        }
    }
}

# Drop every name in `names` from `lane`.
def without [lane: list, names: list] {
    $lane | where {|name| $names | all {|drop| $drop != $name } }
}

# Append names that are not already in `lane`, preserving the existing order.
def with-widgets [lane: list, names: list] {
    $names | reduce -f $lane {|name, acc|
        if ($acc | any {|existing| $existing == $name }) { $acc } else { $acc | append $name }
    }
}

# A comma-separated widget list, or an empty list when the flag is absent.
def names [value: any] {
    if $value == null {
        []
    } else {
        $value | split row "," | each {|name| $name | str trim } | where {|name| $name != "" }
    }
}

def main [
    shell_dir: path # the OmniShell folder, e.g. ~/.config/omniwm/shell
    widget: string # widget to keep at the front of the trailing lane
    theme?: string # theme to pin on the active profile, or none to leave it
    --bar-opacity: float # bar background opacity to pin, or none to leave it
    --bar-height: float # bar height to pin, or none to leave it
    --item-backgrounds # draw the bar items' background pills
    --leading-widgets: string # comma-separated widgets to append to the leading lane
    --trailing-widgets: string # comma-separated widgets to prepend to the trailing lane
    --remove-widgets: string # comma-separated widgets to drop from every lane
    --weather: path # weather location table to merge into the profile
    --island: path # island placement table to merge into the profile
    --widgets: path # per-widget settings tables to merge into the profile
    --dry-run # print the merged file instead of writing it
] {
    let root = $shell_dir | path expand --no-symlink
    let live = $root | path join "shell.toml"

    let current = if ($live | path exists) {
        try {
            open --raw $live | from toml
        } catch {
            print --stderr $"warning: ($live) is not valid TOML; leaving it alone"
            return
        }
    } else {
        {}
    }

    let profile = (try { $current | get --optional profile } catch { null } | default "default")
    let profiles = ($current | get --optional profiles | default {})
    let settings = ($profiles | get --optional $profile | default {})
    let layer = ($root | path join $profile "shell.toml")
    let bundled = ($root | path join "default" "shell.toml")

    # Before first launch -- no profile folder yet -- this is OmniWM 0.8.0's
    # Default trailing lane, so seeding it does not drop the bundled widgets.
    let fallback = [
        "media"
        "notifications"
        "volume"
        "wifi"
        "battery-details"
        "control-center"
        "system-stats"
        "clock"
    ]

    let remove = (names $remove_widgets)
    let leading_names = (names $leading_widgets)
    let trailing_names = (names $trailing_widgets)

    let trailing_now = (lane-in $settings $layer $bundled "trailing" $fallback)
    let leading_now = (lane-in $settings $layer $bundled "leading" [])
    let center_now = (lane-in $settings $layer $bundled "center" [])

    let trailing_base = (without $trailing_now $remove)
    let trailing_body = if ($trailing_base | any {|name| $name == $widget }) {
        $trailing_base
    } else {
        [$widget] | append $trailing_base
    }
    # Extra trailing widgets sit at the front of the lane, after the positional
    # one; a name already present keeps its position.
    let trailing_extras = $trailing_names | where {|name|
        $name != $widget and not ($trailing_base | any {|existing| $existing == $name })
    }
    let trailing_final = $trailing_extras | append $trailing_body
    let leading_final = (with-widgets (without $leading_now $remove) $leading_names)
    let center_final = (without $center_now $remove)

    # The bundled Default style pins `backgroundOpacity` and
    # `showItemBackgrounds` for the bar, and a style layer beats both
    # `settings.workspaceBar` and a theme's `[workspaceBar]`, so a dark surface
    # has to be pinned again here, in the profile layer that wins.
    let bar = ($settings | get --optional workspaceBar | default {})

    let weather = if $weather == null {
        null
    } else {
        ($settings | get --optional weather | default {}) | merge (open --raw $weather | from toml)
    }

    let island = if $island == null {
        null
    } else {
        ($settings | get --optional island | default {}) | merge (open --raw $island | from toml)
    }

    # Widget options are merged per widget name, so a table here only has to
    # carry the keys it changes.
    let widgets = if $widgets == null {
        null
    } else {
        let incoming = (open --raw $widgets | from toml)
        $incoming | transpose key value | reduce -f ($settings | get --optional widgets | default {}) {|it, acc|
            let current = ($acc | get --optional $it.key | default {})
            $acc | upsert $it.key ($current | merge $it.value)
        }
    }

    let pinned = if $theme == null { $settings } else { $settings | upsert theme $theme }
    let pinned = if $bar_opacity == null {
        $pinned
    } else {
        $pinned | upsert workspaceBar ($bar | upsert backgroundOpacity $bar_opacity)
    }
    let pinned = if $bar_height == null {
        $pinned
    } else {
        let bar = ($pinned | get --optional workspaceBar | default {})
        $pinned | upsert workspaceBar ($bar | upsert height $bar_height)
    }
    let pinned = if not $item_backgrounds {
        $pinned
    } else {
        let bar = ($pinned | get --optional workspaceBar | default {})
        $pinned | upsert workspaceBar ($bar | upsert showItemBackgrounds true)
    }
    # A lane is only written when this changes it: an untouched lane keeps
    # falling through to the style, so later edits to the style's own lists
    # still reach the profile.
    let pinned = if $trailing_final == $trailing_now {
        $pinned
    } else {
        $pinned | upsert trailing $trailing_final
    }
    let pinned = if $leading_final == $leading_now {
        $pinned
    } else {
        $pinned | upsert leading $leading_final
    }
    let pinned = if $center_final == $center_now {
        $pinned
    } else {
        $pinned | upsert center $center_final
    }
    let pinned = if $weather == null { $pinned } else { $pinned | upsert weather $weather }
    let pinned = if $island == null { $pinned } else { $pinned | upsert island $island }
    let pinned = if $widgets == null { $pinned } else { $pinned | upsert widgets $widgets }

    if $pinned == $settings {
        return
    }

    let updated = ($current | upsert profiles ($profiles | upsert $profile $pinned))

    if $dry_run {
        print ($updated | to toml)
        return
    }

    mkdir $root
    $updated | to toml | save --force $live
}
