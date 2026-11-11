import { clsx, type ClassValue } from "clsx";
import { extendTailwindMerge } from "tailwind-merge";

// @lat: [[theme-tokens#Theme tokens#Why navigation shell and secondary pages use token-driven borders]]
const customTwMerge = extendTailwindMerge({
    extend: {
        classGroups: {
            "border-w": ["border-neo"],
            "border-w-t": ["border-t-neo"],
            "border-w-r": ["border-r-neo"],
            "border-w-b": ["border-b-neo"],
            "border-w-l": ["border-l-neo"],
        },
    },
});

export function cn(...inputs: ClassValue[]) {
    return customTwMerge(clsx(inputs));
}
