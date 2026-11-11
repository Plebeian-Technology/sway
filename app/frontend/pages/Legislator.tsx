import { Link, usePoll } from "@inertiajs/react";
import { ArrowLeft, ChevronRight, ExternalLink, Mail, MapPin, Phone, User as UserIcon, X as XIcon } from "lucide-react";
import { useCallback, useState } from "react";

import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";
import LegislatorBillOfTheMonthRecord from "app/frontend/components/legislators/LegislatorBillOfTheMonthRecord";
import LegislatorChartsPanel from "app/frontend/components/legislators/charts/LegislatorChartsPanel";
import LegislatorHistoryTermsPanel from "app/frontend/components/legislators/history/LegislatorHistoryTermsPanel";
import LegislatorScoreTiles from "app/frontend/components/legislators/LegislatorScoreTiles";
import { Badge } from "app/frontend/components/ui/badge";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "app/frontend/components/ui/tabs";
import { useScoreSubscription } from "app/frontend/hooks/useScoreSubscription";
import { useUser } from "app/frontend/hooks/users/useUser";
import { formatTermWindow } from "app/frontend/sway_utils/termWindow";
import { ILegislatorWithTerms } from "app/frontend/types/legislators";

interface IProps {
    legislator: ILegislatorWithTerms;
}

const DEFAULT_AVATAR = "/images/politician.svg";

type TTab = "current" | "lifetime" | "history";

function readTabFromUrl(): TTab | null {
    if (typeof window === "undefined") return null;
    const params = new URLSearchParams(window.location.search);
    const tabParam = params.get("legislators_tab") || params.get("tab");
    if (tabParam === "current" || tabParam === "lifetime" || tabParam === "history") {
        return tabParam;
    }
    return null;
}

const POLLING_PROPS = ["legislator"];

const Legislator: React.FC<IProps> = ({ legislator }) => {
    // @lat: [[legislators-controller-design#Detail page has its own response]]
    const user = useUser();
    usePoll(15000, { only: POLLING_PROPS }, { background: "pause" });
    useScoreSubscription(POLLING_PROPS, Boolean(user));
    const [failedPhotoUrl, setFailedPhotoUrl] = useState<string | null>(null);
    const photoUrl = legislator.photo_url || null;
    const avatarSrc = photoUrl && failedPhotoUrl === photoUrl ? DEFAULT_AVATAR : photoUrl;
    const [tab, setTab] = useState<TTab>(() => readTabFromUrl() ?? "current");

    // @lat: [[legislators-controller-design#Active term is loaded before detail serialization]]
    const isFormerRep = legislator.active === false;
    const score = tab === "lifetime" ? legislator.lifetime_score : legislator.user_legislator_score;
    const chartsMode: "current" | "lifetime" = tab === "lifetime" ? "lifetime" : "current";

    // @lat: [[legislators-controller-design#What Legislator.test.tsx pins about the tab wording]]
    const termYearRange = formatTermWindow(legislator);

    const handleTabChange = useCallback((value: string) => setTab(value as TTab), []);

    const district = legislator.district;
    const districtName =
        district?.name ?? (typeof district?.number === "number" ? `District ${district.number}` : null);
    const districtLabel = district
        ? [districtName, district.region_code].filter((p): p is string => Boolean(p)).join(", ") || null
        : null;
    const districtMapHref = districtLabel
        ? `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(districtLabel)}`
        : null;
    const twitterHandle = legislator.twitter ? legislator.twitter.replace(/^@/, "") : null;
    const twitterHref = twitterHandle ? `https://twitter.com/${twitterHandle}` : null;
    const officialLinkHref = legislator.link && /^https?:\/\//i.test(legislator.link) ? legislator.link : null;

    return (
        <div className="space-y-6">
            {user ? (
                <Link
                    href="/legislators"
                    className="inline-flex h-9 cursor-pointer items-center gap-2 rounded-xl border-neo border-border-strong bg-surface-2 px-3 text-xs font-black uppercase tracking-widest text-foreground shadow-neo transition"
                >
                    <ArrowLeft className="size-3.5" aria-hidden="true" />
                    Representatives
                </Link>
            ) : null}

            <div className="rounded-2xl border-neo border-border-strong bg-card/95 p-5 shadow-neo">
                <div className="grid gap-5 md:grid-cols-[10rem_minmax(0,1fr)] md:items-start">
                    <div className="flex justify-center md:justify-start">
                        <div className="w-full max-w-[10rem] rounded-[1.6rem] border-neo border-border-strong bg-surface-2 p-1 shadow-neo">
                            {avatarSrc ? (
                                <img
                                    src={avatarSrc}
                                    alt={legislator.full_name}
                                    aria-label={`${legislator.full_name} avatar`}
                                    className="aspect-[4/5] w-full rounded-[1.25rem] object-cover"
                                    onError={
                                        avatarSrc === DEFAULT_AVATAR ? undefined : () => setFailedPhotoUrl(photoUrl)
                                    }
                                />
                            ) : (
                                <div
                                    className="flex aspect-[4/5] w-full items-center justify-center rounded-[1.25rem] bg-surface-3"
                                    aria-label={`${legislator.full_name} avatar placeholder`}
                                >
                                    <UserIcon className="size-10 text-muted-foreground" aria-hidden="true" />
                                </div>
                            )}
                        </div>
                    </div>

                    <div className="space-y-3">
                        <div className="flex flex-wrap items-center gap-2">
                            <h1 className="text-3xl font-black leading-tight">{legislator.full_name}</h1>
                            {isFormerRep && (
                                <Badge variant="stamp" tone="neutral" data-testid="legislator-detail-ended-stamp">
                                    {PARITY_COPY.legislators.endedStamp}
                                </Badge>
                            )}
                        </div>
                        <p className="text-xs font-black uppercase tracking-[0.18em] text-muted-foreground">
                            {legislator.title}
                            {districtName ? ` · ${districtName}` : null}
                        </p>
                    </div>
                </div>
            </div>

            <Tabs value={tab} onValueChange={handleTabChange}>
                <TabsList>
                    <TabsTrigger value="current" onClick={() => handleTabChange("current")}>
                        {isFormerRep && termYearRange ? termYearRange : PARITY_COPY.legislators.tabCurrentTerm}
                    </TabsTrigger>
                    <TabsTrigger value="lifetime" onClick={() => handleTabChange("lifetime")}>
                        {PARITY_COPY.legislators.tabLifetime}
                    </TabsTrigger>
                    <TabsTrigger value="history" onClick={() => handleTabChange("history")}>
                        {PARITY_COPY.legislators.tabHistory}
                    </TabsTrigger>
                </TabsList>

                {!isFormerRep && termYearRange && (
                    <p className="-mt-2 text-xs text-muted-foreground" data-testid="legislator-term-year-range">
                        {termYearRange}
                    </p>
                )}

                <TabsContent value="current" className="space-y-5">
                    <LegislatorScoreTiles score={score} />
                    {score && (
                        <section aria-label="Voter agreement charts" data-testid="legislator-detail-charts">
                            <LegislatorChartsPanel legislator={legislator} mode={chartsMode} />
                        </section>
                    )}
                </TabsContent>

                <TabsContent value="lifetime" className="space-y-5">
                    <LegislatorScoreTiles score={legislator.lifetime_score} />
                    {legislator.lifetime_score && (
                        <section
                            aria-label="Voter agreement charts (lifetime)"
                            data-testid="legislator-detail-charts-lifetime"
                        >
                            <LegislatorChartsPanel legislator={legislator} mode="lifetime" />
                        </section>
                    )}
                </TabsContent>

                <TabsContent value="history">
                    <LegislatorHistoryTermsPanel legislator={legislator} terms={legislator.terms} />
                </TabsContent>
            </Tabs>

            <LegislatorBillOfTheMonthRecord
                votes={legislator.bill_of_the_month_votes ?? []}
                isSignedIn={Boolean(user)}
            />

            <section aria-label="Contact information" data-testid="legislator-detail-contact" className="space-y-2">
                <ContactRow
                    icon={<MapPin className="size-5" aria-hidden="true" />}
                    label={districtLabel}
                    hint="Open in Google Maps"
                    href={districtMapHref}
                    testId="legislator-detail-district"
                />
                <ContactRow
                    icon={<Mail className="size-5" aria-hidden="true" />}
                    label={legislator.email}
                    hint="Send email"
                    href={legislator.email ? `mailto:${legislator.email}` : null}
                    testId="legislator-detail-email"
                />
                <ContactRow
                    icon={<Phone className="size-5" aria-hidden="true" />}
                    label={legislator.phone}
                    hint="Call"
                    href={legislator.phone ? `tel:${legislator.phone}` : null}
                    testId="legislator-detail-phone"
                />
                <ContactRow
                    icon={<XIcon className="size-5" aria-hidden="true" />}
                    label={twitterHandle ? `@${twitterHandle}` : null}
                    hint="Open on X / Twitter"
                    href={twitterHref}
                    testId="legislator-detail-twitter"
                />
                <ContactRow
                    icon={<ExternalLink className="size-5" aria-hidden="true" />}
                    label={officialLinkHref ? "Official page" : null}
                    hint="Open official website"
                    href={officialLinkHref}
                    testId="legislator-detail-link"
                />
            </section>
        </div>
    );
};

interface IContactRowProps {
    icon: React.ReactElement;
    label: string | null | undefined;
    hint: string;
    href: string | null | undefined;
    testId: string;
}

const ContactRow = ({ icon, label, hint, href, testId }: IContactRowProps) => {
    if (!label || !href) return null;
    const isExternal = /^https?:/i.test(href);
    return (
        <a
            href={href}
            data-testid={testId}
            aria-label={`${hint}: ${label}`}
            target={isExternal ? "_blank" : undefined}
            rel={isExternal ? "noopener noreferrer" : undefined}
            className="flex items-center gap-3 rounded-xl border-neo border-border-strong bg-card px-4 py-3 shadow-neo transition"
        >
            <span className="flex w-7 shrink-0 items-center justify-center text-muted-foreground">{icon}</span>
            <span className="flex-1 truncate text-sm font-semibold text-foreground">{label}</span>
            <ChevronRight className="size-4 shrink-0 text-muted-foreground" aria-hidden="true" />
        </a>
    );
};

export default Legislator;
