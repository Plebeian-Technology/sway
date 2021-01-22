/** @format */

import { Link as MaterialLink, Typography } from "@material-ui/core";
import {
    CURRENT_COUNCIL_START_DATE,
    DEFAULT_ORGANIZATION,
    VOTING_WEBSITES_BY_LOCALE
} from "@sway/constants";
import { isEmptyObject, titleize } from "@sway/utils";
import React from "react";
import { useHistory } from "react-router-dom";
import { sway } from "sway";
import { isComputerWidth } from "../../utils";
import { ILocaleUserProps } from "../user/UserRouter";
import VoteButtonsContainer from "../uservote/VoteButtonsContainer";
import BillArguments from "./BillArguments";
import BillSummaryModal from "./BillSummaryModal";
import BillChartsContainer from "./charts/BillChartsContainer";
import BillMobileChartsContainer from "./charts/BillMobileChartsContainer";
interface IProps extends ILocaleUserProps {
    bill: sway.IBill;
    locale: sway.ILocale;
    organizations?: sway.IOrganization[];
    userVote?: sway.IUserVote;
}

const classes = {
    container: "bill-arguments-container",
    subContainer: "bill-arguments-sub-container",
    textContainer: "bill-arguments-text-container",
    iconContainer: "bill-arguments-org-icon-container",
    title: "bill-arguments-text-container-title",
    text: "bill-arguments-text",
};

const Bill: React.FC<IProps> = ({ locale, user, bill, organizations, userVote }) => {
    const history = useHistory();
    const localeName = locale.name;
    const [
        showSummary,
        setShowSummary,
    ] = React.useState<sway.IOrganization | null>(null);

    const handleNavigateToLegislator = (e: React.MouseEvent<HTMLElement>) => {
        e.preventDefault();
        e.stopPropagation();

        history.push({
            pathname: `/legislator/${locale.name}/${bill.sponsorExternalId}`,
        });
    };

    const renderCharts = () => {
        if (!userVote) return null;
        if (isComputerWidth) {
            return <BillChartsContainer bill={bill} />;
        }
        return <BillMobileChartsContainer bill={bill} />;
    };

    return (
        <div className={"bill-container"}>
            {bill.votedate &&
                new Date(bill.votedate) < CURRENT_COUNCIL_START_DATE && (
                    <div className={"text-container expired-text"}>
                        <Typography variant="h6">
                            {
                                "Legislators that voted on this bill may no longer be in office."
                            }
                        </Typography>
                    </div>
                )}
            <div className={"text-container"} style={{ textAlign: "center" }}>
                <Typography variant="h6">{bill.title}</Typography>
            </div>
            <VoteButtonsContainer
                user={user}
                locale={locale}
                bill={bill}
                organizations={organizations}
                userVote={userVote}
            />
            <div className={classes.container}>
                <div className={classes.textContainer}>
                    <Typography className={classes.title} component="h4">
                        {"Sway Summary"}
                    </Typography>

                    <BillSummaryModal
                        localeName={localeName}
                        summary={bill?.summaries?.sway}
                        billFirestoreId={bill.firestoreId}
                        organization={DEFAULT_ORGANIZATION}
                        selectedOrganization={showSummary}
                        setSelectedOrganization={setShowSummary}
                    />
                </div>
            </div>
            {!isEmptyObject(organizations) && (
                <BillArguments
                    bill={bill}
                    organizations={organizations}
                    localeName={localeName}
                />
            )}
            <div className={"text-container"}>
                <div className={"text-sub-container"}>
                    <Typography className={"bolded-text"} component="h4">
                        {"Legislative Sponsor: "}
                    </Typography>
                    <MaterialLink
                        onClick={handleNavigateToLegislator}
                        href={`/legislators/${bill.sponsorExternalId}`}
                        variant="body1"
                        style={{ fontWeight: "bold" }}
                    >
                        {titleize(
                            bill.sponsorExternalId
                                .split("-")
                                .slice(0, 2)
                                .join(" "),
                        )}
                    </MaterialLink>
                </div>
            </div>
            {bill.relatedBillIds && bill.relatedBillIds.length > 0 && (
                <div className={"text-container"}>
                    <div className={"text-sub-container"}>
                        <Typography className={"bolded-text"} component="h4">
                            {"Related Bills: "}
                        </Typography>
                        <Typography
                            component="span"
                            variant="body1"
                            color="textPrimary"
                        >
                            {bill.relatedBillIds}
                        </Typography>
                    </div>
                </div>
            )}

            {renderCharts()}
            <div className={"text-container"}>
                <div className={"text-sub-container"}>
                    <Typography className={"bolded-text"} component="h4">
                        {"Data From: "}
                    </Typography>
                    <Typography>
                        <MaterialLink
                            href={bill.link}
                            rel="noreferrer"
                            variant="body2"
                        >
                            {VOTING_WEBSITES_BY_LOCALE[localeName]}
                        </MaterialLink>
                    </Typography>
                </div>
            </div>
        </div>
    );
};

export default Bill;
