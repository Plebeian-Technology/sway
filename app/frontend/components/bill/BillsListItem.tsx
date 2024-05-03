/** @format */
import { IS_MOBILE_PHONE, ROUTES } from "app/frontend/sway_constants";
import { titleize } from "app/frontend/sway_utils";
import { useCallback } from "react";

import { Button, Image } from "react-bootstrap";
import { FiInfo } from "react-icons/fi";
import { sway } from "sway";

import VoteButtonsContainer from "../uservote/VoteButtonsContainer";
import BillChartsContainer from "./charts/BillChartsContainer";
import { BillChartFilters } from "./charts/constants";
import { useLocale, useLocaleName } from "app/frontend/hooks/useLocales";

interface IProps {
    bill: sway.IBill;
    organizations?: sway.IOrganization[];
    userVote?: sway.IUserVote;
    index: number;
    isLastItem: boolean;
}

const BillsListItem: React.FC<IProps> = ({ bill, userVote, index, isLastItem }) => {
    const [userLocale] = useLocale();
    const userLocaleName = useLocaleName();

    const { category, externalId, title, votedate } = bill;

    const handleGoToSingleBill = useCallback(() => {
        // navigate(ROUTES.bill(userLocaleName, externalId));
    }, [userLocaleName]);

    return (
        <div
            className={`row py-3 justify-content-center ${
                !isLastItem ? "border-bottom border-2" : ""
            }`}
        >
            <div className="col">
                <div className="row mb-3">
                    <div className="col-3 text-start">
                        <Image
                            alt={`${index + 1}`}
                            src={userLocaleName ? `/avatars/${userLocaleName}.svg` : "/logo300.png"}
                            rounded
                            thumbnail
                        />
                    </div>
                    <div className="col text-end">
                        {category && <span className="bold">{titleize(category)}</span>}
                    </div>
                </div>
                <div className="row">
                    <div className="bold">{`Bill ${externalId}`}</div>
                    <div>{title}</div>
                </div>

                {bill && <VoteButtonsContainer bill={bill} userVote={userVote} />}
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
                    {userLocale &&
                        votedate &&
                        // new Date(votedate) < new Date(userLocale.currentSessionStartDate) && (
                        new Date(votedate) < new Date() && (
                            <div className={"row g-0 my-2"}>
                                <span>
                                    Legislators that voted on this bill may no longer be in office.
                                </span>
                            </div>
                        )}
                </div>
            </div>
            {userLocale && userVote && !IS_MOBILE_PHONE && (
                <div className="col">
                    <BillChartsContainer
                        bill={bill}
                        userLocale={userLocale}
                        userVote={userVote}
                        filter={BillChartFilters.total}
                    />
                </div>
            )}
        </div>
    );
};

export default BillsListItem;
