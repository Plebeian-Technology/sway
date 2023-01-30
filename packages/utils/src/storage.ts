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
    directory: "organizations" | "audio" | "images" | "legislators" | "geojson" | "awards",
): string => {
    if (!path) return "";

    const p = prependSlash(path);
    if (path.includes(localeName)) {
        return p.split("?")[0];
    } else {
        return prependSlash(
            `${prependSlash(localeName)}${prependSlash(directory)}${p.split("?")[0]}`,
        );
    }
};
