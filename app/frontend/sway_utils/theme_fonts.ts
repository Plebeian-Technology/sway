// @lat: [[theme-font-hrefs#Why the shared theme prop carries the whole font map]]

const LINK_ATTRIBUTE = "data-theme-fonts";

function findLink(): HTMLLinkElement | null {
    if (typeof document === "undefined") return null;
    return document.head.querySelector<HTMLLinkElement>(`link[${LINK_ATTRIBUTE}]`);
}

// @lat: [[theme-font-hrefs#Why theme_fonts.ts reads getAttribute and removes empty links]]
export function currentThemeFontHref(): string | undefined {
    return findLink()?.getAttribute("href") ?? undefined;
}

// @lat: [[theme-font-hrefs#Why theme_fonts.ts reads getAttribute and removes empty links]]
export function applyThemeFontHref(href: string | undefined): void {
    if (typeof document === "undefined") return;

    const link = findLink();

    if (!href) {
        link?.remove();
        return;
    }

    if (link) {
        if (link.getAttribute("href") !== href) {
            link.setAttribute("href", href);
        }
        return;
    }

    const created = document.createElement("link");
    created.setAttribute(LINK_ATTRIBUTE, "");
    created.rel = "stylesheet";
    created.href = href;
    document.head.appendChild(created);
}
