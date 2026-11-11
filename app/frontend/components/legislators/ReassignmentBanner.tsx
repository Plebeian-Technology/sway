import { Link } from "@inertiajs/react";
import { ArrowRight, MapPin, UserCheck, UserMinus, UserPlus } from "lucide-react";
import React from "react";

import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";
import { ROUTES } from "app/frontend/sway_constants";
import { useReassignmentNotifications } from "app/frontend/hooks/legislators/useReassignmentNotifications";
import type { sway } from "sway";

const formatDistrictLabel = (district?: sway.IDistrict | null): string => {
    if (!district) return "your district";
    return district.name ?? (typeof district.number === "number" ? `District ${district.number}` : "your district");
};

interface IItemProps {
    notification: sway.IRepresentativeReassignment;
    onDismiss: (id: number) => void;
}

const ReassignmentBannerItem: React.FC<IItemProps> = ({ notification, onDismiss }) => {
    const districtLabel = formatDistrictLabel(notification.district);
    const newLegislator = notification.legislator;
    const oldLegislator = notification.previous_legislator;

    let Icon = MapPin;
    let message: React.ReactNode = null;

    switch (notification.reassignment_type) {
        case "district_changed":
            Icon = MapPin;
            message = (
                <span>
                    Your voting district has changed to {districtLabel}. Your new representative is{" "}
                    {newLegislator ? (
                        <Link
                            href={ROUTES.legislator(newLegislator.id)}
                            className="underline decoration-1 underline-offset-2 hover:opacity-80"
                        >
                            {newLegislator.full_name}
                        </Link>
                    ) : (
                        "assigned"
                    )}
                    .
                </span>
            );
            break;
        case "successor_seeded":
            Icon = UserCheck;
            message = (
                <span>
                    {newLegislator ? (
                        <Link
                            href={ROUTES.legislator(newLegislator.id)}
                            className="underline decoration-1 underline-offset-2 hover:opacity-80"
                        >
                            {newLegislator.full_name}
                        </Link>
                    ) : (
                        "A new representative"
                    )}{" "}
                    has succeeded {oldLegislator?.full_name ?? "your previous representative"} as your representative
                    for {districtLabel}.
                </span>
            );
            break;
        case "vacant_seat":
            Icon = UserMinus;
            message = (
                <span>
                    {oldLegislator?.full_name ?? "Your representative"} no longer represents {districtLabel} and the
                    seat is currently vacant.
                </span>
            );
            break;
        case "vacancy_filled":
            Icon = UserPlus;
            message = (
                <span>
                    {newLegislator ? (
                        <Link
                            href={ROUTES.legislator(newLegislator.id)}
                            className="underline decoration-1 underline-offset-2 hover:opacity-80"
                        >
                            {newLegislator.full_name}
                        </Link>
                    ) : (
                        "A new representative"
                    )}{" "}
                    has been seated as your new representative for {districtLabel}.
                </span>
            );
            break;
    }

    const accessibleText = (() => {
        switch (notification.reassignment_type) {
            case "district_changed":
                return PARITY_COPY.reassignment.districtChanged(districtLabel, newLegislator?.full_name ?? "assigned");
            case "successor_seeded":
                return PARITY_COPY.reassignment.successorSeeded(
                    newLegislator?.full_name ?? "A new representative",
                    oldLegislator?.full_name ?? "your former representative",
                    districtLabel,
                );
            case "vacant_seat":
                return PARITY_COPY.reassignment.vacantSeat(
                    oldLegislator?.full_name ?? "Your representative",
                    districtLabel,
                );
            case "vacancy_filled":
                return PARITY_COPY.reassignment.vacancyFilled(
                    newLegislator?.full_name ?? "A new representative",
                    districtLabel,
                );
        }
    })();

    return (
        <div className="mx-auto flex w-full max-w-[calc(var(--content-max)+6rem)] flex-col gap-3 px-4 py-3 sm:flex-row sm:items-center sm:justify-between md:px-6">
            <div className="flex min-w-0 items-start gap-2.5">
                <Icon className="mt-0.5 size-4 shrink-0 text-info" aria-hidden="true" />
                <p
                    className="break-words text-sm font-semibold leading-snug text-foreground"
                    data-testid="reassignment-banner-text"
                    aria-label={accessibleText}
                >
                    {message}
                </p>
            </div>
            <div className="flex shrink-0 items-center gap-2 self-end sm:self-auto">
                {newLegislator && (
                    <Link
                        href={ROUTES.legislator(newLegislator.id)}
                        className="inline-flex min-h-11 items-center justify-center gap-1.5 rounded-xl border border-border-strong bg-background px-3 py-2 text-xs font-semibold shadow-neo-sm transition hover:bg-accent focus-visible:ring-2"
                        data-testid="reassignment-banner-link"
                    >
                        {PARITY_COPY.reassignment.viewProfile}
                        <ArrowRight className="size-3.5" aria-hidden="true" />
                    </Link>
                )}
                <button
                    type="button"
                    onClick={() => onDismiss(notification.id)}
                    className="inline-flex min-h-11 min-w-11 items-center justify-center rounded-xl px-3 py-2 text-xs font-semibold underline underline-offset-4 transition hover:opacity-90 focus-visible:ring-2"
                    data-testid="reassignment-banner-dismiss"
                >
                    {PARITY_COPY.reassignment.dismiss}
                </button>
            </div>
        </div>
    );
};

export const ReassignmentBanner: React.FC = () => {
    const { notifications, dismiss } = useReassignmentNotifications();

    if (notifications.length === 0) return null;

    return (
        <aside
            aria-label={PARITY_COPY.reassignment.ariaLabel}
            aria-live="polite"
            aria-atomic="true"
            data-testid="reassignment-banner"
            className="block border-b-neo border-border bg-info/15 text-foreground"
        >
            <div className="divide-y divide-border/40">
                {notifications.map((notification) => (
                    <ReassignmentBannerItem key={notification.id} notification={notification} onDismiss={dismiss} />
                ))}
            </div>
        </aside>
    );
};

export default ReassignmentBanner;
