// NativeWind v4.x consumes Tailwind v3-style config. Tokens are auto-generated
// from app/frontend/styles/themes/sway.css via scripts/extract_sway_tokens.mjs;
// keep this file aligned with that emitter.
const { swayTokens } = require("./src/theme/tokens");

const dual = (lightKey, darkKey = lightKey) => ({
    light: swayTokens.light[lightKey],
    dark: swayTokens.dark[darkKey],
});

module.exports = {
    content: ["./src/**/*.{ts,tsx}", "./App.tsx"],
    presets: [require("nativewind/preset")],
    darkMode: "class",
    theme: {
        extend: {
            colors: {
                // 60-30-10 surface roles (UI-SPEC §Color)
                dominant: dual("background"),
                secondary: dual("secondary"),
                accent: dual("primary"),
                destructive: dual("destructive"),
                foreground: dual("foreground"),
                "muted-foreground": dual("mutedForeground"),
                border: dual("border"),
                "border-soft": dual("borderSoft"),
                "vote-for": dual("voteFor"),
                "vote-against": dual("voteAgainst"),
                "surface-3": dual("surface3"),
                warning: "#ffd600",

                // NEW — Phase 33 PARITY-02 — register the 19 missing v2 tokens.
                // Each entry uses the existing dual() helper from line 6.
                card: dual("card"),
                "card-foreground": dual("cardForeground"),
                popover: dual("popover"),
                "popover-foreground": dual("popoverForeground"),
                "primary-foreground": dual("primaryForeground"),
                "secondary-foreground": dual("secondaryForeground"),
                muted: dual("muted"),
                "accent-foreground": dual("accentForeground"),
                "border-strong": dual("borderStrong"),
                input: dual("input"),
                ring: dual("ring"),
                success: dual("success"),
                "success-foreground": dual("successForeground"),
                "warning-foreground": dual("warningForeground"),
                info: dual("info"),
                "info-foreground": dual("infoForeground"),
                "surface-1": dual("surface1"),
                "surface-2": dual("surface2"),
                // `highlight` registers the yellow --accent token without colliding with the
                // existing `accent` key which is intentionally mapped to `primary` (blue CTA).
                // See 33-UI-SPEC.md §Color "Note on token naming ambiguity".
                highlight: dual("accent"),
            },
            fontFamily: {
                // PostScript names — see UI-SPEC Font Loading Contract.
                "open-sans-light": ["OpenSans-Light"], // weight-300 body (D-07)
                "open-sans": ["OpenSans-Regular"],
                "open-sans-semibold": ["OpenSans-SemiBold"],
            },
            fontSize: {
                xs: ["12px", { lineHeight: "1.5" }],
                sm: ["14px", { lineHeight: "1.4" }],
                base: ["16px", { lineHeight: "1.5" }],
                lg: ["18px", { lineHeight: "1.4" }],
                xl: ["20px", { lineHeight: "1.25" }],
                "2xl": ["24px", { lineHeight: "1.25" }],
                "3xl": ["30px", { lineHeight: "1.2" }],
            },
            borderWidth: {
                DEFAULT: "1px", // standard Sway border (--rule-hair / --rule-mid)
                calm: "1px", // flat/no-emphasis variant
                // NOTE: border-2 uses Tailwind's built-in width key (2px); no custom thick key needed
            },
            borderRadius: {
                DEFAULT: "6px", // --radius: 6px (Bootstrap)
                sm: "4px", // --radius-sm (badges, chips)
                md: "5px", // --radius-md (inputs — legacy custom value)
                lg: "6px", // large cards (same as default)
                xl: "6px", // keep name for compat; was 18.4px
                card: "6px", // all Card primitives (was 17.6px — visible change)
                full: "9999px", // pill shape — unchanged
                // NOTE: do NOT register 2xl here — rounded-t-2xl (16px) is a deliberate
                // iOS sheet-handle idiom on AuthPromptSheet/DestructiveSheet ([platform] D-06)
            },
            // IMPORTANT: do NOT add a shadow key here. NW4 does not translate CSS
            // box-shadow to RN shadow* props (Pitfall 1). Shadow is applied via
            // style={shadowBold(colorScheme)} from src/theme/effects.ts.
        },
    },
    plugins: [],
};
