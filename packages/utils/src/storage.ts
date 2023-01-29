const prependSlash = (s: string) => {
    if (!s) return "";
    if (s.startsWith("/")) {
        return s;
    } else {
        return "/" + s;
    }
};

export const getStoragePath = (
    path: string,
    localeName: string,
    base: "organizations" | "audio" | "images" | "legislators",
): string => {
    if (!path) return "";

    const p = prependSlash(path);
    if (path.includes(localeName)) {
        return `${p.split("?")[0]}?alt=media`;
    } else {
        return prependSlash(
            `${prependSlash(localeName)}${prependSlash(base)}${p.split("?")[0]}?alt=media`,
        );
    }
};
