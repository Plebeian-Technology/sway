/** @format */
import { DEFAULT_ORGANIZATION, ROUTES, VOTING_WEBSITES_BY_LOCALE } from "@sway/constants";
import { isEmptyObject, logDev, titleize } from "@sway/utils";
import { useCallback, useEffect, useMemo, useState } from "react";
import { Navbar } from "react-bootstrap";
import Image from "react-bootstrap/Image";
import { FiExternalLink } from "react-icons/fi";
import { useNavigate } from "react-router-dom";
import { Animate } from "react-simple-animate";

import { sway } from "sway";
import { LOAD_ERROR_MESSAGE } from "../../constants";
import { useBill } from "../../hooks/bills/useBill";
import { useCancellable } from "../../hooks/useCancellable";
import { useLocale, useLocaleName } from "../../hooks/useLocales";
import { useIsUserRegistrationComplete } from "../../hooks/users/useIsUserRegistrationComplete";
import { useUser } from "../../hooks/users/useUser";
import { anonymousSignIn } from "../../users/signinAnonymously";
import { handleError } from "../../utils";
import { getCreatedAt } from "../../utils/bills";
import FullScreenLoading from "../dialogs/FullScreenLoading";
import ShareButtons from "../social/ShareButtons";
import VoteButtonsContainer from "../uservote/VoteButtonsContainer";
import BillActionLinks from "./BillActionLinks";
import BillArguments from "./BillArguments";
import BillSummaryAudio from "./BillSummaryAudio";
import BillSummaryModal from "./BillSummaryModal";
import BillMobileChartsContainer from "./charts/BillMobileChartsContainer";

interface IProps {
    billFirestoreId: string;
    preview?: {
        organizations: sway.IOrganization[];
        swaySummary: string;
    };
}

const Bill: React.FC<IProps> = ({ billFirestoreId, preview }) => {
    const makeCancellable = useCancellable();
    const navigate = useNavigate();
    const user = useUser();
    const isRegistrationComplete = useIsUserRegistrationComplete();

    const [locale] = useLocale();
    const localeName = useLocaleName();

    const [{ bill, userVote, organizations: orgs }, getBill, isLoading] = useBill(billFirestoreId);
    const organizations = useMemo(
        () => orgs || preview?.organizations,
        [orgs, preview?.organizations],
    );

    const [showSummary, setShowSummary] = useState<sway.IOrganization | null>(null);

    useEffect(() => {
        const load = async () => {
            if (isRegistrationComplete === undefined) {
                logDev("Bill.useEffect - getBill() isRegistrationComplete === undefined. No-op");
            } else if (!isRegistrationComplete) {
                logDev("Bill.useEffect - getBill() WITH ANONYMOUS USER");
                anonymousSignIn()
                    .then(getBill)
                    .catch((error: Error) => {
                        handleError(error, LOAD_ERROR_MESSAGE);
                    });
            } else {
                logDev("Bill.useEffect - getBill() WITH REGISTERED USER");
                getBill();
            }
        };
        makeCancellable(load(), () => logDev("Cancelled Bill.getBill in useEffect")).catch(
            (error: Error) => {
                handleError(error, LOAD_ERROR_MESSAGE);
            },
        );
    }, [isRegistrationComplete, getBill, makeCancellable]);

    const handleNavigate = useCallback(
        (pathname: string) => {
            navigate({ pathname });
        },
        [navigate],
    );

    const handleNavigateToLegislator = useCallback(
        (e: React.MouseEvent<HTMLElement>) => {
            e.preventDefault();
            e.stopPropagation();
            handleNavigate(ROUTES.legislator(localeName, bill.sponsorExternalId));
        },
        [localeName, bill.sponsorExternalId, handleNavigate],
    );

    const summary = useMemo(() => {
        return preview?.swaySummary || bill?.summaries?.sway || bill?.swaySummary || "";
    }, [bill?.summaries?.sway, bill?.swaySummary, preview?.swaySummary]);

    const renderCharts = useMemo(() => {
        if (!bill) return null;

        return <BillMobileChartsContainer bill={bill} userVote={userVote} />;
    }, [bill, userVote]);

    const legislatorsVotedText = useMemo(() => {
        if (!bill?.votedate) {
            return (
                <>
                    <span>Legislators have not yet voted on a final version of this bill.</span>
                    <br />
                    <span>It may be amended before a final vote.</span>
                </>
            );
        }
        if (!bill.houseVoteDate && !bill.senateVoteDate) {
            return `Legislators voted on - ${bill.votedate}`;
        }
        if (bill.houseVoteDate && !bill.senateVoteDate) {
            return `House voted on - ${bill.houseVoteDate}`;
        }
        if (!bill.houseVoteDate && bill.senateVoteDate) {
            return `Senate voted on - ${bill.senateVoteDate}`;
        }
        return (
            <>
                <span>{`House voted on - ${bill.houseVoteDate}`}</span>
                <span>{`Senate voted on - ${bill.senateVoteDate}`}</span>
            </>
        );
    }, [bill?.houseVoteDate, bill?.senateVoteDate, bill?.votedate]);

    const title = useMemo(() => {
        return `${(bill?.externalId || "").toUpperCase()} - ${bill?.title}`;
    }, [bill?.externalId, bill?.title]);

    if (!bill?.externalId) {
        return <FullScreenLoading message={"Loading Bill..."} />;
    }

    return (
        <Animate play={!isLoading} start={{ opacity: 0 }} end={{ opacity: 1 }}>
            <div className="col p-2 pb-5">
                {bill.votedate &&
                    new Date(bill.votedate) < // TODO: Change this to locale.currentSessionStartDate
                        new Date(locale.currentSessionStartDate) && (
                        <div className="row">
                            <div className="col">
                                <span>
                                    {
                                        "Legislators that voted on this bill may no longer be in office."
                                    }
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
                    <div className="col">{legislatorsVotedText}</div>
                </div>
                {user && locale && bill && (
                    <div className="row my-1">
                        <div className="col">
                            <VoteButtonsContainer
                                bill={bill}
                                updateBill={getBill}
                                userVote={userVote}
                            />
                        </div>
                    </div>
                )}
                {locale && userVote && user && (
                    <div className="row my-1">
                        <div className="col">
                            <ShareButtons bill={bill} locale={locale} userVote={userVote} />
                        </div>
                    </div>
                )}

                {userVote && (
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
                                <Navbar.Brand>
                                    <Image
                                        src={"/logo300.png"}
                                        style={{ maxWidth: 30 }}
                                        className="d-inline-block align-top"
                                    />
                                    <span className="ms-2">Sway Summary</span>
                                </Navbar.Brand>
                                {locale && bill?.summaries?.swayAudioBucketPath && (
                                    <BillSummaryAudio
                                        localeName={locale.name}
                                        swayAudioByline={bill.summaries.swayAudioByline || "Sway"}
                                        swayAudioBucketPath={bill.summaries.swayAudioBucketPath}
                                    />
                                )}
                            </div>
                        </div>
                        <BillSummaryModal
                            localeName={localeName}
                            summary={summary}
                            billFirestoreId={bill.firestoreId}
                            organization={DEFAULT_ORGANIZATION}
                            selectedOrganization={showSummary}
                            setSelectedOrganization={setShowSummary}
                            isUseMarkdown={Boolean(
                                bill && getCreatedAt(bill) > new Date("January 1, 2021"),
                            )}
                        />
                    </div>
                </div>

                {!isEmptyObject(organizations) && (
                    <div className="row my-4">
                        <div className="col">
                            <BillArguments
                                bill={bill}
                                organizations={organizations}
                                localeName={localeName}
                            />
                        </div>
                    </div>
                )}
                <div className="row my-2">
                    <div className="col">
                        <span className="bold">Legislative Sponsor:&nbsp;</span>
                        <span onClick={handleNavigateToLegislator} className="bold pointer">
                            {titleize(bill.sponsorExternalId.split("-").slice(0, 2).join(" "))}
                        </span>
                        <span>
                            {
                                " - Sway records this person, and any co-sponsors, as voting 'For' the legislation in lieu of a vote."
                            }
                        </span>
                    </div>
                </div>

                {bill.relatedBillIds && bill.relatedBillIds.length > 0 && (
                    <div className="row my-1">
                        <div className="col">
                            <span>{"Related Bills: "}</span>
                            <span>{bill.relatedBillIds}</span>
                        </div>
                    </div>
                )}

                {localeName && (
                    <div className="row my-2 pb-5">
                        <div className="col">
                            <span className="bold">Data From:&nbsp;</span>
                            <a href={bill.link} rel="noreferrer" target="_blank">
                                {VOTING_WEBSITES_BY_LOCALE[localeName]}&nbsp;
                                <FiExternalLink />
                            </a>
                        </div>
                    </div>
                )}
            </div>
        </Animate>
    );
};

export default Bill;
