<p align="center">
  <img src="wowdot_logo.png" alt="WoWdot logo" width="200">
</p>

# WoWdot

Godot clients for classic World of Warcraft servers.

| Client | Game version | Server | Status |
| --- | --- | --- | --- |
| [WoWGD](clients/wowgd) | 1.12.1 (build 5875) | vMaNGOS | Playable |
| [WrathGD](clients/wrathgd) | 3.3.5a (build 12340) | AzerothCore | Walks around |

WoWdot ships no Blizzard data.
Point the client at your own game install; each client reads the data for its own game version.

`shared/game/` is one folder of GDScript symlinked in as `game/` by both clients, so `res://game/...` resolves the same in each while the data folder, the expansion setting and the client's own `Data` directory stay per client.

## Layout

```text
extension/       C++ GDExtension: sessions, crypto, MPQ access and WoW file formats
shared/wowdot/   Addon both clients load; the built libraries land in its bin/
shared/game/     GDScript both clients load: the interface, world and gameplay
clients/wowgd/   Vanilla client; game and addons/wowdot link into shared/
clients/wrathgd/ WrathGD client; game and addons/wowdot link into shared/
docs/            Provenance and license audit
website/         Project site, built with website/build.sh into _site/
packaging/       Release zip contents and publish.sh
```

The site is plain HTML in `website/`: what works, what is next, and the downloads.
It carries no API reference, so the build is a file copy and needs neither Godot nor the extension.
For the GDScript API locally, run `godot --headless --path clients/wowgd --script res://addons/gddocs/gddocs_cli.gd`, which writes `clients/wowgd/docs/api/index.html`.
`.forgejo/workflows/pages.yml` builds the site on every push to `main`, pushes it to a `pages` branch here and to GitHub Pages.
It reads `SITE_REPO` at the top of the workflow and a `SITE_TOKEN` secret.
Releases are not built in CI: `packaging/publish.sh <tag>` zips the local export and attaches it to a GitHub release with `gh`.
The presets encrypt the pck, and only export templates compiled with the key can load one, so the build has to come from the machine that has them.

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

## Thanks

[WoWee](https://github.com/Kelsidavis/WoWee), [wowdev.wiki](https://wowdev.wiki/Main_Page) and [benilla](https://github.com/samwhosung/benilla), a from-scratch 1.12.1 client in Rust and Bevy.

## License

WoWdot will be MIT licensed, see [LICENSE](LICENSE), [NOTICE.md](NOTICE.md) and [CONTRIBUTING.md](CONTRIBUTING.md).
