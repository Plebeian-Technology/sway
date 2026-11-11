import React from "react";
import { StyleSheet } from "react-native";
import { render, screen } from "@testing-library/react-native";

import { ThemeProvider } from "../../src/theme/ThemeProvider";
import { swayTokens, type SwayColorScheme } from "../../src/theme/tokens";
import { WarningStamp } from "../../src/components/WarningStamp";

type Rgb = [number, number, number];

const parseHex = (hex: string): { rgb: Rgb; alpha: number } => {
    const n = hex.replace("#", "");
    const rgb = [0, 2, 4].map((i) => parseInt(n.slice(i, i + 2), 16)) as Rgb;
    const alpha = n.length === 8 ? parseInt(n.slice(6, 8), 16) / 255 : 1;
    return { rgb, alpha };
};

const linearize = (c: number) => {
    const s = c / 255;
    return s <= 0.03928 ? s / 12.92 : Math.pow((s + 0.055) / 1.055, 2.4);
};
const luminance = ([r, g, b]: Rgb) => 0.2126 * linearize(r) + 0.7152 * linearize(g) + 0.0722 * linearize(b);
const contrast = (a: Rgb, b: Rgb) => {
    const [hi, lo] = [luminance(a), luminance(b)].sort((x, y) => y - x);
    return (hi + 0.05) / (lo + 0.05);
};
const composite = (over: { rgb: Rgb; alpha: number }, under: Rgb): Rgb =>
    over.rgb.map((v, i) => Math.round(v * over.alpha + under[i] * (1 - over.alpha))) as Rgb;

const renderStamp = (mode: SwayColorScheme) =>
    render(
        <ThemeProvider initialMode={mode}>
            <WarningStamp label="News commentary" testID="stamp" />
        </ThemeProvider>,
    );

describe("WarningStamp", () => {
    test.each<SwayColorScheme>(["light", "dark"])("draws its text and border from the %s warning token", (mode) => {
        renderStamp(mode);

        const token = swayTokens[mode].warning;
        const label = StyleSheet.flatten(screen.getByText("News commentary").props.style);
        const box = StyleSheet.flatten(screen.getByTestId("stamp").props.style);
        expect(label.color).toBe(token);
        expect(String(box.borderColor).toLowerCase().startsWith(token.toLowerCase())).toBe(true);
        expect(String(box.backgroundColor).toLowerCase().startsWith(token.toLowerCase())).toBe(true);
    });

    test.each<[SwayColorScheme, keyof (typeof swayTokens)["light"]]>([
        ["light", "card"],
        ["light", "surface2"],
        ["dark", "card"],
        ["dark", "surface2"],
    ])("keeps the label at least 4.5:1 against its tint in %s mode over %s", (mode, surface) => {
        renderStamp(mode);

        const box = StyleSheet.flatten(screen.getByTestId("stamp").props.style);
        const label = StyleSheet.flatten(screen.getByText("News commentary").props.style);
        const host = parseHex(swayTokens[mode][surface]).rgb;
        const fill = composite(parseHex(String(box.backgroundColor)), host);

        expect(contrast(parseHex(String(label.color)).rgb, fill)).toBeGreaterThanOrEqual(4.5);
    });

    test("is announced as text with its label", () => {
        renderStamp("light");

        expect(screen.getByTestId("stamp").props.accessibilityRole).toBe("text");
        expect(screen.getByText("News commentary")).toBeTruthy();
    });
});
