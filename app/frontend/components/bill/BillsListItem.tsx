/** @format */
import { IS_MOBILE_PHONE, ROUTES } from "app/frontend/sway_constants";
import { titleize } from "app/frontend/sway_utils";
import { lazy, Suspense, useCallback } from "react";

import { Button } from "react-bootstrap";
import { FiInfo } from "react-icons/fi";
import { sway } from "sway";

import { Link as InertiaLink, router } from "@inertiajs/react";
import CenteredLoading from "app/frontend/components/dialogs/CenteredLoading";
import LocaleAvatar from "app/frontend/components/locales/LocaleAvatar";
import { useLocale } from "app/frontend/hooks/useLocales";
import { usePollBillOnUserVote } from "app/frontend/hooks/usePollBillOnUserVote";
import VoteButtonsContainer from "../uservote/VoteButtonsContainer";
import { BillChartFilters } from "./charts/constants";

const BillChartsContainer = lazy(() => import("./charts/BillChartsContainer"));

interface IProps {
    bill: sway.IBill & { user_vote?: sway.IUserVote };
    organizations?: sway.IOrganization[];
    index: number;
    isLastItem: boolean;
    inView: boolean;
}

const BillsListItem: React.FC<IProps> = ({ bill, isLastItem, inView }) => {
    const [locale] = useLocale();

    const { id, category, external_id, title, user_vote } = bill;

    const handleGoToSingleBill = useCallback(() => {
        router.visit(ROUTES.bill(bill.id));
    }, [bill.id]);

    const { onUserVote, onScoreReceived } = usePollBillOnUserVote();

    if (!inView) {
        return null;
    }

    return (
        <div className={`row py-3 justify-content-center ${!isLastItem ? "border-bottom border-2" : ""}`}>
            <div className="col">
                <div className="row mb-3">
                    <div className="col-3 text-start">
                        <LocaleAvatar />
                    </div>
                    <div className="col text-end">{category && <span className="bold">{titleize(category)}</span>}</div>
                </div>
                <InertiaLink href={ROUTES.bill(id)} className="no-underline">
                    <div className="row">
                        <div className="text-black bold">{`Bill ${external_id}`}</div>
                        <div className="text-secondary">{title}</div>
                    </div>
                </InertiaLink>

                <VoteButtonsContainer bill={bill} user_vote={user_vote} onUserVote={onUserVote} />

                <div className="col text-center w-100">
                    <Button
                        variant="outline-primary"
                        style={{ opacity: "70%" }}
                        onClick={handleGoToSingleBill}
                        className="py-3 px-5"
                    >
                        <FiInfo />
                        &nbsp;<span className="align-text-top">Show More Info</span>
                    </Button>
                    {bill.vote_date_time_utc && !bill.active && (
                        <div className={"row g-0 my-2"}>
                            <span>Legislators that voted on this bill may no longer be in office.</span>
                        </div>
                    )}
                </div>
            </div>
            {locale && user_vote && !IS_MOBILE_PHONE && (
                <div className="col">
                    <Suspense fallback={<CenteredLoading />}>
                        <BillChartsContainer
                            bill={bill}
                            locale={locale}
                            user_vote={user_vote}
                            onScoreReceived={onScoreReceived}
                            filter={BillChartFilters.total}
                        />
                    </Suspense>
                </div>
            )}
        </div>
    );
};

export default BillsListItem;
