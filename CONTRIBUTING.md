# Contributing

By submitting a contribution you agree that:

- it is licensed under the project's [MIT License](LICENSE);
- you have the right to submit it;
- it contains no Blizzard code, assets, database content or other material you are not authorized to share;
- it may be reused in open-source or commercial projects, with notices preserved.

Do not copy code from vMaNGOS, AzerothCore or any other GPL project into this repository.
Reading them to understand the protocol is fine.

Do not copy code from WoWee releases after `v2.0.28-preview`; later versions carry a different license.

## Style

GDScript follows the Godot style guide with explicit static types, tabs and `%UniqueName` access for UI nodes.
C++ under `extension/src/` builds with `-Wall -Wextra -Wpedantic -Wshadow`; vendored code keeps its upstream style.
