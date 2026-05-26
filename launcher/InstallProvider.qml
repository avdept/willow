// Install provider — mirrors the "Install" section of `omarchy-menu`.
// Categories drill into their own sub-views; leaves spawn either a
// terminal `omarchy-pkg-install` / `omarchy-pkg-aur-install` flow, or
// `omarchy-launch-floating-terminal-with-presentation` wrapping an
// install script. Typing at the root view fuzzy-searches across every
// leaf so `install steam` finds Steam without drilling into Gaming.

import QtQuick
import Quickshell.Io

Provider {
    id: prov

    name: "Install"
    tag: "install"
    iconText: "󰉉"
    description: "Install apps, languages, themes, fonts"
    shortcuts: ["i", "install"]

    // "" = root. Sub-views: service, style, style_font, development,
    // development_js, development_php, development_elixir, editor,
    // terminal, browser, ai, gaming.
    property string view: ""

    readonly property var _viewParent: ({
        "style_font":         "style",
        "development_js":     "development",
        "development_php":    "development",
        "development_elixir": "development"
    })

    readonly property var _viewTitle: ({
        "":                   "",
        "service":            "service",
        "style":              "style",
        "style_font":         "style / font",
        "development":        "development",
        "development_js":     "development / javascript",
        "development_php":    "development / php",
        "development_elixir": "development / elixir",
        "editor":             "editor",
        "terminal":           "terminal",
        "browser":            "browser",
        "ai":                 "ai",
        "gaming":             "gaming"
    })

    // ── Helpers to build install command strings ─────────────────────────
    function _pkg(label, pkgs) {
        return "echo 'Installing " + label + "...'; omarchy-pkg-add " + pkgs;
    }
    function _pkgAndLaunch(label, pkgs, desktop) {
        return _pkg(label, pkgs) + " && setsid gtk-launch " + desktop;
    }
    function _font(label, pkg, family) {
        return _pkg(label, pkg) + " && sleep 2 && omarchy-font-set '" + family + "'";
    }
    function _aur(label, pkgs) {
        return "echo 'Installing " + label + " from AUR...'; omarchy-pkg-aur-add " + pkgs;
    }

    // ── Row catalogs ─────────────────────────────────────────────────────
    readonly property var _rootRows: [
        { title: "Package",     subtitle: "pacman -S",            iconText: "󰣇", score: 1300,
          data: { kind: "terminal", argv: ["omarchy-pkg-install"] } },
        { title: "AUR",         subtitle: "Arch User Repository", iconText: "󰣇", score: 1290,
          data: { kind: "terminal", argv: ["omarchy-pkg-aur-install"] } },
        { title: "Web App",     subtitle: "Install a web app",    iconText: "", score: 1280,
          data: { kind: "present", cmd: "omarchy-webapp-install" } },
        { title: "TUI",         subtitle: "Terminal UI apps",     iconText: "", score: 1270,
          data: { kind: "present", cmd: "omarchy-tui-install" } },
        { title: "Service",     subtitle: "Dropbox, Tailscale, …",      iconText: "", chevron: true, score: 1260,
          data: { kind: "drill", view: "service" } },
        { title: "Style",       subtitle: "Themes, backgrounds, fonts", iconText: "", chevron: true, score: 1250,
          data: { kind: "drill", view: "style" } },
        { title: "Development", subtitle: "Languages and frameworks",   iconText: "󰵮", chevron: true, score: 1240,
          data: { kind: "drill", view: "development" } },
        { title: "Editor",      subtitle: "VSCode, Neovim, …",          iconText: "", chevron: true, score: 1230,
          data: { kind: "drill", view: "editor" } },
        { title: "Terminal",    subtitle: "Alacritty, Foot, Ghostty, Kitty", iconText: "", chevron: true, score: 1220,
          data: { kind: "drill", view: "terminal" } },
        { title: "Browser",     subtitle: "Chrome, Firefox, …",         iconText: "", chevron: true, score: 1210,
          data: { kind: "drill", view: "browser" } },
        { title: "AI",          subtitle: "Ollama, LM Studio, …",       iconText: "󱚤", chevron: true, score: 1200,
          data: { kind: "drill", view: "ai" } },
        { title: "Gaming",      subtitle: "Steam, RetroArch, …",        iconText: "", chevron: true, score: 1190,
          data: { kind: "drill", view: "gaming" } },
        { title: "Windows",     subtitle: "VM via virt-manager",        iconText: "󰍲", score: 1180,
          data: { kind: "present", cmd: "omarchy-windows-vm install" } }
    ]

    readonly property var _serviceRows: [
        { title: "Dropbox",          iconText: "", score: 1000,
          data: { kind: "present", cmd: "omarchy-install-dropbox" } },
        { title: "Tailscale",        iconText: "", score: 990,
          data: { kind: "present", cmd: "omarchy-install-tailscale" } },
        { title: "NordVPN [AUR]",    iconText: "󱇱", score: 980,
          data: { kind: "present", cmd: "omarchy-install-nordvpn" } },
        { title: "ONCE",             iconText: "󰏖", score: 970,
          data: { kind: "present", cmd: "omarchy-install-once" } },
        { title: "Bitwarden",        iconText: "󰟵", score: 960,
          data: { kind: "present", cmd: prov._pkgAndLaunch("Bitwarden", "bitwarden bitwarden-cli", "bitwarden") } },
        { title: "Chromium Account", iconText: "", score: 950,
          data: { kind: "present", cmd: "omarchy-install-chromium-google-account" } }
    ]

    readonly property var _styleRows: [
        { title: "Theme",      subtitle: "Install a community theme",     iconText: "󰸌", score: 1000,
          data: { kind: "present", cmd: "omarchy-theme-install" } },
        { title: "Background", subtitle: "Add a wallpaper to current theme", iconText: "", score: 990,
          data: { kind: "spawn", argv: ["omarchy-theme-bg-install"] } },
        { title: "Font",       subtitle: "Nerd Font monospace",           iconText: "", chevron: true, score: 980,
          data: { kind: "drill", view: "style_font" } }
    ]

    readonly property var _styleFontRows: [
        { title: "Cascadia Mono",       iconText: "", score: 1000,
          data: { kind: "present", cmd: prov._font("Cascadia Mono",       "ttf-cascadia-mono-nerd",      "CaskaydiaMono Nerd Font") } },
        { title: "Meslo LG Mono",       iconText: "", score: 990,
          data: { kind: "present", cmd: prov._font("Meslo LG Mono",       "ttf-meslo-nerd",              "MesloLGL Nerd Font") } },
        { title: "Fira Code",           iconText: "", score: 980,
          data: { kind: "present", cmd: prov._font("Fira Code",           "ttf-firacode-nerd",           "FiraCode Nerd Font") } },
        { title: "Victor Code",         iconText: "", score: 970,
          data: { kind: "present", cmd: prov._font("Victor Code",         "ttf-victor-mono-nerd",        "VictorMono Nerd Font") } },
        { title: "Bitstream Vera Code", iconText: "", score: 960,
          data: { kind: "present", cmd: prov._font("Bitstream Vera Code", "ttf-bitstream-vera-mono-nerd","BitstromWera Nerd Font") } },
        { title: "Iosevka",             iconText: "", score: 950,
          data: { kind: "present", cmd: prov._font("Iosevka",             "ttf-iosevka-nerd",            "Iosevka Nerd Font Mono") } }
    ]

    readonly property var _developmentRows: [
        { title: "Ruby on Rails", iconText: "󰫏", score: 1000,
          data: { kind: "present", cmd: "omarchy-install-dev-env ruby" } },
        { title: "Docker DB",     iconText: "",  score: 990,
          data: { kind: "present", cmd: "omarchy-install-docker-dbs" } },
        { title: "JavaScript",    iconText: "",  chevron: true, score: 980,
          data: { kind: "drill", view: "development_js" } },
        { title: "Go",            iconText: "",  score: 970,
          data: { kind: "present", cmd: "omarchy-install-dev-env go" } },
        { title: "PHP",           iconText: "",  chevron: true, score: 960,
          data: { kind: "drill", view: "development_php" } },
        { title: "Python",        iconText: "",  score: 950,
          data: { kind: "present", cmd: "omarchy-install-dev-env python" } },
        { title: "Elixir",        iconText: "",  chevron: true, score: 940,
          data: { kind: "drill", view: "development_elixir" } },
        { title: "Zig",           iconText: "",  score: 930,
          data: { kind: "present", cmd: "omarchy-install-dev-env zig" } },
        { title: "Rust",          iconText: "",  score: 920,
          data: { kind: "present", cmd: "omarchy-install-dev-env rust" } },
        { title: "Java",          iconText: "",  score: 910,
          data: { kind: "present", cmd: "omarchy-install-dev-env java" } },
        { title: ".NET",          iconText: "",  score: 900,
          data: { kind: "present", cmd: "omarchy-install-dev-env dotnet" } },
        { title: "OCaml",         iconText: "",  score: 890,
          data: { kind: "present", cmd: "omarchy-install-dev-env ocaml" } },
        { title: "Clojure",       iconText: "",  score: 880,
          data: { kind: "present", cmd: "omarchy-install-dev-env clojure" } },
        { title: "Scala",         iconText: "",  score: 870,
          data: { kind: "present", cmd: "omarchy-install-dev-env scala" } }
    ]

    readonly property var _developmentJsRows: [
        { title: "Node.js", iconText: "", score: 1000,
          data: { kind: "present", cmd: "omarchy-install-dev-env node" } },
        { title: "Bun",     iconText: "", score: 990,
          data: { kind: "present", cmd: "omarchy-install-dev-env bun" } },
        { title: "Deno",    iconText: "", score: 980,
          data: { kind: "present", cmd: "omarchy-install-dev-env deno" } }
    ]

    readonly property var _developmentPhpRows: [
        { title: "PHP",     iconText: "", score: 1000,
          data: { kind: "present", cmd: "omarchy-install-dev-env php" } },
        { title: "Laravel", iconText: "", score: 990,
          data: { kind: "present", cmd: "omarchy-install-dev-env laravel" } },
        { title: "Symfony", iconText: "", score: 980,
          data: { kind: "present", cmd: "omarchy-install-dev-env symfony" } }
    ]

    readonly property var _developmentElixirRows: [
        { title: "Elixir",  iconText: "", score: 1000,
          data: { kind: "present", cmd: "omarchy-install-dev-env elixir" } },
        { title: "Phoenix", iconText: "", score: 990,
          data: { kind: "present", cmd: "omarchy-install-dev-env phoenix" } }
    ]

    readonly property var _editorRows: [
        { title: "VSCode",       iconText: "", score: 1000,
          data: { kind: "present", cmd: "omarchy-install-vscode" } },
        { title: "Cursor",       iconText: "", score: 990,
          data: { kind: "present", cmd: prov._pkgAndLaunch("Cursor", "cursor-bin", "cursor") } },
        { title: "Zed",          iconText: "", score: 980,
          data: { kind: "present", cmd: "omarchy-install-zed" } },
        { title: "Sublime Text", iconText: "", score: 970,
          data: { kind: "present", cmd: prov._pkgAndLaunch("Sublime Text", "sublime-text-4", "sublime_text") } },
        { title: "Helix",        iconText: "", score: 960,
          data: { kind: "present", cmd: "omarchy-install-helix" } },
        { title: "Vim",          iconText: "", score: 950,
          data: { kind: "present", cmd: prov._pkg("Vim", "vim") } },
        { title: "Emacs",        iconText: "", score: 940,
          data: { kind: "present", cmd: prov._pkg("Emacs", "emacs-wayland") + " && systemctl --user enable --now emacs.service" } }
    ]

    readonly property var _terminalRows: [
        { title: "Alacritty", iconText: "", score: 1000,
          data: { kind: "present", cmd: "omarchy-install-terminal alacritty" } },
        { title: "Foot",      iconText: "", score: 990,
          data: { kind: "present", cmd: "omarchy-install-terminal foot" } },
        { title: "Ghostty",   iconText: "", score: 980,
          data: { kind: "present", cmd: "omarchy-install-terminal ghostty" } },
        { title: "Kitty",     iconText: "", score: 970,
          data: { kind: "present", cmd: "omarchy-install-terminal kitty" } }
    ]

    readonly property var _browserRows: [
        { title: "Chrome",       iconText: "", score: 1000,
          data: { kind: "present", cmd: "omarchy-install-browser chrome" } },
        { title: "Edge",         iconText: "", score: 990,
          data: { kind: "present", cmd: "omarchy-install-browser edge" } },
        { title: "Brave",        iconText: "", score: 980,
          data: { kind: "present", cmd: "omarchy-install-browser brave" } },
        { title: "Brave Origin", iconText: "", score: 970,
          data: { kind: "present", cmd: "omarchy-install-browser brave-origin" } },
        { title: "Firefox",      iconText: "", score: 960,
          data: { kind: "present", cmd: "omarchy-install-browser firefox" } },
        { title: "Zen",          iconText: "󰖟", score: 950,
          data: { kind: "present", cmd: "omarchy-install-browser zen" } }
    ]

    readonly property var _aiRows: [
        { title: "Dictation", subtitle: "voxtype",  iconText: "",  score: 1000,
          data: { kind: "present", cmd: "omarchy-voxtype-install" } },
        { title: "LM Studio", iconText: "󱚤",                       score: 990,
          data: { kind: "present", cmd: prov._pkg("LM Studio", "lmstudio-bin") } },
        { title: "Ollama",    subtitle: "auto-picks cuda/rocm/cpu", iconText: "󱚤", score: 980,
          data: { kind: "present", cmd: "ollama_pkg=$( (omarchy-cmd-present nvidia-smi && echo ollama-cuda) || (omarchy-cmd-present rocminfo && echo ollama-rocm) || echo ollama ); " + prov._pkg("Ollama", "$ollama_pkg") } },
        { title: "Crush",     iconText: "󱚤",                       score: 970,
          data: { kind: "present", cmd: prov._pkg("Crush", "crush-bin") } }
    ]

    readonly property var _gamingRows: [
        { title: "Steam",                iconText: "",  score: 1000,
          data: { kind: "present", cmd: "omarchy-install-gaming-steam" } },
        { title: "RetroArch",            iconText: "",  score: 990,
          data: { kind: "present", cmd: "omarchy-install-gaming-retroarch" } },
        { title: "Minecraft",            iconText: "󰍳", score: 980,
          data: { kind: "present", cmd: prov._pkgAndLaunch("Minecraft", "minecraft-launcher", "minecraft-launcher") } },
        { title: "NVIDIA GeForce NOW",   iconText: "󰢹", score: 970,
          data: { kind: "present", cmd: "omarchy-install-gaming-geforce-now" } },
        { title: "Xbox Cloud Gaming",    iconText: "",  score: 960,
          data: { kind: "present", cmd: "omarchy-install-gaming-xbox-cloud" } },
        { title: "Xbox Controller",      iconText: "󰂯", score: 950,
          data: { kind: "present", cmd: "omarchy-install-gaming-xbox-controllers" } },
        { title: "Moonlight (GameStream)", iconText: "󰍹", score: 940,
          data: { kind: "present", cmd: "omarchy-install-gaming-moonlight" } },
        { title: "Lutris (Battle.net)",  iconText: "",  score: 930,
          data: { kind: "present", cmd: "omarchy-install-gaming-lutris" } },
        { title: "Heroic (Epic Games)",  iconText: "󱓟", score: 920,
          data: { kind: "present", cmd: "omarchy-install-gaming-heroic" } }
    ]

    function _rowsForView(v) {
        switch (v) {
        case "":                   return _rootRows;
        case "service":            return _serviceRows;
        case "style":              return _styleRows;
        case "style_font":         return _styleFontRows;
        case "development":        return _developmentRows;
        case "development_js":     return _developmentJsRows;
        case "development_php":    return _developmentPhpRows;
        case "development_elixir": return _developmentElixirRows;
        case "editor":             return _editorRows;
        case "terminal":           return _terminalRows;
        case "browser":            return _browserRows;
        case "ai":                 return _aiRows;
        case "gaming":             return _gamingRows;
        }
        return [];
    }

    function search(text) {
        const q = norm(text);
        if (view === "") {
            results = q.length === 0 ? _rootRows.slice() : _searchAllLeaves(q);
        } else {
            results = _filter(_rowsForView(view), q);
        }
    }

    // Flat fuzzy search across every leaf in every sub-view. Lets the
    // global launcher search hit "steam" without first drilling Gaming.
    function _searchAllLeaves(q) {
        const views = ["", "service", "style", "style_font", "development",
                       "development_js", "development_php", "development_elixir",
                       "editor", "terminal", "browser", "ai", "gaming"];
        const seen = {};
        const leaves = [];
        for (let v = 0; v < views.length; v++) {
            const rows = _rowsForView(views[v]);
            for (let i = 0; i < rows.length; i++) {
                const r = rows[i];
                if (r.data && r.data.kind === "drill") continue;
                const key = r.title + "|" + ((r.data && r.data.cmd) || ((r.data && r.data.argv) || []).join(" "));
                if (seen[key]) continue;
                seen[key] = true;
                leaves.push(r);
            }
        }
        return _filter(leaves, q);
    }

    function _filter(rows, q) {
        if (q.length === 0) return rows.slice();
        const out = [];
        for (let i = 0; i < rows.length; i++) {
            const r = rows[i];
            const s = scoreText(q, norm(r.title), norm(r.subtitle || ""));
            if (s <= 0) continue;
            out.push(Object.assign({}, r, { score: s }));
        }
        out.sort((a, b) => b.score - a.score);
        return out;
    }

    function activate(result) {
        const d = result?.data;
        if (!d) return;
        if (d.kind === "drill") {
            _setView(d.view);
            return true;
        }
        if (d.kind === "spawn" && d.argv) {
            openExternal(d.argv);
            return;
        }
        if (d.kind === "terminal" && d.argv) {
            openExternal(["xdg-terminal-exec", "--app-id=org.omarchy.terminal"].concat(d.argv));
            return;
        }
        if (d.kind === "present" && d.cmd) {
            openExternal(["omarchy-launch-floating-terminal-with-presentation", d.cmd]);
            return;
        }
    }

    function _setView(v) {
        if (view === v) return;
        view = v;
        currentTitle = _viewTitle[v] || "";
        viewChanged();
    }

    function goBack() {
        if (view !== "") {
            _setView(_viewParent[view] || "");
            return true;
        }
        return false;
    }

    function reset() {
        if (view !== "") {
            view = "";
            currentTitle = "";
        }
    }
}
