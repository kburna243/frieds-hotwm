# HOTWM brand assets

These files bring the friendly mascot direction from the local Fried's Retro
Gaming Skills source project into the HOTWM desktop interface. Source files are
kept intact; the PNGs are raster renderings of those SVGs for WPF image use.

## Character artwork

Source directory: `I:\claude-system\data\projects\frieds-retrogaming-skills\assets`

| State | Source SVG / SHA-256 | WPF PNG | PNG details |
| --- | --- | --- | --- |
| Friendly | `character-friendly.svg` — `09583E0AC4AAFC2D1F50CAD855CC3E3F7A5B5377536107F0025CF602B9E2B3F3` | `gui/assets/brand/character-friendly.png` | 960 × 960, RGBA, transparent |
| Controller | `character-controller.svg` — `0BD498E01B3CBFCACC02ED8802AEC30152F5D9415027DA0A2FDC44539BBFA734` | `gui/assets/brand/character-controller.png` | 960 × 960, RGBA, transparent |
| Celebrate | `character-celebrate.svg` — `3C12F8B97DE7AD986BF9F2FE6B96FD203168D127639EBF5410A9FD3FEF6A4582` | `gui/assets/brand/character-celebrate.png` | 960 × 960, RGBA, transparent |
| Surprised | `character-surprised.svg` — `E1269B5388EBA5EEB5D5CD00AAA46E3CDE95437B94CB46A934C2FE2E43970410` | `gui/assets/brand/character-surprised.png` | 960 × 960, RGBA, transparent |

The SVGs in `gui/assets/brand/` are byte-for-byte copies of the listed source
files. Each PNG is rendered from its corresponding local SVG; there is no
redrawing or remote asset dependency.

## Repeating the SVG-to-PNG conversion

The PNGs were rendered offline with Microsoft Edge 155.0.4283.45, Chromium's
headless screenshot renderer. The SVG's `viewBox` is 240 × 240. A 480 × 480 CSS
viewport at device scale factor 2 produces the 960 × 960 output. The renderer
uses a transparent page background and loads only a local `file:///` SVG.

From PowerShell, set `$edge` to the installed `msedge.exe`, `$svg` to an
absolute source SVG path, `$png` to the desired output path, and `$profile` to
a fresh temporary directory, then run:

```powershell
& $edge --headless=new --disable-gpu --disable-extensions --hide-scrollbars `
  --window-size=480,480 --force-device-scale-factor=2 `
  --default-background-color=00000000 "--user-data-dir=$profile" `
  "--screenshot=$png" ([Uri]::new($svg).AbsoluteUri)
```

The source design system names Playfair Display and Inter. This asset package
does not bundle fonts; use the existing system font stack (Georgia and Segoe
UI) so the GUI remains offline and does not redistribute font files.

## Design source

[`design.md`](design.md) is copied from the source project's
`assets/design.md`; its opening note records provenance and explains that HOTWM
adapts the design direction to the existing Windows interface.

## 3D mascot source and limits

The source project has a procedural Three.js implementation, not a standalone
model file. Its files and SHA-256 hashes are:

| Source file | SHA-256 |
| --- | --- |
| `mascot-3d/RetroMascot.js` | `E42D8EF6AB8B04C28C0CA3305ABA58E5F4E2C7870E6A361914491AB92D56A42B` |
| `mascot-3d/index.html` | `D6CC954AEE90D84E8D8A528921CFA6FB6720C8C22E3E4FDEE7D10735479267A3` |
| `mascot-3d/sculpt-spec.json` | `3297FEA27E0A6761ADB910AEB28C36F82E23247D8EC887557BFC6FBDAC724BFC` |
| `mascot-3d/analysis.md` | `A16FC7537C4FD13CDA89A9085AD0A16491E2940CF3FE2ED0A694DE56452304E2` |

`RetroMascot.js` constructs the scene from Three.js primitives. The source
HTML imports Three.js from `https://unpkg.com/three@0.160.0/`; there is no local
Three.js package or GLB/GLTF model in the source asset directory. Since a
network-free render could not load that dependency, this package deliberately
does not include a purported 3D still. The original code and sculpt
specification remain the references if a faithful offline render pipeline is
added later.
