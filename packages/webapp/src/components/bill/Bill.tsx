/** @format */

import { Link as MaterialLink, Typography } from "@material-ui/core";
import {
    CURRENT_COUNCIL_START_DATE,
    DEFAULT_ORGANIZATION,
    VOTING_WEBSITES_BY_LOCALE,
} from "@sway/constants";
import {
    findLocale,
    isEmptyObject,
    IS_DEVELOPMENT,
    titleize,
} from "@sway/utils";
import React, { useEffect, useState } from "react";
import { useHistory, useParams } from "react-router-dom";
import { sway } from "sway";
import { useBill } from "../../hooks/bills";
import { signInAnonymously } from "../../users/signinAnonymously";
import { handleError, IS_COMPUTER_WIDTH, SWAY_COLORS } from "../../utils";
import FullWindowLoading from "../dialogs/FullWindowLoading";
import CenteredDivRow from "../shared/CenteredDivRow";
import ShareButtons from "../social/ShareButtons";
import { ILocaleUserProps } from "../user/UserRouter";
import VoteButtonsContainer from "../uservote/VoteButtonsContainer";
import BillArguments from "./BillArguments";
import BillSummaryAudio from "./BillSummaryAudio";
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

const Bill: React.FC<IProps> = ({
    locale,
    user,
    bill,
    organizations,
    userVote,
}) => {
    const history = useHistory();
    const params: { billFirestoreId: string; localeName: string } = useParams();
    const [showSummary, setShowSummary] = useState<sway.IOrganization | null>(
        null,
    );
    const [isUserVoted, setIsUserVoted] = useState<boolean>(!!userVote);

    const uid = user?.uid;
    const billFirestoreId = bill ? bill.firestoreId : params.billFirestoreId;

    const paramsLocale = findLocale(params.localeName);
    const selectedLocale = locale || paramsLocale;
    const localeName = selectedLocale?.name;

    const [hookedBill, getBill] = useBill(billFirestoreId);

    useEffect(() => {
        const load = async () => {
            if (locale || bill) return;

            if (!user) {
                signInAnonymously()
                    .then(() => getBill(selectedLocale, uid))
                    .catch(handleError);
            } else {
                getBill(selectedLocale, uid);
            }
        };
        load().catch(handleError);
    }, [selectedLocale, uid, bill, getBill]);

    const selectedBill = bill || hookedBill?.bill;
    if (!selectedBill) {
        IS_DEVELOPMENT && console.log("(dev) BILL.tsx - NO SELECTED BILL");
        return <FullWindowLoading message={"Loading Bill..."} />;
    }
    if (user && !user.locales && !user.isAnonymous) {
        IS_DEVELOPMENT && console.log("(dev) BILL.tsx - LOADING USER");
        return <FullWindowLoading message={"Loading Bill..."} />;
    }

    const handleNavigateToLegislator = (e: React.MouseEvent<HTMLElement>) => {
        e.preventDefault();
        e.stopPropagation();

        history.push({
            pathname: `/legislator/${localeName}/${bill.sponsorExternalId}`,
        });
    };

    const onUserVoteUpdateBill = () => {
        setIsUserVoted(true);
    };

    const getSummary = (): { summary: string; byline: string } => {
        if (bill.summaries.sway) {
            return { summary: bill.summaries.sway, byline: "Sway" };
        }
        if (bill.swaySummary) {
            return { summary: bill.swaySummary, byline: "Sway" };
        }
        return { summary: "", byline: "" };
    };

    const renderCharts = () => {
        if (!userVote) return null;
        if (IS_COMPUTER_WIDTH) {
            return <BillChartsContainer bill={bill} />;
        }
        return <BillMobileChartsContainer bill={bill} />;
    };

    const { summary } = getSummary();

    return (
        <div className={"bill-container"}>
            {selectedBill.votedate &&
                new Date(selectedBill.votedate) <
                    CURRENT_COUNCIL_START_DATE && (
                    <div className={"text-container expired-text"}>
                        <Typography variant="h6">
                            {
                                "Legislators that voted on this bill may no longer be in office."
                            }
                        </Typography>
                    </div>
                )}
            <div
                className={"text-container"}
                style={{ textAlign: "center", marginTop: 20 }}
            >
                <Typography variant="h6">{selectedBill.title}</Typography>
            </div>
            <div style={{ textAlign: "center" }}>
                {selectedBill.votedate ? (
                    <Typography variant="body2">{`Legislators Voted On - ${selectedBill.votedate}`}</Typography>
                ) : (
                    <Typography variant="body2" style={{ color: SWAY_COLORS.primary, fontWeight: "bold" }}>
                        {"Legislators have not yet voted on this bill."}
                    </Typography>
                )}
            </div>
            <VoteButtonsContainer
                user={user}
                locale={locale}
                bill={bill}
                updateBill={onUserVoteUpdateBill}
                organizations={organizations}
                userVote={userVote}
            />
            {selectedBill.active &&
                user &&
                user.isRegistrationComplete &&
                isUserVoted && (
                    <ShareButtons
                        bill={bill}
                        locale={locale}
                        user={user}
                        userVote={userVote}
                    />
                )}
            <div className={classes.container}>
                <div className={classes.textContainer}>
                    <CenteredDivRow style={{ justifyContent: "flex-start" }}>
                        <Typography className={classes.title} component="h4">
                            {"Sway Summary"}
                        </Typography>
                        {bill?.summaries?.swayAudioBucketPath && (
                            <BillSummaryAudio
                                swayAudioByline={
                                    bill.summaries.swayAudioByline || "Sway"
                                }
                                swayAudioBucketPath={
                                    bill.summaries.swayAudioBucketPath
                                }
                            />
                        )}
                    </CenteredDivRow>
                    <BillSummaryModal
                        localeName={localeName}
                        summary={summary}
                        swayAudioByline={bill?.summaries?.swayAudioByline}
                        swayAudioBucketPath={
                            bill?.summaries?.swayAudioBucketPath
                        }
                        billFirestoreId={selectedBill.firestoreId}
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
                        href={`/legislators/${selectedBill.sponsorExternalId}`}
                        variant="body1"
                        style={{ fontWeight: "bold" }}
                    >
                        {titleize(
                            selectedBill.sponsorExternalId
                                .split("-")
                                .slice(0, 2)
                                .join(" "),
                        )}
                    </MaterialLink>
                </div>
            </div>
            {selectedBill.relatedBillIds &&
                selectedBill.relatedBillIds.length > 0 && (
                    <div className={"text-container"}>
                        <div className={"text-sub-container"}>
                            <Typography
                                className={"bolded-text"}
                                component="h4"
                            >
                                {"Related Bills: "}
                            </Typography>
                            <Typography
                                component="span"
                                variant="body1"
                                color="textPrimary"
                            >
                                {selectedBill.relatedBillIds}
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
                            href={selectedBill.link}
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
