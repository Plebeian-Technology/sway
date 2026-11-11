import { Link, usePage } from "@inertiajs/react";
import { Menu, type LucideIcon } from "lucide-react";
import { Fragment, useMemo, useState } from "react";

import BrandMark from "app/frontend/components/brand/BrandMark";
import ReleaseInfo from "app/frontend/components/brand/ReleaseInfo";
import { GENERIC_ENTRY, resolvePlaceholder } from "app/frontend/navigation/placeholderRegistry";
import { PREFETCH_CACHE_FOR } from "app/frontend/sway_constants";
import { isSafeExternalHref } from "app/frontend/sway_utils/safeHref";
import ThemePicker from "app/frontend/components/drawer/ThemePicker";
import ThemeToggle from "app/frontend/components/drawer/ThemeToggle";
import { Button } from "app/frontend/components/ui/button";
import {
    Sheet,
    SheetContent,
    SheetDescription,
    SheetHeader,
    SheetTitle,
    SheetTrigger,
} from "app/frontend/components/ui/sheet";
import { cn } from "app/frontend/lib/utils";

export interface NavItem {
    Icon: LucideIcon;
    label: string;
    route?: string;
    activePrefix?: string;
    external?: boolean;
    prefetch?: boolean;
    onSelect?: () => void;
}

interface IProps {
    isLoading: boolean;
    primaryItems: NavItem[];
    secondaryItems: NavItem[];
}

const navItemClassName = (selected: boolean) =>
    cn(
        "ml-0.5 flex cursor-pointer items-center gap-3 rounded-xl border-neo border-border-strong px-4 py-2 text-left text-sm font-semibold shadow-neo transition",
        selected
            ? "bg-primary text-primary-foreground"
            : "bg-surface-2 text-foreground ring-1 ring-inset ring-border-strong/70 hover:bg-accent hover:text-accent-foreground",
    );

// @lat: [[drawer-header-and-nav-selection#Why the selection rule strips the query and hash]]
// oxlint-disable-next-line react-refresh/only-export-components -- pure helper exported for direct unit testing; co-located with its only caller (Drawer).
export const isActivePrefix = (path: string, prefix: string): boolean => {
    const normalized = prefix.endsWith("/") ? prefix.slice(0, -1) : prefix;
    if (normalized === "" || normalized === "/") {
        return false;
    }
    return path === normalized || path.startsWith(normalized + "/");
};

// @lat: [[drawer-header-and-nav-selection#Why the selection rule strips the query and hash]]
const pathOf = (url: string): string => url.split(/[?#]/)[0];

const isItemSelected = (item: NavItem, path: string): boolean =>
    item.activePrefix ? isActivePrefix(path, item.activePrefix) : item.route === path;

// @lat: [[drawer-header-and-nav-selection#Where the mobile header's page name comes from]]
const pageTitleFor = (path: string, items: NavItem[]): string => {
    const selected = items.find((item) => Boolean(item.route) && !item.external && isItemSelected(item, path));
    if (selected) {
        return selected.label;
    }

    const { pageName } = resolvePlaceholder(path);
    return pageName === GENERIC_ENTRY.pageName ? "Sway" : pageName;
};

const NavItemRow = ({ item, onAfterSelect }: { item: NavItem; onAfterSelect?: () => void }) => {
    const { url } = usePage();
    const path = pathOf(url);
    const isSelected = isItemSelected(item, path);
    const content = (
        <Fragment>
            <item.Icon className="size-4" aria-hidden="true" />
            <span>{item.label}</span>
        </Fragment>
    );

    if (typeof item.onSelect === "function") {
        return (
            <button
                type="button"
                className={cn(navItemClassName(false), "w-full")}
                onClick={(e) => {
                    e.preventDefault();

                    item.onSelect!();
                    onAfterSelect?.();
                }}
            >
                {content}
            </button>
        );
    }

    if (!item.route) {
        return null;
    }

    if (item.external) {
        if (!isSafeExternalHref(item.route)) {
            return null;
        }
        return (
            <a
                href={item.route}
                target="_blank"
                rel="noopener noreferrer"
                className={navItemClassName(false)}
                onClick={onAfterSelect}
            >
                {content}
            </a>
        );
    }

    return (
        <Link
            href={item.route}
            prefetch={item.prefetch ? "hover" : undefined}
            cacheFor={PREFETCH_CACHE_FOR}
            viewTransition
            className={navItemClassName(isSelected)}
            aria-current={isSelected ? "page" : undefined}
            onClick={onAfterSelect}
        >
            {content}
        </Link>
    );
};

const DrawerSection = ({
    title,
    items,
    onAfterSelect,
}: {
    title: string;
    items: NavItem[];
    onAfterSelect?: () => void;
}) => {
    if (items.length === 0) {
        return null;
    }

    return (
        <section className="space-y-2">
            <div className="px-1 text-xs font-black uppercase tracking-widest text-muted-foreground">{title}</div>
            <div className="space-y-2">
                {items.map((item) => (
                    <NavItemRow
                        key={`${item.label}-${item.route ?? "action"}`}
                        item={item}
                        onAfterSelect={onAfterSelect}
                    />
                ))}
            </div>
        </section>
    );
};

const DrawerBrand = () => (
    <ReleaseInfo>
        <Link
            href="/"
            prefetch="hover"
            cacheFor={PREFETCH_CACHE_FOR}
            viewTransition
            className="flex items-center gap-3 rounded-2xl border-neo border-border-soft bg-secondary px-2 py-2 shadow-neo"
        >
            <BrandMark className="size-12 rounded-2xl" />
            <div className="min-w-0">
                <div className="text-sm font-semibold text-muted-foreground">Remember in November</div>
                <div className="text-2xl font-black text-foreground">Sway</div>
            </div>
        </Link>
    </ReleaseInfo>
);

const DrawerFooter = ({ isLoading }: Pick<IProps, "isLoading">) => (
    <div className="space-y-3 border-t-neo border-border pt-4">
        <div className="space-y-2">
            <div className="px-1 text-xs font-black uppercase tracking-widest text-muted-foreground">Appearance</div>
            <ThemeToggle className="w-full" />
            <ThemePicker />
        </div>

        {isLoading && (
            <output
                className="flex items-center gap-2 rounded-xl border-neo border-border bg-card px-3 py-2 text-xs font-semibold text-muted-foreground shadow-neo"
                aria-live="polite"
            >
                <img src="/images/loading.svg" alt="" className="size-4" aria-hidden="true" />
                <span>Navigating</span>
            </output>
        )}
    </div>
);

const Drawer: React.FC<IProps> = ({ isLoading, primaryItems, secondaryItems }) => {
    const [open, setOpen] = useState(false);
    const { url } = usePage();
    const pageTitle = useMemo(
        () => pageTitleFor(pathOf(url), [...primaryItems, ...secondaryItems]),
        [primaryItems, secondaryItems, url],
    );
    const drawerSections = useMemo(
        () => [
            { title: "Navigation", items: primaryItems },
            { title: "More", items: secondaryItems },
        ],
        [primaryItems, secondaryItems],
    );

    return (
        <Fragment>
            <div className="sticky top-0 z-40 border-b-neo border-border bg-background/95 px-4 py-4 backdrop-blur lg:hidden">
                <div className="flex items-center justify-between gap-3">
                    <Sheet open={open} onOpenChange={setOpen}>
                        <SheetTrigger asChild>
                            <Button
                                type="button"
                                variant="secondary"
                                size="icon"
                                aria-label="Open navigation drawer"
                                className="cursor-pointer"
                            >
                                <Menu className="size-4" />
                            </Button>
                        </SheetTrigger>
                        <SheetContent
                            side="left"
                            className="w-[88vw] max-w-sm gap-0 overflow-hidden p-0"
                            aria-label="Navigation drawer"
                        >
                            <SheetHeader className="border-b-neo border-border bg-card p-4">
                                <SheetTitle className="text-left text-lg font-black text-foreground">
                                    Navigate Sway
                                </SheetTitle>
                                <SheetDescription className="sr-only">
                                    Browse navigation links, account actions, and display intensity controls.
                                </SheetDescription>
                            </SheetHeader>
                            <div className="flex h-full flex-col gap-5 overflow-y-auto bg-card px-4 py-4">
                                <DrawerBrand />
                                {drawerSections.map((section) => (
                                    <DrawerSection
                                        key={section.title}
                                        title={section.title}
                                        items={section.items}
                                        onAfterSelect={() => setOpen(false)}
                                    />
                                ))}
                                <div className="mt-auto">
                                    <DrawerFooter isLoading={isLoading} />
                                </div>
                            </div>
                        </SheetContent>
                    </Sheet>

                    <div className="min-w-0 flex-1">
                        <div className="text-xs font-black uppercase tracking-widest text-muted-foreground">Sway</div>
                        <div className="truncate text-lg font-black text-foreground" data-testid="drawer-page-title">
                            {pageTitle}
                        </div>
                    </div>
                </div>
            </div>

            <aside className="hidden border-r-neo border-border bg-background lg:block">
                <div className="sticky top-0 flex h-svh flex-col gap-4 overflow-hidden px-5 py-4">
                    <DrawerBrand />

                    <div className="min-h-0 flex-1 space-y-4 overflow-y-auto pr-1">
                        {drawerSections.map((section) => (
                            <DrawerSection key={section.title} title={section.title} items={section.items} />
                        ))}
                    </div>

                    <DrawerFooter isLoading={isLoading} />
                </div>
            </aside>
        </Fragment>
    );
};

export default Drawer;
