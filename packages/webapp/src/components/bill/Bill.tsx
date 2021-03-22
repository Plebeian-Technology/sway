/** @format */

import {
    createStyles,
    Link as MaterialLink,
    makeStyles,
    Typography,
} from "@material-ui/core";
import {
    CONGRESS_LOCALE,
    CURRENT_COUNCIL_START_DATE,
    DEFAULT_ORGANIZATION,
    ROUTES,
    VOTING_WEBSITES_BY_LOCALE,
} from "@sway/constants";
import {
    findLocale,
    isEmptyObject,
    logDev,
    titleize,
    userLocaleFromLocales,
} from "@sway/utils";
import React, { useEffect, useMemo, useState } from "react";
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
    locale: sway.ILocale | undefined;
    organizations?: sway.IOrganization[];
    userVote?: sway.IUserVote;
}

// const classes = {
//     container: "bill-arguments-container",
//     subContainer: "bill-arguments-sub-container",
//     textContainer: "bill-arguments-text-container",
//     iconContainer: "bill-arguments-org-icon-container",
//     title: "bill-arguments-text-container-title",
//     text: "bill-arguments-text",
// };

const LOAD_ERROR_MESSAGE =
    "Error loading Bill of the Week. Please navigate back to https://app.sway.vote.";

const useStyles = makeStyles(() => {
    return createStyles({
        container: {
            display: "flex",
            flexDirection: "column",
            alignItems: "space-between",
            marginLeft: 10,
            marginRight: 10,
        },
        subContainer: {
            display: "flex",
            flexDirection: "row",
            justifyContent: "space-around",
        },
        textContainer: {
            display: "flex",
            flexDirection: "column",
            alignItems: "center",
            marginLeft: 10,
            marginRight: 10,
        },
        text: {
            overflow: "hidden",
            textOverflow: "ellipsis",
            display: "-webkit-box",
            "-webkit-line-clamp": 4,
            "-webkit-box-orient": "vertical",
            maxWidth: "50ch",
            margin: "10px auto",
            WebkitLineClamp: 4,
        },
        title: {
            fontWeight: 700,
        },
    });
});

const Bill: React.FC<IProps> = ({
    locale,
    user,
    bill,
    organizations,
    userVote,
}) => {
    const history = useHistory();
    const classes = useStyles();
    const params: { billFirestoreId: string; localeName: string } = useParams();
    const [showSummary, setShowSummary] = useState<sway.IOrganization | null>(
        null,
    );

    const uid = user?.uid;
    const billFirestoreId = bill ? bill.firestoreId : params.billFirestoreId;

    const paramsLocale = findLocale(params.localeName);

    const selectedLocale: sway.ILocale =
        locale || paramsLocale || CONGRESS_LOCALE;
    const localeName = selectedLocale?.name;

    const [hookedBill, getBill] = useBill(billFirestoreId);

    useEffect(() => {
        const load = async () => {
            if (hookedBill) return;
            if (!selectedLocale) return;

            if (!user) {
                signInAnonymously()
                    .then(() => getBill(selectedLocale, uid))
                    .catch((error: Error) => {
                        handleError(error, LOAD_ERROR_MESSAGE);
                    });
            } else {
                logDev("getting new hookedBill");
                getBill(selectedLocale, uid);
            }
        };
        load().catch((error: Error) => {
            handleError(error, LOAD_ERROR_MESSAGE);
        });
    }, [selectedLocale, uid, hookedBill, getBill]);

    const selectedBill = hookedBill?.bill || bill;
    const selectedUserVote = hookedBill?.userVote || userVote;
    if (!selectedBill) {
        logDev("BILL.tsx - NO SELECTED BILL");
        return <FullWindowLoading message={"Loading Bill..."} />;
    }
    if (user && !user.locales && !user.isAnonymous) {
        logDev("BILL.tsx - LOADING USER");
        return <FullWindowLoading message={"Loading Bill..."} />;
    }

    const handleNavigate = (pathname: string) => {
        history.push({ pathname });
    };

    const handleNavigateToLegislator = (e: React.MouseEvent<HTMLElement>) => {
        e.preventDefault();
        e.stopPropagation();

        handleNavigate(`/legislator/${localeName}/${bill.sponsorExternalId}`);
    };

    const onUserVoteUpdateBill = () => {
        if (!selectedLocale) {
            logDev("No selectedLocale, skip get bill after user vote.");
            return;
        }

        getBill(selectedLocale, uid);
    };

    const getSummary = (): { summary: string; byline: string } => {
        if (bill?.summaries?.sway) {
            return { summary: bill.summaries.sway, byline: "Sway" };
        }
        if (bill?.swaySummary) {
            return { summary: bill.swaySummary, byline: "Sway" };
        }
        return { summary: "", byline: "" };
    };

    const renderCharts = useMemo(() => {
        if (!selectedUserVote) return null;
        if (!locale?.name) return null;

        const userLocale = user && userLocaleFromLocales(user, locale.name);
        if (!userLocale) return null;

        if (IS_COMPUTER_WIDTH) {
            return (
                <BillChartsContainer
                    bill={selectedBill}
                    userLocale={userLocale}
                    userVote={selectedUserVote}
                />
            );
        }
        return (
            <BillMobileChartsContainer
                bill={selectedBill}
                userLocale={userLocale}
                userVote={selectedUserVote}
            />
        );
    }, [selectedUserVote, selectedBill]);

    const { summary } = getSummary();

    const getLegislatorsVotedText = (() => {
        if (!selectedBill.votedate) {
            return "Legislators have not yet voted on a final version of this bill.";
        }
        if (!selectedBill.houseVoteDate && !selectedBill.senateVoteDate) {
            return `Legislators voted on - ${selectedBill.votedate}`;
        }
        if (selectedBill.houseVoteDate && !selectedBill.senateVoteDate) {
            return `House voted on - ${selectedBill.houseVoteDate}`;
        }
        if (!selectedBill.houseVoteDate && selectedBill.senateVoteDate) {
            return `Senate voted on - ${selectedBill.senateVoteDate}`;
        }
        return `House voted on - ${selectedBill.houseVoteDate} and Senate voted on - ${selectedBill.senateVoteDate}`;
    })();

    const title = (() => {
        return `${selectedBill.externalId.toUpperCase()} - ${
            selectedBill.title
        }`;
    })();

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
            <Typography variant="h6">{title}</Typography>
            {selectedBill.votedate ? (
                <Typography variant="body2">
                    {getLegislatorsVotedText}
                </Typography>
            ) : (
                <Typography
                    variant="body2"
                    style={{
                        margin: "20px auto",
                        color: SWAY_COLORS.primary,
                        fontWeight: "bold",
                    }}
                >
                    {getLegislatorsVotedText}
                </Typography>
            )}
            {user && selectedLocale && selectedBill && (
                <VoteButtonsContainer
                    user={user}
                    locale={selectedLocale}
                    bill={selectedBill}
                    updateBill={onUserVoteUpdateBill}
                    organizations={organizations}
                    userVote={selectedUserVote}
                />
            )}
            {selectedLocale && selectedUserVote && user && (
                <ShareButtons
                    bill={selectedBill}
                    locale={selectedLocale}
                    user={user}
                    userVote={selectedUserVote}
                />
            )}
            {selectedUserVote && (
                <MaterialLink
                    style={{ marginTop: 20, marginBottom: 20 }}
                    onClick={() => handleNavigate(ROUTES.legislators)}
                >
                    <Typography>
                        See how you compare to your representatives.
                    </Typography>
                </MaterialLink>
            )}
            {renderCharts}
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
                        billFirestoreId={selectedBill.firestoreId}
                        organization={DEFAULT_ORGANIZATION}
                        selectedOrganization={showSummary}
                        setSelectedOrganization={setShowSummary}
                    />
                </div>
            </div>
            {!isEmptyObject(organizations) && (
                <BillArguments
                    bill={selectedBill}
                    organizations={organizations}
                    localeName={localeName}
                />
            )}
            <div className={"bill-extra-info-container"}>
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

                {localeName && (
                    <div className={"text-container"}>
                        <div className={"text-sub-container"}>
                            <Typography
                                className={"bolded-text"}
                                component="h4"
                            >
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
                )}
            </div>
        </div>
    );
};

export default Bill;
