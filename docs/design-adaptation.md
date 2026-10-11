# HOTWM theme adaptation

HOTWM adapts the Fried's Retro Gaming Skills palette to a dense Windows setup
dashboard. Night is the application background, cream carries primary text,
and restrained neutral blue-greys separate panels. Pixel green marks the main
action and success state; crown gold marks warnings; retro red is reserved for
danger. Most of the interface remains neutral, keeping status and action colors
meaningful.

The resource dictionary at `gui/HotwmTheme.xaml` uses three token levels:

1. **Primitives** name the five brand colors and the neutral shades needed for
   readable dark surfaces.
2. **Semantic brushes** express purpose: `BackgroundBrush`, `SurfaceBrush`,
   `ElevatedBrush`, `TextBrush`, `MutedTextBrush`, `BorderBrush`, `AccentBrush`,
   and the three `Status*Brush` values.
3. **Component styles** are explicitly keyed (`HotwmCardStyle`,
   `HotwmPrimaryButtonStyle`, and related names). They consume semantic brushes
   and do not impose implicit styles on the existing dashboard.

Georgia provides an editorial serif for occasional headings; Segoe UI is the
body and control face. Both are system fonts. The theme adds no font files,
external font requests, motion framework, or 3D runtime. The dictionary is an
opt-in foundation; existing dashboard colors remain unchanged until a separate
UI integration pass adopts these resources.
