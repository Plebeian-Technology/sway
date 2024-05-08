/** @format */
import { DEFAULT_ORGANIZATION, ROUTES, VOTING_WEBSITES_BY_LOCALE } from "app/frontend/sway_constants";
import { titleize } from "app/frontend/sway_utils";
import { Suspense, lazy, useCallback, useMemo, useState } from "react";
import { Button, Navbar } from "react-bootstrap";
import Image from "react-bootstrap/Image";
import { FiExternalLink } from "react-icons/fi";

import { router } from "@inertiajs/react";
import SwayLogo from "app/frontend/components/SwayLogo";
import FullScreenLoading from "app/frontend/components/dialogs/FullScreenLoading";
import SuspenseFullScreen from "app/frontend/components/dialogs/SuspenseFullScreen";
import VoteButtonsContainer from "app/frontend/components/uservote/VoteButtonsContainer";
import { useLocale, useLocaleName } from "app/frontend/hooks/useLocales";
import { useUser } from "app/frontend/hooks/users/useUser";
import { Animate } from "react-simple-animate";
import { sway } from "sway";
import SwaySpinner from "app/frontend/components/SwaySpinner";

const BillSummaryModal = lazy(() => import("app/frontend/components/bill/BillSummaryModal"));
const BillMobileChartsContainer = lazy(() => import("app/frontend/components/bill/charts/BillMobileChartsContainer"));
const ShareButtons = lazy(() => import("app/frontend/components/social/ShareButtons"));
const BillActionLinks = lazy(() => import("app/frontend/components/bill/BillActionLinks"));

interface IProps {
    bill: sway.IBill;
    locale?: sway.ISwayLocale;
    user_vote?: sway.IUserVote;
}

const BillComponent: React.FC<IProps> = ({ bill, locale: propsLocale, user_vote: userVote }) => {
    const user = useUser();

    const [locale] = useLocale(propsLocale);
    const localeName = useLocaleName();

    const [showSummary, setShowSummary] = useState<sway.IOrganization | null>(null);

    const handleNavigate = useCallback((pathname: string) => {
        router.visit(pathname);
    }, []);

    const handleNavigateToLegislator = useCallback(
        (e: React.MouseEvent<HTMLElement>) => {
            e.preventDefault();
            e.stopPropagation();
            handleNavigate(ROUTES.legislator(localeName, bill.legislatorId.toString()));
        },
        [localeName, bill.legislatorId, handleNavigate],
    );

    const legislatorsVotedText = useMemo(() => {
        const votedate = bill.houseVoteDateTimeUtc || bill.senateVoteDateTimeUtc
        if (!votedate) {
            return (
                <>
                    <span>Legislators have not yet voted on a final version of this bill.</span>
                    <br />
                    <span>It may be amended before a final vote.</span>
                </>
            );
        }
        if (!bill.houseVoteDateTimeUtc && !bill.senateVoteDateTimeUtc) {
            return `Legislators voted on - ${votedate}`;
        }
        if (bill.houseVoteDateTimeUtc && !bill.senateVoteDateTimeUtc) {
            return `House voted on - ${bill.houseVoteDateTimeUtc}`;
        }
        if (!bill.houseVoteDateTimeUtc && bill.senateVoteDateTimeUtc) {
            return `Senate voted on - ${bill.senateVoteDateTimeUtc}`;
        }
        return (
            <>
                <span>{`House voted on - ${bill.houseVoteDateTimeUtc}`}</span>
                <span>{`Senate voted on - ${bill.senateVoteDateTimeUtc}`}</span>
            </>
        );
    }, [bill?.houseVoteDateTimeUtc, bill?.senateVoteDateTimeUtc]);

    const title = useMemo(() => {
        return `${(bill.externalId || "").toUpperCase()} - ${bill?.title}`;
    }, [bill.externalId, bill?.title]);

    if (!bill.externalId) {
        return <FullScreenLoading message={"Loading Bill..."} />;
        // return null;
    }

    return (
        <Animate play={true} start={{ opacity: 0 }} end={{ opacity: 1 }}>
            <div className="col p-2 pb-5">
                {/* {bill.votedate &&
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
                    )} */}

                <div className="row my-1">
                    <div className="col">
                        <span className="bold">{title}</span>
                    </div>
                </div>
                <div className="row my-1">
                    <div className="col">{legislatorsVotedText}</div>
                </div>
                {locale && bill && (
                    <div className="row my-1">
                        <div className="col">
                            <VoteButtonsContainer bill={bill} userVote={userVote} />
                        </div>
                    </div>
                )}
                {locale && userVote && user && (
                    <div className="row my-1">
                        <div className="col">
                            <Suspense fallback={<SwaySpinner />}>
                                <ShareButtons bill={bill} locale={locale} userVote={userVote} />
                            </Suspense>
                        </div>
                    </div>
                )}

                {userVote && (
                    <div className="row my-2">
                        <div className="col text-center">
                            <Suspense fallback={<SwaySpinner />}>
                                <BillActionLinks />
                            </Suspense>
                        </div>
                    </div>
                )}

                {userVote && (
                    <Suspense fallback={<SwaySpinner />}>
                        <BillMobileChartsContainer bill={bill} />
                    </Suspense>
                )}

                {bill?.summary && (
                    <div className="row">
                        <div className="col">
                            <div className="row">
                                <div className="col text-center">
                                    <SwayLogo className="my-3" maxWidth={30} />
                                </div>
                            </div>
                            <div className="row">
                                <div className="col">
                                    <Navbar.Brand>
                                        <Image
                                            src={"/images/logo300.png"}
                                            style={{ maxWidth: 30 }}
                                            className="d-inline-block align-top"
                                        />
                                        <span className="ms-2">Sway Summary</span>
                                    </Navbar.Brand>
                                    {/* {locale && bill?.summaries?.swayAudioBucketPath && (
                                    <BillSummaryAudio
                                        localeName={locale.name}
                                        swayAudioByline={bill.summaries.swayAudioByline || "Sway"}
                                        swayAudioBucketPath={bill.summaries.swayAudioBucketPath}
                                    />
                                )} */}
                                </div>
                            </div>

                            <SuspenseFullScreen>
                                <BillSummaryModal
                                    localeName={localeName}
                                    summary={bill.summary}
                                    billExternalId={bill.externalId}
                                    organization={DEFAULT_ORGANIZATION}
                                    selectedOrganization={showSummary}
                                    setSelectedOrganization={setShowSummary}
                                />
                            </SuspenseFullScreen>
                        </div>
                    </div>
                )}

                {/* {!isEmptyObject(organizations) && (
                    <div className="row my-4">
                        <div className="col">
                            <BillArguments
                                bill={bill}
                                organizations={organizations}
                                localeName={localeName}
                            />
                        </div>
                    </div>
                )} */}
                <div className="row">
                    <div className="col text-center">
                        <SwayLogo maxWidth={30} className="mb-3" />
                    </div>
                </div>
                <div className="row my-2">
                    <div className="col">
                        <span className="bold">Legislative Sponsor:&nbsp;</span>
                        <Button
                            variant="link"
                            onClick={handleNavigateToLegislator}
                            className="bold shadow-none bg-transparent border-0 p-0 text-black no-underline align-baseline"
                        >
                            {/* TODO */}
                            {/* {titleize((bill?.sponsorExternalId || "").split("-").slice(0, 2).join(" "))} */}
                        </Button>
                        <span>
                            {
                                " - Sway records this person, and any co-sponsors, as voting 'For' the legislation in lieu of a vote."
                            }
                        </span>
                    </div>
                </div>

                {localeName && (
                    <div className="row my-2 pb-5">
                        <div className="col">
                            <span className="bold">Data From:&nbsp;</span>
                            <a href={bill.link} rel="noreferrer" target="_blank">
                                {(VOTING_WEBSITES_BY_LOCALE as Record<string, any>)[localeName]}&nbsp;
                                <FiExternalLink />
                            </a>
                        </div>
                    </div>
                )}
            </div>
        </Animate>
    );
};

export default BillComponent;
