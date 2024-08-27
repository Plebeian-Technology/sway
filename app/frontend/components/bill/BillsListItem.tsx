/** @format */
import { IS_MOBILE_PHONE, ROUTES } from "app/frontend/sway_constants";
import { titleize } from "app/frontend/sway_utils";
import { lazy, useCallback } from "react";

import { Button } from "react-bootstrap";
import { FiInfo } from "react-icons/fi";
import { sway } from "sway";

import { router } from "@inertiajs/react";
import SuspenseFullScreen from "app/frontend/components/dialogs/SuspenseFullScreen";
import LocaleAvatar from "app/frontend/components/locales/LocaleAvatar";
import { useLocale } from "app/frontend/hooks/useLocales";
import VoteButtonsContainer from "../uservote/VoteButtonsContainer";
import { BillChartFilters } from "./charts/constants";

const BillChartsContainer = lazy(() => import("./charts/BillChartsContainer"));

interface IProps {
    bill: sway.IBill;
    organizations?: sway.IOrganization[];
    userVote?: sway.IUserVote;
    index: number;
    isLastItem: boolean;
}

const BillsListItem: React.FC<IProps> = ({ bill, userVote, isLastItem }) => {
    const [locale] = useLocale();

    const { category, externalId, title } = bill;

    const handleGoToSingleBill = useCallback(() => {
        router.visit(ROUTES.bill(bill.id));
    }, [bill.id]);

    return (
        <div className={`row py-3 justify-content-center ${!isLastItem ? "border-bottom border-2" : ""}`}>
            <div className="col">
                <div className="row mb-3">
                    <div className="col-3 text-start">
                        <LocaleAvatar />
                    </div>
                    <div className="col text-end">{category && <span className="bold">{titleize(category)}</span>}</div>
                </div>
                <div className="row">
                    <div className="bold">{`Bill ${externalId}`}</div>
                    <div>{title}</div>
                </div>

                <VoteButtonsContainer bill={bill} userVote={userVote} />
                <div className="col text-center w-100">
                    <Button
                        variant="outline-primary"
                        style={{ opacity: "70%" }}
                        onClick={handleGoToSingleBill}
                        className="p-3"
                    >
                        <FiInfo />
                        &nbsp;<span className="align-text-top">Show More Info</span>
                    </Button>
                    {bill.voteDateTimeUtc && !bill.active && (
                        <div className={"row g-0 my-2"}>
                            <span>Legislators that voted on this bill may no longer be in office.</span>
                        </div>
                    )}
                </div>
            </div>
            {locale && userVote && !IS_MOBILE_PHONE && (
                <div className="col">
                    <SuspenseFullScreen>
                        <BillChartsContainer
                            bill={bill}
                            locale={locale}
                            userVote={userVote}
                            filter={BillChartFilters.total}
                        />
                    </SuspenseFullScreen>
                </div>
            )}
        </div>
    );
};

export default BillsListItem;
