---
version: 1
slug: "index-html"
primary_target: "index.html"
related_targets: []
---

# Surface brief: website/index.html

Scope: the project site's one page. Visitor mode: Persuade.
Audience: private server players who hold a 1.12.1 client and a realmlist; success is that they leave convinced the work is real and deep, and download WoWGD.
Proof on hand: the Northshire capture; more screenshots the author drops into website/wowgd/ and website/wrathgd/, listed by screenshots.sh into screenshots.json at build time; the feature list kept, compressed.
Constraints: no pitch or marketing lines, facts only (user pinned); WoWGD is gold and WrathGD is ice blue (user pinned); copy and facts preserved; logo and client icons kept as marks; no Blizzard art or frames, every ornament drawn here; credit reads Mark Arneman (bearlikelion) linking to github.com/bearlikelion.
Unresolved: whether a light theme is wanted (the glue screen is a night scene, so the build is dark only).

## Direction contract

THESIS: The site is the character selection screen. The two clients are the characters on the list, each with its level, class and zone (status, expansion, server), and Enter World is the download. It refuses the dark hero with a screenshot thumbnail and a feature table under it.

OWN-WORLD: A night sky ground, deep indigo falling to black with a sparse drawn star field; one gold (#c9a227) for rules, the primary action and WoWGD; ice blue (#6fb6f0) for WrathGD, pinned by the user, so each client keeps its own colour on its status word and on its row when chosen; ivory text. The list is a right-hand panel of gold-ruled rows. Display type is Grenze, a roman with a point of view; body is Alegreya Sans. Panels are bounded by thin double gold rules drawn in CSS, no textures. With the content removed, the gold-ruled right column on indigo still says glue screen.

STORY: The visitor recognises the screen in a second, reads two characters, sees WoWGD at the top ready to play and WrathGD low on the list, and presses Enter World to download. Scrolling opens the character sheet: what is in, what is left, the extension underneath, the author.

FIRST VIEWPORT: 100vh, two regions. Left 62%: the model slot, a carousel of the selected client's screenshots (the Northshire capture first) at full height fading into the night at its edges, with gold arrows on the slot's edges and dots under the caption when there is more than one; the zone name in gold beneath it, read from the filename, as the glue screen prints it. A client with no screenshots shows a labelled empty slot. Top left: the WoWdot mark and name at realm-name scale. Right 38%: the character list: row one WoWGD, Vanilla 1.12.1 (5875), vMaNGOS, Playable, selected in gold; row two WrathGD, Wrath of the Lich King 3.3.5a (12340), AzerothCore, In development. Under the list: Enter World as the primary gold button (download for Windows and Linux beneath it, every release on GitHub as a text link). Bottom left, where the client prints its build: Made by Mark Arneman (bearlikelion). Signature interaction: selecting a row swaps the model slot and the facts beneath it with one fade through black, 300ms ease-out; up and down arrows move the selection, left and right step the carousel, Enter fires Enter World; the carousel advances every seven seconds, pausing under the pointer and never under reduced motion. Motion grammar: that one fade and a gold row highlight, nothing else moves.

FORM: Character Select, position 1 on the grounded list, presented as the pick and chosen over the assigned Godot editor direction; seed key ceec5efa.

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance.
