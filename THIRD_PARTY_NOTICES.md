# Third-party notices

Till has no third-party code dependencies. It bundles one third-party artwork asset and
fetches others at the user's request.

## Menu-bar glyph

- **Asset:** `seedling` from Font Awesome 5 Solid (Iconify id `fa-solid:seedling`), embedded in
  `Sources/Till/Views/BarGlyph.swift`.
- **Author:** Dave Gandy, Font Awesome (https://github.com/FortAwesome/Font-Awesome).
- **License:** Creative Commons Attribution 4.0 International (CC BY 4.0),
  https://creativecommons.org/licenses/by/4.0/. The glyph was recoloured (white fill) and
  rasterized; no other change to the shapes.
- **Source of the data:** the `@iconify-json/fa-solid` package (version 1.2.2, Font Awesome 5.15.4).

CC BY 4.0 requires attribution. Before shipping a build, surface this credit where users can
find it (for example an About line or the download page); the repository file alone does not
satisfy it for people who only have the app.

## Icons fetched from Iconify

Icons a user picks are fetched from the public Iconify API at chip creation and cached on the
user's Mac. Each icon set has its own license, shown in the picker when the icon is chosen.
