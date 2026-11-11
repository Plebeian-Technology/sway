// @lat: [[char-diff-tailwind-highlighting#Why diffToTailwind.ts uses a plain colour wash]]

import { diffChars, type Change } from "diff";
import React from "react";

export interface DiffPart {
    key: number;
    value: string;
    className: string | null;
    kind: "added" | "removed" | "unchanged";
}

const additionClasses = "bg-success/20 text-foreground";
const removalClasses = "bg-destructive/20 text-foreground";

export const computeDiffParts = (previous: string, next: string): DiffPart[] => {
    const changes: Change[] = diffChars(previous ?? "", next ?? "");
    return changes.map((part, idx) => {
        if (part.added) {
            return { key: idx, value: part.value, className: additionClasses, kind: "added" };
        }
        if (part.removed) {
            return { key: idx, value: part.value, className: removalClasses, kind: "removed" };
        }
        return { key: idx, value: part.value, className: null, kind: "unchanged" };
    });
};

export const renderCharDiff = (previous: string, next: string): React.ReactNode => {
    const parts = computeDiffParts(previous, next);
    return parts.map((part) =>
        part.className
            ? React.createElement("span", { key: part.key, className: part.className }, part.value)
            : React.createElement("span", { key: part.key }, part.value),
    );
};
