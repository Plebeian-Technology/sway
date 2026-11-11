export type InertiaPageLoader = () => Promise<any>;

interface ResolvedPageLoader {
    loader: InertiaPageLoader;
    pageName: string;
}

const toPath = (prefix: string, pageName: string) => `${prefix}/${pageName}.tsx`;

export const resolvePageLoader = (
    rawPageName: string | undefined,
    pages: Record<string, InertiaPageLoader>,
): ResolvedPageLoader => {
    const pageName = rawPageName || "Home";
    const path = toPath("../pages", pageName);

    if (pages[path]) {
        return { loader: pages[path], pageName };
    }

    throw new Error(`Unable to resolve Inertia page "${pageName}".`);
};
