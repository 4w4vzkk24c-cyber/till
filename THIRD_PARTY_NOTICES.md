# Third-party notices

Till has no third-party code dependencies. It bundles third-party icon artwork and fetches
more at the user's request.

## Bundled icons (offline defaults)

Embedded as SVG in `Sources/Till/Views/BundledIconCatalog.swift` and `BarGlyph.swift`.
Data taken from the `@iconify-json/*` packages on 2026-11-03. Monotone icons were recoloured
white so they can be tinted; the shapes are unchanged.

| Icon | Set | Author | License |
|---|---|---|---|
| `hugeicons:bio-energy` (default chip icon) | Huge Icons | Hugeicons | MIT |
| `withicons:peacock-feather-sketch` | with icons | Evergrow | MIT |
| `at-icons:lightning-bolt` | @icons | Valentin Fossati | MIT |
| `emojione-monotone:tomato` | Emoji One (Monotone) | Emoji One | CC BY 4.0 |
| `logos:claude-icon`, `logos:openai-icon`, `logos:z-ai`, `logos:opencode-icon`, `logos:ollama` | SVG Logos | Gil Barbara | CC0 1.0 |
| `fa-solid:seedling` (menu-bar glyph) | Font Awesome 5 Solid | Dave Gandy, Font Awesome | CC BY 4.0 |

- **Attribution needed before shipping.** CC BY 4.0 (Emoji One, Font Awesome) requires credit to
  the author, and MIT (Hugeicons, with icons, @icons) requires the copyright and permission
  notice to accompany copies. The repository file alone does not satisfy either for people who
  only have the app: surface these credits where users can find them (for example an About line
  and the download page) and include the MIT license texts.
- **Company marks.** The Claude, OpenAI, Z.ai, opencode and Ollama logos are trademarks of their
  owners. The SVG Logos collection is CC0 for the artwork, which does not grant any trademark
  rights. Using them here, as icons a person picks to stand for a timer, is the operator's call.

## Icons fetched from Iconify

Icons a user picks are fetched from the public Iconify API at chip creation and cached on the
user's Mac. Each icon set has its own license, shown in the picker when the icon is chosen.
