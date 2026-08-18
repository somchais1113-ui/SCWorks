# SC Drive Production Font Policy

## Required production typography

SC Drive production builds must use the protected Nissan Brand typography supplied by the project owner.

Runtime family:

- `NissanBrand` weight 400: Nissan Brand Regular
- `NissanBrand` weight 700: Nissan Brand Bold

Thai UI must remain available in the packaged font set. The current production finalization uses IBM Plex Sans Thai glyph coverage merged into the NissanBrand runtime files so the global `NissanBrand` theme can render Thai without system-font dependence.

## Production guardrails

1. Do not ship DejaVu Sans or another placeholder under the `NissanBrand` asset names.
2. Do not depend on fonts installed on the Android head unit.
3. Both NissanBrand font files must be physically embedded in `assets/flutter_assets/assets/fonts/` in the APK.
4. `FontManifest.json` must register NissanBrand weight 400 and 700.
5. The packaged regular and bold files must contain Thai Unicode coverage for the application's Thai UI. Current validation target: 87 Thai code points in U+0E00–U+0E7F.
6. Preserve OpenType shaping tables required by Thai text (`GDEF`, `GPOS`, `GSUB`).
7. The protected Nissan font binaries must not be committed to a public repository. Production finalization must obtain them from the project owner's protected/user-supplied asset source or a controlled production artifact.
8. A production build must fail final QA if a placeholder font is detected.

## Speed cluster requirement

The digital speed cluster must support three-digit values through the current 0–240 km/h display range.

Preserve these UI safeguards:

- `_digitalSpeed` supports values up to 240.
- At `>= 100 km/h`, use the three-digit font sizing branch.
- Keep the fixed speed-display box large enough for three digits.
- Keep `FittedBox(fit: BoxFit.scaleDown)` around the speed text.
- Keep tabular figures enabled.
- Do not truncate, wrap, or replace `100–240` with two-digit output.

## Production finalization checklist

Before signing a release APK:

- verify real Nissan Brand metadata in the packaged regular/bold font assets;
- verify Thai cmap coverage;
- verify `GDEF`, `GPOS`, and `GSUB` are present;
- verify `FontManifest.json` references both NissanBrand weights;
- verify the speed cluster still contains its `>= 100` sizing branch, 240 km/h clamp, and `BoxFit.scaleDown` behavior;
- verify the production Google Maps key and permanent signing identity remain unchanged;
- verify the final APK after font injection/signing, not only the pre-finalization candidate.

This policy exists specifically to prevent future SC Drive development from silently reverting to placeholder fonts or breaking the three-digit speed display.
