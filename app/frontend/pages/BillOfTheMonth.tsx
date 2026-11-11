import { Link, router, usePage, usePoll } from "@inertiajs/react";
import { createElement, Suspense } from "react";

import { useActionCableReconnect } from "app/frontend/hooks/useActionCableReconnect";
import { useActiveThemeId } from "app/frontend/hooks/useActiveThemeId";
import { useSwayLocale, useSwayLocales } from "app/frontend/hooks/useSwayLocales";
import { usePullToRefresh } from "app/frontend/hooks/usePullToRefresh";
import { useScoreSubscription } from "app/frontend/hooks/useScoreSubscription";
import BillEditLink from "app/frontend/components/bill/BillEditLink";
import { billLayoutFor } from "app/frontend/components/bill/layouts";
import ThemeLayoutPlaceholder from "app/frontend/components/bill/ThemeLayoutPlaceholder";
import { Label } from "app/frontend/components/ui/label";
import SwayLocalePicker from "app/frontend/components/locales/SwayLocalePicker";
import { ROUTES } from "app/frontend/sway_constants";
import { PARITY_COPY } from "app/frontend/sway_constants/parityCopy";
import { toFormattedLocaleName } from "app/frontend/sway_utils";
import { sway } from "sway";

interface IProps {
    bill?: sway.IBill;
    sponsor: sway.ILegislator;
    legislators?: sway.ILegislator[];
    organizations: sway.IBillOrganizationPosition[];
    legislator_votes: sway.ILegislatorVote[];
    user_vote?: sway.IUserVote;
    bill_score?: sway.IBillScore;
    districts?: sway.IDistrict[];
}

// @lat: [[client-caches-and-identity#Bill refresh feedback]]
const POLLING_PROPS = ["bill", "sponsor", "organizations", "user_vote", "bill_score"];

const BillOfTheMonth: React.FC<IProps> = ({ bill, sponsor, organizations, user_vote, bill_score }) => {
    const user = usePage<sway.IPageProps>().props?.user;
    const { options } = useSwayLocales();
    const [swayLocale, getSwayLocale, pendingSwayLocaleId] = useSwayLocale();
    const formattedSwayLocaleName = toFormattedLocaleName(swayLocale?.name ?? "");

    usePoll(15000, { only: POLLING_PROPS }, { background: "pause" });
    const isAwaitingScoreUpdate = useScoreSubscription(POLLING_PROPS, Boolean(user));
    useActionCableReconnect(POLLING_PROPS);
    usePullToRefresh({ onRefresh: () => router.reload() });

    // @lat: [[client-caches-and-identity#Bill refresh feedback]]
    const layout = billLayoutFor(useActiveThemeId());

    return (
        <div className="space-y-6">
            <div className="flex items-center gap-3 rounded-xl border border-border bg-surface-2 px-4 py-3">
                <Label htmlFor="v2-locale" className="shrink-0">
                    Locale
                </Label>
                <SwayLocalePicker
                    id="v2-locale"
                    options={options}
                    value={pendingSwayLocaleId ?? swayLocale?.id}
                    onChange={getSwayLocale}
                    className="min-w-0 flex-1"
                />
            </div>

            {bill ? (
                <div>
                    {/* @lat: [[identity-and-access#Identity and access#The admin gate is a lint rule#An admin affordance in the reader's page is a convenience, not a gate]] */}
                    <BillEditLink billId={bill.id} billIdentifier={bill.external_id} variant="detail" />
                    <Suspense fallback={<ThemeLayoutPlaceholder shape="detail" />}>
                        {createElement(layout, {
                            bill,
                            sponsor,
                            organizations,
                            user_vote,
                            bill_score,
                            isAwaitingScoreUpdate,
                        })}
                    </Suspense>
                </div>
            ) : (
                <div
                    className="space-y-3 rounded-xl border border-border bg-surface-2 px-4 py-6"
                    data-testid="botm-empty"
                >
                    <p className="text-lg font-semibold">
                        {PARITY_COPY.billOfTheMonth.noneForLocale(formattedSwayLocaleName)}
                    </p>
                    <Link href={ROUTES.pastBillsOfTheMonth} className="inline-flex items-center gap-2 underline">
                        {PARITY_COPY.billOfTheMonth.browseBills}
                    </Link>
                </div>
            )}
        </div>
    );
};

export default BillOfTheMonth;
