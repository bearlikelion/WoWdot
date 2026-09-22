---
name: WoWdot
description: The project site as the 1.12 character selection screen, a night sky with gold-ruled rows and one lit Enter World button.
colors:
  night: "#070b16"
  indigo: "#0d162b"
  ivory: "#efe8d6"
  ivory-dim: "#b7b3c4"
  gold: "#c9a227"
  gold-deep: "#8d6f12"
  ice: "#6fb6f0"
  ice-deep: "#2f6ea8"
  rule: "rgba(201, 162, 39, 0.45)"
  rule-soft: "rgba(201, 162, 39, 0.18)"
typography:
  display:
    fontFamily: "Grenze, Times New Roman, serif"
    fontSize: "2.4rem"
    fontWeight: 700
    lineHeight: 1
    letterSpacing: "0.01em"
  headline:
    fontFamily: "Grenze, Times New Roman, serif"
    fontSize: "2rem"
    fontWeight: 600
    lineHeight: 1.05
  title:
    fontFamily: "Grenze, Times New Roman, serif"
    fontSize: "1.45rem"
    fontWeight: 600
    lineHeight: 1.1
  body:
    fontFamily: "Alegreya Sans, system-ui, sans-serif"
    fontSize: "17px"
    fontWeight: 400
    lineHeight: 1.55
  label:
    fontFamily: "Grenze, Times New Roman, serif"
    fontSize: "1.15rem"
    fontWeight: 600
    lineHeight: 1.2
    letterSpacing: "0.1em"
  mono:
    fontFamily: "ui-monospace, Cascadia Mono, monospace"
    fontSize: "0.9em"
rounded:
  none: "0"
  chip: "4px"
  icon-sm: "6px"
  icon-md: "8px"
  circle: "50%"
spacing:
  s-1: "4px"
  s-2: "8px"
  s-3: "12px"
  s-4: "16px"
  s-6: "24px"
  s-8: "32px"
  s-12: "48px"
  s-16: "64px"
  s-24: "96px"
components:
  button-enter-world:
    backgroundColor: "{colors.gold}"
    textColor: "#1a1304"
    typography: "{typography.title}"
    rounded: "{rounded.none}"
    padding: "12px 24px"
  button-arrow:
    backgroundColor: "rgba(7, 11, 22, 0.7)"
    textColor: "{colors.gold}"
    rounded: "{rounded.circle}"
    size: "44px"
  button-arrow-hover:
    backgroundColor: "rgba(7, 11, 22, 0.9)"
  roster-row:
    backgroundColor: "transparent"
    textColor: "{colors.ivory}"
    rounded: "{rounded.none}"
    padding: "16px 12px"
  roster-row-hover:
    backgroundColor: "rgba(201, 162, 39, 0.08)"
  roster-row-selected:
    backgroundColor: "linear-gradient(90deg, rgba(201, 162, 39, 0.18), rgba(201, 162, 39, 0.04))"
    textColor: "{colors.gold}"
  roster-row-selected-ice:
    backgroundColor: "linear-gradient(90deg, rgba(111, 182, 240, 0.18), rgba(111, 182, 240, 0.04))"
    textColor: "{colors.ice}"
  chip-class:
    backgroundColor: "rgba(13, 22, 43, 0.9)"
    textColor: "{colors.gold}"
    typography: "{typography.mono}"
    rounded: "{rounded.chip}"
    padding: "4px 12px"
  code-inline:
    backgroundColor: "rgba(13, 22, 43, 0.9)"
    textColor: "{colors.ivory}"
    typography: "{typography.mono}"
    rounded: "{rounded.chip}"
    padding: "1px 6px"
  dot:
    backgroundColor: "transparent"
    rounded: "{rounded.circle}"
    size: "24px"
  dot-on:
    backgroundColor: "{colors.gold}"
---

# Design System: WoWdot

## Overview

**Creative North Star: "Character Select"**

The site is the 1.12 character selection screen.
The two clients are the characters on the list, each with its status, expansion and server where the game prints level, class and zone, and Enter World is the download.
The first viewport is a night sky, deep indigo falling to black under a sparse drawn star field, with the selected client's screenshot standing in the model slot at full height and a gold-ruled roster on the right.

Everything on the screen is drawn in CSS: the star field is an inline SVG tile, the frames are hairlines, the arrows are stroked paths.
There are no textures, no Blizzard art, no borrowed frames.
Below the fold the screen becomes a character sheet: one full-width column of gold-ruled sections in which prose runs the full width with no measure cap, a decision the author pinned.
The voice is plain and factual and the visual system follows it; the only lit control on the page is the gold Enter World button.

The world is dark only.
There is no light theme and none is planned; the glue screen is a night scene and a light variant would not be the same screen.

**Key Characteristics:**
- Night ground: indigo to black gradient with a drawn star tile, never a flat fill.
- One gold for rules, the primary action and WoWGD; ice blue reserved for WrathGD.
- Gold hairline rules at two alphas do all the framing; there are no shadows and no filled panels.
- Grenze display at 600 and 700 over Alegreya Sans body at 17px.
- One motion: a 300ms fade through the night when the selection or the carousel changes.

## Colors

A night palette of two darks and two lights, with one gold that does all the work and one ice blue that belongs to a single character.

### Primary
- **Gold** (`{colors.gold}`): the realm name, zone name, sheet headings, the selected WoWGD row's name and frame, the Enter World fill, hover on links, the focus ring, text selection, the carousel arrows and dots, and the class chip text.
- **Gold Deep** (`{colors.gold-deep}`): the one pixel border on the Enter World button so the flat gold slab has an edge against the night.
- **Rule** (`{colors.rule}`): gold at 45% alpha, the drawn hairline for the double rule, the arrow ring, the empty slot frame, the blockquote bar, the class chip border and link underlines.
- **Rule Soft** (`{colors.rule-soft}`): gold at 18% alpha, the row divider, the facts row divider and the inline code border.

### Secondary
- **Ice** (`{colors.ice}`): WrathGD only, on its status word, and on its row name and frame when it is the selected character.
- **Ice Deep** (`{colors.ice-deep}`): declared for WrathGD's darker step; the current page does not reach for it.

### Neutral
- **Night** (`{colors.night}`): the page background and the bottom of the glue screen gradient; also the text colour on a gold selection.
- **Indigo** (`{colors.indigo}`): the middle of the glue screen gradient, the inline code and chip fill at 90% alpha, and the cut-outs in the Linux mark.
- **Ivory** (`{colors.ivory}`): body text, links, row names, facts terms and the stars.
- **Ivory Dim** (`{colors.ivory-dim}`): the tagline, subtitles, section labels, roster heading, class and zone lines, facts values, muted paragraphs, the blockquote, the build line and the footer.

### Named Rules
**The One Gold Rule.** Gold is the only accent on the page; ice appears only on WrathGD's status word and its selected row, never on rules, buttons or headings.
**The Hairline Rule.** Frames are one pixel of gold at 45% or 18% alpha; a solid gold border means the element is selected.
**The Night Only Rule.** There is no light theme; every surface sits on night or indigo and text is ivory.

## Typography

**Display Font:** Grenze 600 and 700 (with Times New Roman, serif), loaded from Google Fonts
**Body Font:** Alegreya Sans 400, 500, 700 and 400 italic (with system-ui, sans-serif), loaded from Google Fonts
**Label/Mono Font:** ui-monospace, Cascadia Mono, monospace for code and class chips

**Character:** Grenze is a roman with a point of view that reads as the glue screen's engraved names; Alegreya Sans is a humanist sans that keeps the facts plain and quick to read at 17px.

### Hierarchy
- **Display** (700, 2.4rem, 1, 0.01em tracking, gold): the realm name WoWdot beside the mark, once.
- **Headline** (600, 2rem, 1.05, gold): the sheet section titles below the fold.
- **Zone** (600, 1.6rem, 1.15, gold): the zone name under the model slot, read from the screenshot filename.
- **Title** (600, 1.45rem, 1.1, ivory, gold or ice when selected): the row name in the roster; 1.3rem under 900px.
- **Button** (700, 1.35rem, 1.2, 0.06em tracking, uppercase): Enter World only.
- **Label** (600, 1.15rem, 1.2, 0.1em tracking, uppercase, ivory dim): sheet subheadings such as What's in, Install, Next.
- **Roster label** (600, 1.05rem, 1, 0.12em tracking, uppercase, ivory dim): the Characters heading over the list.
- **Body** (400, 17px, 1.55, ivory): everything else; prose runs the full column width with no measure cap.
- **Small** (0.95rem for row class and zone lines and platform links, 0.9rem for the build line and footer): secondary lines in ivory dim.
- **Mono** (0.9em): inline code and the extension class chips.

### Named Rules
**The Grenze Names Rule.** Grenze is for names and headings only: the realm, the zone, the characters, the sections and the one button; it never sets running text.
**The Full Width Rule.** Sheet prose runs the full 1040px column; do not add a paragraph measure cap.

## Layout

The glue screen is the first viewport: a 100vh grid with a 640px minimum, two columns at 62fr and 38fr with a 48px gutter, padded 32px top, 48px sides and 24px bottom.
The left column stacks the realm mark and name, the model slot centred in the remaining height, and the build line at the bottom.
The right column is the roster, vertically centred, holding the Characters heading, the double-ruled list and the Enter World block.
The model slot fills the column and its screenshot fits inside with a radial mask that fades its edges into the night.

Below the fold, main and footer share a 1040px column centred with 24px side padding.
Each sheet section is padded 64px top and bottom and opens with a double gold rule.
Inside a sheet, two-column blocks and the facts grid split 1fr 1fr with a 48px gutter; the facts grid gives its terms an 8.5em column.

Spacing is a 4px scale from 4px to 96px (--s-1 to --s-24); the working steps are 12px for inner gaps, 16px for row padding, 24px for block margins, 32px for section heads and 48px for gutters and column gaps.

Under 900px the glue screen becomes one column ordered realm, model, roster, build, its height released to auto, padded 24px and 16px.
The model slot becomes a 16:9 box at full width, row padding drops to 12px, sheet padding to 48px, and every two-column grid collapses to one with facts terms at 7em.

## Elevation & Depth

There are no shadows anywhere in the system.
Depth is carried by the night gradient, the star field and gold hairlines; the selected row lifts by a horizontal gold gradient from 18% to 4% alpha and a solid gold frame.
The carousel arrows sit on the screenshot as translucent night discs at 70% alpha, deepening to 90% on hover.
The screenshot's radial mask dissolves its edges so the capture sits in the night rather than on it.

### Named Rules
**The No Shadow Rule.** Nothing casts a shadow; if an element needs to separate from the ground, frame it with a gold hairline or a translucent night fill.

## Shapes

Square by default.
Buttons, rows, rules, sheets, the blockquote and the empty slot have no radius; Enter World is a flat gold slab.
The circle is the exception and belongs to the carousel: 44px arrow discs and 10px dots in 24px hit boxes.
Small radii appear on marks and code only: 4px on inline code and class chips, 6px on the 40px roster icons, 8px on the 48px sheet-head icons.
Rules are one pixel; the double rule is two hairlines three pixels apart.

## Components

### Buttons
- **Shape:** square (0 radius), one pixel gold-deep border.
- **Primary (Enter World):** gold fill, near-black text (#1a1304), Grenze 700 at 1.35rem uppercase with 0.06em tracking, padded 12px 24px, block width of the roster column.
- **Hover:** lifts 1px and brightens 8% over 200ms with the ease-out curve cubic-bezier(0.22, 1, 0.36, 1).
- **Locked:** when the selected client is not playable the button drops to 35% opacity and full grayscale, the platform links hide and a one-line notice takes their place.
- **Platform links:** under the button, Windows and Linux with 16px inline SVG marks in ivory at weight 500, then every release on GitHub as an ivory dim text link.

### Carousel arrows
- **Shape:** 44px circle, one pixel rule border, night fill at 70% alpha.
- **Glyph:** a 20px stroked chevron in gold, stroke 2 with round caps, inline SVG.
- **Hover:** border turns solid gold and the fill deepens to 90% over 200ms.
- **Placement:** on the model slot's left and right edges with a 12px inset; hidden when a client has fewer than two shots.

### Dots
- **Style:** 24px hit box around a 10px gold-ringed disc, 4px apart, centred under the caption.
- **State:** the current dot fills gold; dots hide when there is a single shot.

### Roster rows
- **Shape:** full-width square button, padded 16px 12px, 12px gap between the 40px icon and the text stack, an 18% gold hairline beneath.
- **Text:** name in Grenze 600 at 1.45rem, status word in the client colour at weight 700, expansion and server lines in ivory dim at 0.95rem.
- **Hover:** gold wash at 8% alpha over 200ms; the WrathGD row washes ice at 8%.
- **Selected:** a horizontal client-colour gradient from 18% to 4% alpha, a solid one pixel frame top and bottom in the client colour, and the name set in that colour; gold for WoWGD, ice for WrathGD.
- **Keys:** up and down move the selection, Enter fires Enter World on a playable client.

### Double rule
- **Style:** a one pixel gold rule at 45% alpha with a second hairline three pixels below it, drawn with a border and a pseudo element.
- **Use:** the top of the roster list, the top of every sheet section and the top of the footer.

### Sheet sections
- **Shape:** full-width, no fill, no border but the double rule above, padded 64px top and bottom.
- **Head:** a 48px icon at 8px radius beside a gold Grenze headline and an ivory dim subtitle line.
- **Subheadings:** uppercase Grenze labels in ivory dim with 0.1em tracking, 32px above and 12px below.

### Facts grid
- **Style:** a definition list in two columns with a 48px gutter; each entry is a term column at 8.5em in ivory 700 and a value in ivory dim, padded 8px vertically with an 18% gold hairline beneath.

### Class chips
- **Style:** inline code at 0.9em in a monospace stack, gold text on indigo at 90% alpha, one pixel rule border at 45% alpha, 4px radius, padded 4px 12px, wrapping with 8px gaps.
- **State:** static; no hover or selection.

### Inline code
- **Style:** the same indigo fill with an 18% rule border, ivory text, 4px radius, padded 1px 6px.

### Blockquote
- **Style:** a one pixel gold rule at 45% on the left, 16px inset, ivory dim text, 16px margins above and below.

### Links
- **Style:** ivory text with a 1px underline in the 45% gold rule, offset 3px.
- **Hover:** text and underline turn gold.

### Model slot
- **Style:** the selected client's screenshot fitted inside the column with a radial mask (ellipse 82% by 80% at 50% 48%, solid to 45%, transparent at the edge).
- **Empty:** a 34ch notice in ivory dim, 24px padding, framed by a one pixel rule at 45%.
- **Caption:** the zone name in gold Grenze 600 at 1.6rem, a subtitle in ivory dim, then the dots.
- **Motion:** any change of selection or step fades the slot's contents to zero opacity over 300ms on cubic-bezier(0.22, 1, 0.36, 1), repaints, and fades back; the carousel steps every seven seconds and pauses while the pointer or focus is inside; under reduced motion there is no auto-advance and no fade.

### Focus and selection
- **Focus:** every focusable element takes a 2px solid gold outline offset 3px.
- **Selection:** highlighted text is night on gold.

## Do's and Don'ts

### Do:
- **Do** ground every surface on the night gradient or the night fill; the star tile belongs to the glue screen only.
- **Do** frame with gold hairlines at 45% or 18% alpha and mark selection with a solid gold or ice frame.
- **Do** keep gold on rules, headings, the primary action and WoWGD; give WrathGD ice on its status word and selected row and nowhere else.
- **Do** set names and headings in Grenze and everything else in Alegreya Sans at 17px on 1.55.
- **Do** use the single 300ms fade through the night for any content swap, and disable it and the seven second auto-advance under reduced motion.
- **Do** keep the 2px gold focus ring at 3px offset on every interactive element.
- **Do** draw every ornament in CSS or inline SVG.

### Don't:
- **Don't** add a light theme; the world is a night scene.
- **Don't** cast shadows or fill panels; the system is hairlines on night.
- **Don't** cap paragraph measure; sheet prose runs the full column width.
- **Don't** put ice on anything but WrathGD, or a second accent anywhere.
- **Don't** round buttons, rows or sheets; radius belongs to icons, code chips and the carousel circles only.
- **Don't** use Blizzard frames, textures or art as ornament; screenshots are the only game imagery.
- **Don't** add motion beyond the fade and the row highlight.
