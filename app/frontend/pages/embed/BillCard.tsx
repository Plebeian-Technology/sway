import React, { useEffect } from "react";

import { ROUTES } from "app/frontend/sway_constants/routes";
import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";

export interface IEmbedBill {
    id: number;
    identifier: string;
    title: string;
    brief_summary: string;
    sway_locale: {
        name: string;
        jurisdiction: string;
        state: string;
    };
    current_status: string;
    pro_percent: number | null;
    con_percent: number | null;
    comparison_suppressed: boolean;
    cta_url: string;
}

export interface IProps {
    bill?: IEmbedBill;
    id?: number;
    identifier?: string;
    title?: string;
    brief_summary?: string;
    sway_locale?: {
        name: string;
        jurisdiction: string;
        state: string;
    };
    current_status?: string;
    pro_percent?: number | null;
    con_percent?: number | null;
    comparison_suppressed?: boolean;
    cta_url?: string;
}

const BillCard: React.FC<IProps> & { layout?: (page: React.ReactNode) => React.ReactNode } = (props) => {
    const bill: IEmbedBill = props.bill ?? {
        id: props.id ?? 0,
        identifier: props.identifier ?? "",
        title: props.title ?? "",
        brief_summary: props.brief_summary ?? "",
        sway_locale: props.sway_locale ?? { name: "", jurisdiction: "", state: "" },
        current_status: props.current_status ?? "Introduced",
        pro_percent: props.pro_percent ?? 0,
        con_percent: props.con_percent ?? 0,
        comparison_suppressed: props.comparison_suppressed ?? true,
        cta_url: props.cta_url ?? "",
    };

    const defaultVoteUrl = `/bills/${bill.id}`;
    const rawCtaUrl = props.cta_url || bill.cta_url || defaultVoteUrl;
    const ctaUrl = (() => {
        try {
            const parsed = new URL(rawCtaUrl, window.location.origin);
            if (parsed.protocol === "http:" || parsed.protocol === "https:") {
                return rawCtaUrl;
            }
        } catch {
            return defaultVoteUrl;
        }
        return defaultVoteUrl;
    })();
    const signUpHref = (() => {
        const referral = new URLSearchParams();
        const { searchParams } = new URL(ctaUrl, window.location.origin);
        ["partner", "ref"].forEach((key) => {
            const value = searchParams.get(key);
            if (value) referral.set(key, value);
        });
        const query = referral.toString();
        return query ? `${ROUTES.signin}?${query}` : ROUTES.signin;
    })();
    // @lat: [[voter-privacy-threshold#The embed widget withholds counts on the server]]
    const comparisonSuppressed = bill.comparison_suppressed !== false;
    const proPct = bill.pro_percent ?? 0;
    const conPct = bill.con_percent ?? 0;

    useEffect(() => {
        if (typeof window !== "undefined" && window.parent && window.parent !== window) {
            let lastHeight = 0;
            const sendHeight = () => {
                const height = Math.ceil(document.documentElement?.scrollHeight || document.body?.scrollHeight || 0);
                if (height > 0 && height !== lastHeight) {
                    lastHeight = height;
                    window.parent.postMessage(
                        {
                            type: "sway:resize",
                            height,
                            billId: bill.id,
                        },
                        "*",
                    );
                }
            };

            sendHeight();
            window.addEventListener("resize", sendHeight);

            let observer: ResizeObserver | null = null;
            if (typeof ResizeObserver !== "undefined") {
                observer = new ResizeObserver(() => {
                    sendHeight();
                });
                const target = document.body || document.documentElement;
                if (target) {
                    observer.observe(target);
                }
            }

            return () => {
                window.removeEventListener("resize", sendHeight);
                if (observer) {
                    observer.disconnect();
                }
            };
        }
    }, [bill.id]);

    return (
        <article
            data-testid="embed-bill-card"
            className="flex h-full min-h-[260px] w-full flex-col justify-between rounded-xl border-neo border-border bg-card p-4 text-card-foreground shadow-neo sm:p-5"
        >
            <div className="space-y-3">
                <header className="flex flex-wrap items-center gap-2">
                    {bill.sway_locale?.jurisdiction && (
                        <span
                            data-testid="locale-badge"
                            className="rounded-full border-neo border-border bg-muted px-2.5 py-0.5 text-xs font-bold uppercase tracking-wider text-muted-foreground shadow-neo"
                        >
                            {bill.sway_locale.jurisdiction}
                        </span>
                    )}
                    {bill.identifier && (
                        <span
                            data-testid="bill-identifier"
                            className="rounded-full border-neo border-border bg-accent px-2.5 py-0.5 text-xs font-black uppercase tracking-wider text-accent-foreground shadow-neo"
                        >
                            {bill.identifier}
                        </span>
                    )}
                    {bill.current_status && (
                        <span
                            data-testid="bill-status"
                            className="rounded-full border-neo border-border bg-surface-3 px-2.5 py-0.5 text-xs font-semibold uppercase tracking-wider text-foreground shadow-neo"
                        >
                            {bill.current_status}
                        </span>
                    )}
                </header>

                <div className="space-y-1.5">
                    <h2
                        data-testid="bill-title"
                        title={bill.title}
                        className="line-clamp-2 text-lg font-black leading-snug tracking-tight text-foreground sm:line-clamp-3 sm:text-xl"
                    >
                        {bill.title}
                    </h2>

                    {bill.brief_summary && (
                        <p
                            data-testid="bill-summary"
                            className="line-clamp-3 text-xs leading-relaxed text-muted-foreground sm:text-sm"
                        >
                            {bill.brief_summary}
                        </p>
                    )}
                </div>
            </div>

            <div className="mt-4 space-y-3 pt-2">
                {!comparisonSuppressed ? (
                    <div data-testid="vote-meter" className="space-y-1.5">
                        <div
                            className="flex h-6 w-full overflow-hidden rounded-lg border-neo border-border bg-muted shadow-neo"
                            aria-label={`Support ${proPct}%, Oppose ${conPct}%`}
                        >
                            {proPct > 0 && (
                                <div
                                    data-testid="pro-bar"
                                    className="flex items-center justify-start bg-vote-for px-2 text-xs font-black text-white tabular-nums"
                                    style={{ width: `${proPct}%` }}
                                >
                                    {proPct >= 15 && `${proPct}%`}
                                </div>
                            )}
                            {conPct > 0 && (
                                <div
                                    data-testid="con-bar"
                                    className="flex items-center justify-end bg-vote-against px-2 text-xs font-black text-white tabular-nums"
                                    style={{ width: `${conPct}%` }}
                                >
                                    {conPct >= 15 && `${conPct}%`}
                                </div>
                            )}
                        </div>

                        <div className="flex items-center justify-between text-xs font-bold uppercase tracking-wider text-muted-foreground">
                            <span className="flex items-center gap-1.5 text-vote-for">
                                <span className="inline-block size-2.5 rounded-full bg-vote-for" />
                                <span>Support {proPct}%</span>
                            </span>
                            <span className="flex items-center gap-1.5 text-vote-against">
                                <span>Oppose {conPct}%</span>
                                <span className="inline-block size-2.5 rounded-full bg-vote-against" />
                            </span>
                        </div>
                    </div>
                ) : (
                    <div
                        data-testid="vote-meter-suppressed"
                        className="space-y-1 rounded-lg border-neo border-border bg-surface-3 px-3 py-2 text-center text-xs font-semibold text-muted-foreground shadow-neo"
                    >
                        <p>{PARITY_COPY.bill.voteComparisonPlaceholder.notEnoughVotes}</p>
                        <p>
                            {PARITY_COPY.bill.voteComparisonPlaceholder.invitePrompt}{" "}
                            <a
                                href={signUpHref}
                                target="_blank"
                                rel="noopener noreferrer"
                                className="font-black text-foreground underline"
                            >
                                {PARITY_COPY.bill.voteComparisonPlaceholder.signUp}
                            </a>
                        </p>
                    </div>
                )}

                <footer className="flex flex-wrap items-center justify-between gap-3 border-t border-border pt-3">
                    <div className="flex items-center gap-2">
                        <div className="flex size-5 items-center justify-center rounded-md border-neo border-border bg-primary text-[10px] font-black text-primary-foreground">
                            S
                        </div>
                        <span className="text-xs font-semibold text-muted-foreground">Vote on Sway</span>
                    </div>

                    <a
                        data-testid="act-cta-button"
                        href={ctaUrl}
                        target="_blank"
                        rel="noopener noreferrer"
                        className="inline-flex items-center justify-center gap-1.5 rounded-lg border-neo border-border bg-primary px-3.5 py-2 text-xs font-black uppercase tracking-wide text-primary-foreground shadow-neo transition hover:-translate-x-0.5 hover:-translate-y-0.5 active:translate-x-0 active:translate-y-0 focus:outline-none focus:ring-2 focus:ring-ring sm:text-sm"
                    >
                        Act on this bill &rarr;
                    </a>
                </footer>
            </div>
        </article>
    );
};

BillCard.layout = (page: React.ReactNode) => page;

export default BillCard;
