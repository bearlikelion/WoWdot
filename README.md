<p align="center">
  <img src="wowdot_logo.png" alt="WoWdot logo" width="200">
</p>

# WoWdot

Open-source Godot clients for classic World of Warcraft servers.

| Client | Game version | Server | Status |
| --- | --- | --- | --- |
| [WoWGD](clients/wowgd) | 1.12.1 (build 5875) | vMaNGOS | Playable |
| [WotLKGD](clients/wotlkgd) | 3.3.5a (build 12340) | AzerothCore | Scaffold |

WoWdot ships no Blizzard data.
Point the client at your own game install.

## Layout

```text
extension/       C++ GDExtension: sessions, crypto, MPQ access and WoW file formats
shared/wowdot/   Addon both clients load; the built libraries land in its bin/
clients/wowgd/   Vanilla client, addons/wowdot links to shared/wowdot
clients/wotlkgd/ WotLK client, addons/wowdot links to shared/wowdot
docs/            Provenance and license audit
website/         Project site, built with website/build.sh into _site/
```

The site includes a GDDocs API reference for each client.
GitHub Pages deploys it from `.github/workflows/pages.yml`, and Forgejo pushes it to a `pages` branch from `.forgejo/workflows/pages.yml`.

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
