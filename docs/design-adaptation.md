# HOTWM design adaptation

HOTWM applies the Fried's Retro Gaming Skills palette to its native Windows WPF dashboard. The dashboard merges `gui/HotwmTheme.xaml`; its window-level resource styles use those tokens across the setup, device, output, profile, layout, tuning, and log views. The palette keeps surfaces dark and neutral, using green for the primary action/success, gold for warnings, and red for danger.

The theme resource dictionary defines three layers:

1. **Primitive colors:** Night `#0E1B23`, Cream `#F6F2E9`, Pixel Green `#3DDC84`, Retro Red `#FF4B3A`, Crown Gold `#FFC857`, and supporting blue-gray surface, border, and muted-text colors.
2. **Semantic brushes:** background, surface, elevated surface, text, muted text, border, accent, and success/warning/danger status brushes.
3. **Reusable styles:** named styles in the theme plus window-scoped WPF styles for text, groups, buttons, tabs, inputs, selectors, and data grids. Controls use semantic brushes rather than repeating palette values.

Segoe UI is the body/control face; Georgia is used sparingly for the brand heading. They are installed system fonts. The dashboard loads its mascot PNGs from `gui/assets/brand` using local file paths. There are no remote image/font requests or external visual dependencies, so these assets work offline. The SVG artwork remains alongside the PNGs as editable source.

The friendly mascot is the persistent brand mark. The controller mascot accompanies the device-assignment guidance. The surprised mascot appears for invalid folder selection or setup errors and is cleared when setup dispatch begins again. The celebrate mascot appears only when every required manual check has a current user attestation. Its message explicitly says those checks are not independently verified and do not guarantee game functionality; celebration is not a device-readiness signal.

The visual adaptation is native 2D WPF. No 3D scene, renderer, animation framework, webfont, or additional runtime is bundled.
