/** @format */
import { ROUTES, Support, VOTING_WEBSITES_BY_LOCALE } from "app/frontend/sway_constants";
import { Suspense, lazy, useCallback, useMemo, useState } from "react";
import { Alert, Button, Navbar } from "react-bootstrap";
import Image from "react-bootstrap/Image";
import { FiExternalLink } from "react-icons/fi";

import { router } from "@inertiajs/react";
import SwayLoading from "app/frontend/components/SwayLoading";
import SwayLogo from "app/frontend/components/SwayLogo";
import BillArguments from "app/frontend/components/bill/BillArguments";
import BillSummaryModal from "app/frontend/components/bill/BillSummaryModal";
import VoteButtonsContainer from "app/frontend/components/uservote/VoteButtonsContainer";
import { useLocale, useLocaleName } from "app/frontend/hooks/useLocales";
import { usePollBillOnUserVote } from "app/frontend/hooks/usePollBillOnUserVote";
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
    iconPath: "sway-us-light.png",
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
    const [locale] = useLocale();
    const localeName = useLocaleName();

    const [showSummary, setShowSummary] = useState<sway.IOrganizationBase | undefined>();

    const { onUserVote, onScoreReceived } = usePollBillOnUserVote();

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
                <Alert variant="warning" className="my-1">
                    <span>Legislators have not yet voted on a final version of this bill.</span>
                    <br />
                    <span>It may be amended before a final vote.</span>
                </Alert>
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
        <>
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
                        {legislatorsVotedText}
                    </div>
                </div>

                {locale && bill && (
                    <div className="row mt-3 mb-1">
                        <div className="col">
                            <p className="fw-semibold m-0">Your Vote</p>
                            <VoteButtonsContainer bill={bill} userVote={userVote} onUserVote={onUserVote} />
                        </div>
                    </div>
                )}

                {userVote && (
                    <Suspense fallback={null}>
                        <BillMobileChartsContainer bill={bill} onScoreReceived={onScoreReceived}>
                            <p className="fw-semibold mb-2">How Others Voted</p>
                        </BillMobileChartsContainer>
                    </Suspense>
                )}

                {bill?.summary && (
                    <div className="row">
                        <div className="col">
                            <div className="row">
                                <div className="col text-center">
                                    <SwayLogo className="my-5" maxWidth={30} />
                                </div>
                            </div>
                            <div className="row mb-3">
                                <div className="col">
                                    <Navbar.Brand>
                                        <Image
                                            src={"/images/logo300.png"}
                                            style={{ maxWidth: 30 }}
                                            className="d-inline-block align-top"
                                        />
                                        <span className="fw-semibold ms-2">Sway Summary</span>
                                    </Navbar.Brand>
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
                <div className="row mb-5">
                    <div className="col text-center">
                        <SwayLogo maxWidth={30} />
                    </div>
                </div>
                {locale && (
                    <div className="row my-1">
                        <div className="col">
                            <Suspense fallback={<SwayLoading />}>
                                <ShareButtons bill={bill} locale={locale} userVote={userVote} />
                            </Suspense>
                        </div>
                    </div>
                )}

                {userVote && (
                    <div className="row my-2">
                        <div className="col text-center">
                            <Suspense fallback={null}>
                                <BillActionLinks />
                            </Suspense>
                        </div>
                    </div>
                )}
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
        </>
    );
};

export default BillComponent;
