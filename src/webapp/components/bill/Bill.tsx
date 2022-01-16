/** @format */
import { makeStyles } from "@mui/styles";
import { Link as MaterialLink, Typography } from "@mui/material";
import {
    CONGRESS_LOCALE,
    DEFAULT_ORGANIZATION,
    ROUTES,
    VOTING_WEBSITES_BY_LOCALE,
} from "src/constants";
import {
    findLocale,
    isEmptyObject,
    logDev,
    titleize,
    userLocaleFromLocales,
} from "src/utils";
import React, { useEffect, useState } from "react";
import { useNavigate, useParams } from "react-router-dom";
import { sway } from "sway";
import { useBill } from "../../hooks/bills";
import { useCancellable } from "../../hooks/cancellable";
import { signInAnonymously } from "../../users/signinAnonymously";
import { handleError, IS_COMPUTER_WIDTH, SWAY_COLORS } from "../../utils";
import FullWindowLoading from "../dialogs/FullWindowLoading";
import CenteredDivCol from "../shared/CenteredDivCol";
import CenteredDivRow from "../shared/CenteredDivRow";
import FlexColumnDiv from "../shared/FlexColumnDiv";
import ShareButtons from "../social/ShareButtons";
import { ILocaleUserProps } from "../user/UserRouter";
import VoteButtonsContainer from "../uservote/VoteButtonsContainer";
import BillActionLinks from "./BillActionLinks";
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

const LOAD_ERROR_MESSAGE =
    "Error loading Bill of the Week. Please navigate back to https://app.sway.vote.";

const useStyles = makeStyles({
    titleContainer: {
        textAlign: "center",
    },
    title: {
        fontWeight: 700,
        paddingBottom: 10,
    },
    voteDateText: {
        margin: "20px auto",
        color: SWAY_COLORS.primary,
        fontWeight: "bold",
        textAlign: "center",
        lineHeight: 1,
    },
    extraInfo: {
        textAlign: "left",
        width: "100%",
    },
    extraInfoTextContainer: {
        display: "flex",
        flexDirection: "column",
        margin: 10,
    },
    extraInfoText: {
        display: "inline",
        margin: 10,
    },
    extraInfoExpiredText: {
        color: SWAY_COLORS.tertiary,
        textAlign: "center",
    },
    pointer: {
        cursor: "pointer",
    },
    horizontalSpace: {
        paddingLeft: 5,
        paddingRight: 5,
    },
});

const withHorizontalMargin = { marginLeft: 10, marginRight: 10 };

const Bill: React.FC<IProps> = ({
    locale,
    user,
    bill,
    organizations,
    userVote,
}) => {
    const makeCancellable = useCancellable();
    const navigate = useNavigate();
    const classes = useStyles();
    const params = useParams() as {
        billFirestoreId: string;
        localeName: string;
    };
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
        makeCancellable(load(), () =>
            logDev("Cancelled Bill.getBill in useEffect"),
        ).catch((error: Error) => {
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
        navigate({ pathname });
    };

    const handleNavigateToLegislator = (e: React.MouseEvent<HTMLElement>) => {
        e.preventDefault();
        e.stopPropagation();

        handleNavigate(
            ROUTES.legislator(localeName, selectedBill.sponsorExternalId),
        );
    };

    const onUserVoteUpdateBill = () => {
        if (!selectedLocale) {
            logDev("No selectedLocale, skip get bill after user vote.");
            return;
        }

        getBill(selectedLocale, uid);
    };

    const getSummary = (): { summary: string; byline: string } => {
        if (selectedBill?.summaries?.sway) {
            return { summary: selectedBill.summaries.sway, byline: "Sway" };
        }
        if (selectedBill?.swaySummary) {
            return { summary: selectedBill.swaySummary, byline: "Sway" };
        }
        return { summary: "", byline: "" };
    };

    const renderCharts = (() => {
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
    })();

    const { summary } = getSummary();

    const getLegislatorsVotedText = (() => {
        if (!selectedBill.votedate) {
            return (
                <>
                    <Typography variant="body2" className={classes.title}>
                        Legislators have not yet voted on a final version of
                        this bill.
                    </Typography>
                    <br />
                    <Typography variant="body2" className={classes.title}>
                        It may be amended before a final vote.
                    </Typography>
                </>
            );
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
        return (
            <>
                <Typography variant="body2">
                    {`House voted on - ${selectedBill.houseVoteDate}`}
                </Typography>
                <Typography variant="body2">
                    {`Senate voted on - ${selectedBill.senateVoteDate}`}
                </Typography>
            </>
        );
    })();

    const title = (() => {
        return `${selectedBill.externalId.toUpperCase()} - ${
            selectedBill.title
        }`;
    })();

    const getCreatedAt = (b: sway.IBill) => {
        if (!b.createdAt) return new Date();
        const seconds = String(b.createdAt.seconds);
        const nanos = String(b.createdAt.nanoseconds).substring(0, 3);
        return new Date(Number(seconds + nanos));
    };

    return (
        <CenteredDivCol style={{ padding: 10 }}>
            {selectedBill.votedate &&
                new Date(selectedBill.votedate) < // TODO: Change this to locale.currentSessionStartDate
                    new Date(selectedLocale.currentSessionStartDate) && (
                    <CenteredDivCol style={withHorizontalMargin}>
                        <Typography variant="h6">
                            {
                                "Legislators that voted on this bill may no longer be in office."
                            }
                        </Typography>
                    </CenteredDivCol>
                )}
            <div className={classes.titleContainer}>
                <Typography variant="h6">{title}</Typography>
            </div>
            {selectedBill.votedate ? (
                <div>{getLegislatorsVotedText}</div>
            ) : (
                <div className={classes.voteDateText}>
                    {getLegislatorsVotedText}
                </div>
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
            {selectedUserVote && <BillActionLinks />}
            {renderCharts}
            <FlexColumnDiv
                style={{
                    ...withHorizontalMargin,
                    alignItems: "space-between",
                }}
            >
                <CenteredDivCol style={withHorizontalMargin}>
                    <CenteredDivRow style={{ justifyContent: "flex-start" }}>
                        <Typography className={classes.title} component="h4">
                            {"Sway Summary"}
                        </Typography>
                        {selectedLocale &&
                            selectedBill?.summaries?.swayAudioBucketPath && (
                                <BillSummaryAudio
                                    localeName={selectedLocale.name}
                                    swayAudioByline={
                                        selectedBill.summaries
                                            .swayAudioByline || "Sway"
                                    }
                                    swayAudioBucketPath={
                                        selectedBill.summaries
                                            .swayAudioBucketPath
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
                        isUseMarkdown={Boolean(
                            selectedBill &&
                                getCreatedAt(selectedBill) <
                                    new Date("January 1, 2021"),
                        )}
                    />
                </CenteredDivCol>
            </FlexColumnDiv>
            {!isEmptyObject(organizations) && (
                <BillArguments
                    bill={selectedBill}
                    organizations={organizations}
                    localeName={localeName}
                />
            )}
            <div className={classes.extraInfo}>
                <div className={classes.extraInfoTextContainer}>
                    <div className={classes.extraInfoText}>
                        <Typography component="h4">
                            {"Legislative Sponsor: "}
                        </Typography>
                        <MaterialLink
                            onClick={handleNavigateToLegislator}
                            href={ROUTES.legislator(
                                paramsLocale?.name,
                                selectedBill.sponsorExternalId,
                            )}
                            variant="body1"
                            component="span"
                            style={{ fontWeight: "bold", cursor: "pointer" }}
                        >
                            {titleize(
                                selectedBill.sponsorExternalId
                                    .split("-")
                                    .slice(0, 2)
                                    .join(" "),
                            )}
                        </MaterialLink>
                        <Typography variant="body1" component="span">
                            {
                                " - Sway records this person, and any co-sponsors, as voting 'For' the legislation in lieu of a vote."
                            }
                        </Typography>
                    </div>
                </div>
                {selectedBill.relatedBillIds &&
                    selectedBill.relatedBillIds.length > 0 && (
                        <div className={classes.extraInfoTextContainer}>
                            <div className={classes.extraInfoText}>
                                <Typography component="h4">
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
                    <div className={classes.extraInfoTextContainer}>
                        <div className={classes.extraInfoText}>
                            <Typography component="h4">
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
        </CenteredDivCol>
    );
};

export default Bill;
