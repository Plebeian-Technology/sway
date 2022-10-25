/** @format */
import Image from "react-bootstrap/Image";
import {
    CONGRESS_LOCALE,
    DEFAULT_ORGANIZATION,
    ROUTES,
    VOTING_WEBSITES_BY_LOCALE,
} from "@sway/constants";
import { findLocale, isEmptyObject, logDev, titleize, userLocaleFromLocales } from "@sway/utils";
import { useEffect, useMemo, useState } from "react";
import { useNavigate, useParams } from "react-router-dom";
import { sway } from "sway";
import { useBill } from "../../hooks/bills";
import { useCancellable } from "../../hooks/cancellable";
import { anonymousSignIn } from "../../users/signinAnonymously";
import { handleError, IS_MOBILE_PHONE } from "../../utils";
import FullWindowLoading from "../dialogs/FullWindowLoading";
import ShareButtons from "../social/ShareButtons";
import { ILocaleUserProps } from "../user/UserRouter";
import VoteButtonsContainer from "../uservote/VoteButtonsContainer";
import BillActionLinks from "./BillActionLinks";
import BillArguments from "./BillArguments";
import BillSummaryAudio from "./BillSummaryAudio";
import BillSummaryModal from "./BillSummaryModal";
import BillChartsContainer from "./charts/BillChartsContainer";
import BillMobileChartsContainer from "./charts/BillMobileChartsContainer";
import { FiExternalLink } from "react-icons/fi";

interface IProps extends ILocaleUserProps {
    bill: sway.IBill;
    locale: sway.ILocale | undefined;
    organizations?: sway.IOrganization[];
    userVote?: sway.IUserVote;
    isPreview?: boolean;
}

const LOAD_ERROR_MESSAGE =
    "Error loading Bill of the Week. Please navigate back to https://app.sway.vote.";

const Bill: React.FC<IProps> = ({ locale, user, bill, organizations, userVote, isPreview }) => {
    logDev("BOTW", { bill, organizations });

    const makeCancellable = useCancellable();
    const navigate = useNavigate();
    const params = useParams() as {
        billFirestoreId: string;
        localeName: string;
    };
    const [showSummary, setShowSummary] = useState<sway.IOrganization | null>(null);

    const uid = user?.uid;
    const billFirestoreId = bill ? bill.firestoreId : params.billFirestoreId;

    const paramsLocale = findLocale(params.localeName);

    const selectedLocale: sway.ILocale = locale || paramsLocale || CONGRESS_LOCALE;
    const localeName = selectedLocale?.name;

    const orgs = useMemo(() => (organizations || []).filter((o) => o.name), [organizations]);

    const [hookedBill, getBill] = useBill(billFirestoreId);

    useEffect(() => {
        const load = async () => {
            if (hookedBill) return;
            if (!selectedLocale) return;

            if (!user) {
                anonymousSignIn()
                    .then(() => getBill(selectedLocale, uid))
                    .catch((error: Error) => {
                        handleError(error, LOAD_ERROR_MESSAGE);
                    });
            } else {
                logDev("getting new hookedBill");
                getBill(selectedLocale, uid);
            }
        };
        makeCancellable(load(), () => logDev("Cancelled Bill.getBill in useEffect")).catch(
            (error: Error) => {
                handleError(error, LOAD_ERROR_MESSAGE);
            },
        );
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

        handleNavigate(ROUTES.legislator(localeName, selectedBill.sponsorExternalId));
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

        if (IS_MOBILE_PHONE) {
            return (
                <BillMobileChartsContainer
                    bill={selectedBill}
                    userLocale={userLocale}
                    userVote={selectedUserVote}
                />
            );
        } else {
            return (
                <BillChartsContainer
                    bill={selectedBill}
                    userLocale={userLocale}
                    userVote={selectedUserVote}
                />
            );
        }
    })();

    const { summary } = getSummary();

    const getLegislatorsVotedText = (() => {
        if (!selectedBill.votedate) {
            return (
                <>
                    <span>Legislators have not yet voted on a final version of this bill.</span>
                    <br />
                    <span>It may be amended before a final vote.</span>
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
                <span>{`House voted on - ${selectedBill.houseVoteDate}`}</span>
                <span>{`Senate voted on - ${selectedBill.senateVoteDate}`}</span>
            </>
        );
    })();

    const title = (() => {
        return `${selectedBill.externalId.toUpperCase()} - ${selectedBill.title}`;
    })();

    const getCreatedAt = (b: sway.IBill) => {
        if (!b.createdAt) return new Date();
        return new Date(b.createdAt);
    };

    return (
        <div className="col p-2">
            {selectedBill.votedate &&
                new Date(selectedBill.votedate) < // TODO: Change this to locale.currentSessionStartDate
                    new Date(selectedLocale.currentSessionStartDate) && (
                    <div className="row">
                        <div className="col">
                            <span>
                                {"Legislators that voted on this bill may no longer be in office."}
                            </span>
                        </div>
                    </div>
                )}

            <div className="row my-1">
                <div className="col">
                    <span className="bold">{title}</span>
                </div>
            </div>
            <div className="row my-1">
                <div className="col">{getLegislatorsVotedText}</div>
            </div>
            {user && selectedLocale && selectedBill && (
                <div className="row my-1">
                    <div className="col">
                        <VoteButtonsContainer
                            user={user}
                            locale={selectedLocale}
                            bill={selectedBill}
                            updateBill={onUserVoteUpdateBill}
                            userVote={selectedUserVote}
                        />
                    </div>
                </div>
            )}
            {selectedLocale && selectedUserVote && user && (
                <div className="row my-1">
                    <div className="col">
                        <ShareButtons
                            bill={selectedBill}
                            locale={selectedLocale}
                            user={user}
                            userVote={selectedUserVote}
                        />
                    </div>
                </div>
            )}

            {selectedUserVote && (
                <div className="row my-2">
                    <div className="col text-center">
                        <BillActionLinks />
                    </div>
                </div>
            )}

            {renderCharts && <div className="row my-4">{renderCharts}</div>}

            <div className="row">
                <div className="col">
                    <div className="row">
                        <div className="col">
                            <div className="row align-items-center">
                                <div className="col-2 pe-0" style={{ maxWidth: 100 }}>
                                    <Image roundedCircle thumbnail src="/logo300.png" />
                                </div>
                                <div className="col-10 bold">Sway Summary</div>
                            </div>
                            {selectedLocale && selectedBill?.summaries?.swayAudioBucketPath && (
                                <BillSummaryAudio
                                    localeName={selectedLocale.name}
                                    swayAudioByline={
                                        selectedBill.summaries.swayAudioByline || "Sway"
                                    }
                                    swayAudioBucketPath={selectedBill.summaries.swayAudioBucketPath}
                                />
                            )}
                        </div>
                    </div>
                    <BillSummaryModal
                        localeName={localeName}
                        summary={summary}
                        billFirestoreId={selectedBill.firestoreId}
                        organization={DEFAULT_ORGANIZATION}
                        selectedOrganization={showSummary}
                        setSelectedOrganization={setShowSummary}
                        isUseMarkdown={
                            isPreview ||
                            Boolean(
                                selectedBill &&
                                    getCreatedAt(selectedBill) > new Date("January 1, 2021"),
                            )
                        }
                    />
                </div>
            </div>

            {!isEmptyObject(orgs) && (
                <div className="row my-4">
                    <div className="col">
                        <BillArguments
                            bill={selectedBill}
                            organizations={orgs}
                            localeName={localeName}
                        />
                    </div>
                </div>
            )}
            <div className="row my-2">
                <div className="col">
                    <span className="bold">Legislative Sponsor:&nbsp;</span>
                    <span onClick={handleNavigateToLegislator} className="bold pointer">
                        {titleize(selectedBill.sponsorExternalId.split("-").slice(0, 2).join(" "))}
                    </span>
                    <span>
                        {
                            " - Sway records this person, and any co-sponsors, as voting 'For' the legislation in lieu of a vote."
                        }
                    </span>
                </div>
            </div>

            {selectedBill.relatedBillIds && selectedBill.relatedBillIds.length > 0 && (
                <div className="row my-1">
                    <div className="col">
                        <span>{"Related Bills: "}</span>
                        <span>{selectedBill.relatedBillIds}</span>
                    </div>
                </div>
            )}

            {localeName && (
                <div className="row my-2">
                    <div className="col">
                        <span className="bold">Data From:&nbsp;</span>
                        <a href={selectedBill.link} rel="noreferrer" target="_blank">
                            {VOTING_WEBSITES_BY_LOCALE[localeName]}&nbsp;
                            <FiExternalLink />
                        </a>
                    </div>
                </div>
            )}
        </div>
    );
};

export default Bill;
