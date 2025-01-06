/** @format */
import { ROUTES, Support, VOTING_WEBSITES_BY_LOCALE } from "app/frontend/sway_constants";
import { Suspense, lazy, useCallback, useMemo, useState } from "react";
import { Button, Fade, Navbar } from "react-bootstrap";
import Image from "react-bootstrap/Image";
import { FiExternalLink } from "react-icons/fi";

import { router } from "@inertiajs/react";
import SwayLogo from "app/frontend/components/SwayLogo";
import SwaySpinner from "app/frontend/components/SwaySpinner";
import BillArguments from "app/frontend/components/bill/BillArguments";
import BillSummaryModal from "app/frontend/components/bill/BillSummaryModal";
import VoteButtonsContainer from "app/frontend/components/uservote/VoteButtonsContainer";
import { useLocale, useLocaleName } from "app/frontend/hooks/useLocales";
import { useUser } from "app/frontend/hooks/users/useUser";
import { formatDate } from "app/frontend/sway_utils/datetimes";
import { sway } from "sway";

const BillMobileChartsContainer = lazy(() => import("app/frontend/components/bill/charts/BillMobileChartsContainer"));
const ShareButtons = lazy(() => import("app/frontend/components/social/ShareButtons"));
const BillActionLinks = lazy(() => import("app/frontend/components/bill/BillActionLinks"));

interface IProps {
    bill: sway.IBill;
    organizations: sway.IOrganization[];
    legislatorVotes: sway.ILegislatorVote[];
    sponsor: sway.ILegislator;
    locale?: sway.ISwayLocale;
    userVote?: sway.IUserVote;
}

const DEFAULT_ORGANIZATION: sway.IOrganization = {
    id: -1,
    swayLocaleId: -1,
    name: "Sway",
    iconPath: "sway.png",
    positions: [
        {
            id: -1,
            billId: -1,
            support: Support.Abstain,
            summary: "",
        },
    ],
};

const BillComponent: React.FC<IProps> = ({ bill, sponsor, organizations, userVote }) => {
    const user = useUser();

    const [locale] = useLocale();
    const localeName = useLocaleName();

    const [showSummary, setShowSummary] = useState<sway.IOrganizationBase | undefined>();

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
        if (!bill.voteDateTimeUtc) {
            return (
                <>
                    <span>Legislators have not yet voted on a final version of this bill.</span>
                    <br />
                    <span>It may be amended before a final vote.</span>
                </>
            );
        }
        if (!bill.houseVoteDateTimeUtc && !bill.senateVoteDateTimeUtc) {
            return `Legislators voted on - ${formatDate(bill.voteDateTimeUtc)}`;
        }
        if (bill.houseVoteDateTimeUtc && !bill.senateVoteDateTimeUtc) {
            return `House voted on - ${formatDate(bill.houseVoteDateTimeUtc)}`;
        }
        if (!bill.houseVoteDateTimeUtc && bill.senateVoteDateTimeUtc) {
            return `Senate voted on - ${formatDate(bill.senateVoteDateTimeUtc)}`;
        }
        return (
            <>
                <span>{`House voted on - ${formatDate(bill.houseVoteDateTimeUtc)}`}</span>
                <span>{`Senate voted on - ${formatDate(bill.senateVoteDateTimeUtc)}`}</span>
            </>
        );
    }, [bill.houseVoteDateTimeUtc, bill.senateVoteDateTimeUtc, bill.voteDateTimeUtc]);

    const title = useMemo(() => {
        return `${(bill.externalId || "").toUpperCase()} - ${bill?.title}`;
    }, [bill.externalId, bill?.title]);

    return (
        <Fade in={true}>
            <div className="col p-2 pb-5">
                {bill.voteDateTimeUtc && !bill.active && (
                    <div className="row">
                        <div className="col">
                            <span>Legislators that voted on this bill may no longer be in office.</span>
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
                                    {/* {locale && bill?.summaries?.audioBucketPath && (
                                    <BillSummaryAudio
                                        localeName={locale.name}
                                        audioByLine={bill.summaries.audioByLine || "Sway"}
                                        audioBucketPath={bill.summaries.audioBucketPath}
                                    />
                                )} */}
                                </div>
                            </div>

                            <BillSummaryModal
                                summary={bill.summary}
                                organization={DEFAULT_ORGANIZATION}
                                selectedOrganization={showSummary}
                                setSelectedOrganization={setShowSummary}
                            />
                        </div>
                    </div>
                )}

                <div className="row my-4">
                    <div className="col">
                        <BillArguments bill={bill} organizations={organizations} />
                    </div>
                </div>
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
                            {sponsor?.fullName}
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
                                {(VOTING_WEBSITES_BY_LOCALE as Record<string, string>)[localeName]}&nbsp;
                                <FiExternalLink title={bill.link} />
                            </a>
                        </div>
                    </div>
                )}
            </div>
        </Fade>
    );
};

export default BillComponent;
