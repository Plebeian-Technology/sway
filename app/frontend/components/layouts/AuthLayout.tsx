import { Head, usePage } from "@inertiajs/react";
import { sway } from "sway";

import { GITHUB_LINK, ROUTES } from "app/frontend/sway_constants";
import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";
import OfflineContext from "app/frontend/components/contexts/OfflineContext";
import PageErrorBoundary from "app/frontend/components/error_handling/PageErrorBoundary";
import { SWUpdateToast } from "app/frontend/components/offline/SWUpdateToast";
import { useOfflineBannerState } from "app/frontend/hooks/useOfflineBannerState";
import { useReachability } from "app/frontend/hooks/useReachability";
import { useLogout } from "app/frontend/hooks/users/useLogout";
import { useUser } from "app/frontend/hooks/users/useUser";
import {
    Activity,
    ArrowLeft,
    ArrowUpRight,
    Bell,
    Bookmark,
    BrainCog,
    Building2,
    Hammer,
    History,
    KeyRound,
    Landmark,
    LayoutDashboard,
    LogIn,
    LogOut,
    ScrollText,
    Search,
    Sparkles,
    Tags,
    Users,
    WifiOff,
} from "lucide-react";
import { PropsWithChildren, useCallback, useEffect, useMemo, useState } from "react";

import AppVersionFooter from "app/frontend/components/brand/AppVersionFooter";
import Drawer, { type NavItem } from "app/frontend/components/drawer/Drawer";
import PageBodySlot from "app/frontend/components/layouts/PageBodySlot";
import { makeSignOutHandler } from "app/frontend/components/layouts/signOutHandler";
import ReassignmentBanner from "app/frontend/components/legislators/ReassignmentBanner";
import { isSafeExternalHref } from "app/frontend/sway_utils/safeHref";

type IProps = PropsWithChildren;

// @lat: [[system-shape#Auth navigation]]
const isAdminContext = (url: string): boolean => {
    const path = url.split(/[?#]/)[0];
    return path === "/admin" || path.startsWith("/admin/");
};

const AuthLayout: React.FC<IProps> = ({ children }) => {
    const user = useUser();
    // @lat: [[system-shape#Auth navigation]]
    const page = usePage<sway.IPageProps>();
    const { legislator_photo_urls } = page.props;
    const url = page.url;
    const adminMode = !!user?.is_admin && isAdminContext(url);
    const logout = useLogout();
    const [isLoading, setIsLoading] = useState(false);
    const { isOnline, lastChecked } = useReachability();
    const { bannerState, dismissBanner, assertBanner } = useOfflineBannerState(isOnline);

    const offlineValue = useMemo(
        () => ({ isOnline, lastChecked, bannerState, dismissBanner, assertBanner }),
        [assertBanner, bannerState, dismissBanner, isOnline, lastChecked],
    );

    useEffect(() => {
        const stop = () => setIsLoading(false);
        window.addEventListener("inertia:finish", stop);
        window.addEventListener("inertia:error", stop);
        return () => {
            window.removeEventListener("inertia:finish", stop);
            window.removeEventListener("inertia:error", stop);
        };
    }, []);

    // @lat: [[system-shape#Auth navigation]]
    const buildSignOutItem = useCallback(
        (): NavItem => ({
            label: "Sign Out",
            Icon: LogOut,
            onSelect: makeSignOutHandler(logout, setIsLoading),
        }),
        [logout],
    );

    const primaryItems = useMemo<NavItem[]>(() => {
        if (adminMode) {
            // @lat: [[system-shape#Auth navigation]]
            const adminItems: NavItem[] = [
                { route: ROUTES.admin, label: "Admin Home", Icon: LayoutDashboard },
                {
                    route: ROUTES.billCreator,
                    activePrefix: "/admin/bill_creator",
                    label: "Bill Creator",
                    Icon: Hammer,
                },
                {
                    route: ROUTES.admin_llm_settings,
                    activePrefix: "/admin/llm_settings",
                    label: "LLM Settings",
                    Icon: BrainCog,
                },
                {
                    route: ROUTES.admin_categories,
                    activePrefix: "/admin/categories",
                    label: "Categories",
                    Icon: Tags,
                },
            ];
            if (user?.beszel_url) {
                adminItems.push({
                    route: user.beszel_url,
                    label: "Beszel",
                    Icon: Activity,
                    external: true,
                });
            }
            return adminItems;
        }

        const defaults: NavItem[] = [
            { route: ROUTES.legislators, label: "Representatives", Icon: Users, prefetch: true },
            { route: ROUTES.billOfTheMonth, label: PARITY_COPY.billOfTheMonth.title, Icon: Bookmark, prefetch: true },
            {
                route: ROUTES.pastBillsOfTheMonth,
                label: PARITY_COPY.bills.pastBillsOfTheMonthTitle,
                Icon: History,
                prefetch: true,
            },
            { route: ROUTES.bills, label: PARITY_COPY.bills.allBillsTitle, Icon: ScrollText, prefetch: true },
            { route: ROUTES.influence, label: "Your Sway", Icon: Sparkles, prefetch: true },
        ];

        if (user?.is_registration_complete) {
            return defaults;
        }

        return [
            {
                route: user ? ROUTES.registration : ROUTES.signin,
                label: user ? "Find Representatives" : "Sign in to Sway",
                Icon: user ? Search : LogIn,
            },
            ...defaults,
        ];
    }, [adminMode, user]);

    const secondaryItems = useMemo<NavItem[]>(() => {
        if (adminMode) {
            // @lat: [[system-shape#Auth navigation]]
            const _items: NavItem[] = [{ route: ROUTES.index, label: "Back to Sway", Icon: ArrowLeft }];
            if (user) {
                _items.push({ route: "/users/passkeys", label: "Passkeys", Icon: KeyRound }, buildSignOutItem());
            }
            _items.push({ route: GITHUB_LINK, label: "GitHub", Icon: ArrowUpRight, external: true });
            return _items;
        }

        const items: NavItem[] = [
            { route: ROUTES.users.organization_memberships, label: "Organizations", Icon: Building2 },
            // @lat: [[system-shape#Auth navigation]]
            { route: ROUTES.publicOrganizations, label: "Browse Organizations", Icon: Landmark },
        ];

        if ("Notification" in window) {
            items.push({ route: ROUTES.notifications, label: "Notifications", Icon: Bell });
        }

        if (user?.is_admin) {
            items.push({ route: ROUTES.admin, label: "Admin", Icon: LayoutDashboard });
        }

        if (user) {
            items.push({ route: "/users/passkeys", label: "Passkeys", Icon: KeyRound }, buildSignOutItem());
        }

        items.push({ route: GITHUB_LINK, label: "GitHub", Icon: ArrowUpRight, external: true });

        return items;
    }, [adminMode, buildSignOutItem, user]);

    return (
        <OfflineContext.Provider value={offlineValue}>
            {/* @lat: [[legislator-photo-prefetch#Why it prefetches images instead of preloading them]] */}
            {legislator_photo_urls && legislator_photo_urls.length > 0 && (
                <Head>
                    {legislator_photo_urls.filter(isSafeExternalHref).map((_url) => (
                        <link key={_url} rel="prefetch" as="image" href={_url} />
                    ))}
                </Head>
            )}
            <div className="min-h-svh bg-background lg:grid lg:grid-cols-[18rem_minmax(0,1fr)]">
                <SWUpdateToast />
                <Drawer isLoading={isLoading} primaryItems={primaryItems} secondaryItems={secondaryItems} />

                <div className="min-w-0">
                    {bannerState !== "hidden" && (
                        <output
                            aria-live="polite"
                            aria-atomic="true"
                            data-testid="offline-banner"
                            className="block border-b-neo border-border bg-warning px-4 py-3 text-sm font-semibold text-warning-foreground md:px-6"
                        >
                            <div className="mx-auto flex w-full max-w-[calc(var(--content-max)+6rem)] items-center justify-between gap-4">
                                <div className="flex items-center gap-2.5">
                                    <WifiOff className="h-4 w-4 shrink-0" aria-hidden="true" />
                                    <span>
                                        {bannerState === "asserted"
                                            ? "Still offline. Reconnect to load pages and vote."
                                            : "You're offline. Reconnect to load pages and vote."}
                                    </span>
                                </div>
                                {bannerState === "visible" && (
                                    <button
                                        type="button"
                                        className="min-h-11 shrink-0 underline underline-offset-4 font-semibold hover:opacity-90 transition-opacity"
                                        onClick={dismissBanner}
                                    >
                                        Dismiss
                                    </button>
                                )}
                            </div>
                        </output>
                    )}

                    <ReassignmentBanner />

                    {/* @lat: [[system-shape#Why the shell keeps one reading measure]] */}
                    <main className="mx-auto flex w-full max-w-[calc(var(--content-max)+6rem)] flex-col px-4 pb-16 pt-6 md:px-6 lg:px-8">
                        <div className="mx-auto w-full max-w-(--content-max)">
                            <PageBodySlot>
                                <PageErrorBoundary>{children}</PageErrorBoundary>
                            </PageBodySlot>
                        </div>
                        <AppVersionFooter className="mx-auto w-full max-w-(--content-max)" />
                    </main>
                </div>
            </div>
        </OfflineContext.Provider>
    );
};

// @lat: [[system-shape#Auth navigation]]
export { AuthLayout };

const AuthPageLayout = (page: React.JSX.Element) => <AuthLayout {...page.props}>{page}</AuthLayout>;

export default AuthPageLayout;
