<p align="center">
  <img src="wowdot_logo.png" alt="WoWdot logo" width="200">
</p>

# WoWdot

Godot clients for classic World of Warcraft servers.

| Client | Game version | Server | Status |
| --- | --- | --- | --- |
| [WoWGD](clients/wowgd) | 1.12.1 (build 5875) | vMaNGOS | Playable |
| [WrathGD](clients/wrathgd) | 3.3.5a (build 12340) | AzerothCore | Planned |

WoWdot ships no Blizzard data.
Point the client at your own game install.

## Layout

```text
extension/       C++ GDExtension: sessions, crypto, MPQ access and WoW file formats
shared/wowdot/   Addon both clients load; the built libraries land in its bin/
clients/wowgd/   Vanilla client, addons/wowdot links to shared/wowdot
clients/wrathgd/ WrathGD client, addons/wowdot links to shared/wowdot
docs/            Provenance and license audit
website/         Project site, built with website/build.sh into _site/
packaging/       Files that ship inside the release zips
```

The site is plain HTML in `website/`: what works, what is next, and the downloads.
It carries no API reference, so the build is a file copy and needs neither Godot nor the extension.
For the GDScript API locally, run `godot --headless --path clients/wowgd --script res://addons/gddocs/gddocs_cli.gd`, which writes `clients/wowgd/docs/api/index.html`.
`.forgejo/workflows/pages.yml` builds the site on every push to `main`, pushes it to a `pages` branch here and to GitHub Pages.
`.forgejo/workflows/release.yml` builds the Linux and Windows clients on a `v*` tag and attaches the zips to a GitHub release.
Both read `SITE_REPO` at the top of the workflow and a `SITE_TOKEN` secret; the release also needs `GODOT_SCRIPT_ENCRYPTION_KEY`.

## Building

Needs Godot 4.7, SCons and a C++20 compiler.
Every library the extension uses is a submodule and is compiled in, so there are no system packages to install.

```sh
git clone --recursive <repo> WoWdot
cd WoWdot/extension
scons -j"$(nproc)" target=template_debug
```

Windows builds cross-compile with mingw-w64:

```sh
scons -j"$(nproc)" platform=windows target=template_release
```

On Windows, clone with `git config core.symlinks true` (Developer Mode enabled), or copy `shared/wowdot` over each `clients/*/addons/wowdot` link.

## Running

Open `clients/wowgd` in Godot, set **Project Settings > wowgd > client_data_dir** to your 1.12.1 client's `Data` folder, and run.
Exported builds read the `Data` folder next to the executable instead.

## License

WoWdot will be MIT licensed, see [LICENSE](LICENSE), [NOTICE.md](NOTICE.md) and [CONTRIBUTING.md](CONTRIBUTING.md).
