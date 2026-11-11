// @lat: [[theme-test-suite-silent-failure-guards#Colour notation: one shared module for two gates that used to disagree]]

/**
 * Every notation, whether this file can turn it into a hex triple, and the name
 * to print when it cannot.
 *
 // @lat: [[theme-test-suite-silent-failure-guards#Colour notation: one shared module for two gates that used to disagree#Why NOTATIONS' order matters, and why rgba() is recognised but unmeasurable]]
 */
const NOTATIONS: ReadonlyArray<{ name: string; pattern: RegExp; convertible: boolean }> = [
    { name: "6-digit hex", pattern: /^#[0-9a-fA-F]{6}$/, convertible: true },
    { name: "rgb()", pattern: /^rgb\(/, convertible: true },
    { name: "rgba()", pattern: /^rgba\(/, convertible: false },
    { name: "3-digit hex", pattern: /^#[0-9a-fA-F]{3}$/, convertible: false },
    { name: "4-digit hex", pattern: /^#[0-9a-fA-F]{4}$/, convertible: false },
    { name: "8-digit hex", pattern: /^#[0-9a-fA-F]{8}$/, convertible: false },
    { name: "hsl()", pattern: /^hsla?\(/, convertible: false },
    { name: "oklch()", pattern: /^oklch\(/, convertible: false },
    { name: "oklab()", pattern: /^oklab\(/, convertible: false },
    { name: "lab()", pattern: /^lab\(/, convertible: false },
    { name: "lch()", pattern: /^lch\(/, convertible: false },
    { name: "color()", pattern: /^color\(/, convertible: false },
    { name: "color-mix()", pattern: /^color-mix\(/, convertible: false },
];

/** rgba() is recognised on purpose and never measured — see NOTATIONS. */
const UNMEASURABLE_BY_DESIGN = new Set(["rgba()"]);

/** The notation this value is written in, or null when it names no colour. */
export const notationOf = (value: string): string | null =>
    NOTATIONS.find((notation) => notation.pattern.test(value))?.name ?? null;

/**
 * The value as `#rrggbb`, or null when it names no colour or names one in a
 * notation this file cannot convert. Callers that need to tell those two apart
 * ask `notationOf`.
 */
export const toHex = (value: string): string | null => {
    if (/^#[0-9a-fA-F]{6}$/.test(value)) return value;

    const parts = value.match(/rgb\(\s*(\d+)[\s,]+(\d+)[\s,]+(\d+)\s*\)/);
    if (!parts) return null;

    return `#${parts
        .slice(1)
        .map((n) => Number(n).toString(16).padStart(2, "0"))
        .join("")}`;
};

/**
 * True when the value names a colour that ought to be readable here but is not
 * — the case a gate should fail on, naming the notation.
 *
 // @lat: [[theme-test-suite-silent-failure-guards#Colour notation: one shared module for two gates that used to disagree#Why NOTATIONS' order matters, and why rgba() is recognised but unmeasurable]]
 */
export const namesAnUnreadableColour = (value: string): boolean => {
    const notation = notationOf(value);
    if (notation === null) return false;
    if (UNMEASURABLE_BY_DESIGN.has(notation)) return false;

    return toHex(value) === null;
};

/** Every `--token: value;` declaration in a block of CSS text. */
export const declarationsIn = (body: string): Array<{ name: string; value: string }> =>
    [...body.matchAll(/(--[a-z0-9-]+)\s*:\s*([^;]+);/g)].map(([, name, raw]) => ({
        name,
        value: raw.trim(),
    }));

/** A colour declaration, as written and (where readable) as a hex triple. */
export interface ColourDeclaration {
    name: string;
    /** Exactly as it appears in the file — what to search built output for. */
    value: string;
    /** null when the notation cannot be converted. */
    hex: string | null;
}

/** Every declaration in this CSS that names a colour at all. */
export const colourDeclarationsIn = (css: string): ColourDeclaration[] =>
    declarationsIn(css)
        .map(({ name, value }) => ({ name, value, hex: toHex(value) }))
        .filter((declaration) => declaration.hex !== null || namesAnUnreadableColour(declaration.value));

/**
 // @lat: [[theme-test-suite-silent-failure-guards#Colour notation: one shared module for two gates that used to disagree#Why uniqueColourValue throws two different errors]]
 */
export const uniqueColourValue = (label: string, css: string, otherCss: readonly string[]): string => {
    const mine = colourDeclarationsIn(css);
    const taken = new Set(
        otherCss.flatMap((other) => colourDeclarationsIn(other).map((declaration) => declaration.hex)),
    );

    const own = mine.find((declaration) => declaration.hex !== null && !taken.has(declaration.hex));
    if (own) return own.value;

    const unreadable = mine
        .filter((declaration) => declaration.hex === null)
        .map((declaration) => `${declaration.name}: ${declaration.value} (${notationOf(declaration.value)})`);

    if (unreadable.length > 0) {
        throw new Error(
            `${label} writes colours in a notation this check cannot read, so nothing here can key the theme: ` +
                unreadable.join(", "),
        );
    }

    throw new Error(`${label} shares every one of its colours with another theme; nothing keys it uniquely`);
};
