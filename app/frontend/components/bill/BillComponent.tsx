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
import UserLegislatorEmailForm from "app/frontend/components/forms/email/UserLegislatorEmailForm";
import ActionButtons from "app/frontend/components/social/ActionButtons";

const BillMobileChartsContainer = lazy(() => import("app/frontend/components/bill/charts/BillMobileChartsContainer"));
const ShareButtons = lazy(() => import("app/frontend/components/social/ShareButtons"));
const BillActionLinks = lazy(() => import("app/frontend/components/bill/BillActionLinks"));

interface IProps {
    bill: sway.IBill;
    organizations: sway.IOrganization[];
    legislator_votes: sway.ILegislatorVote[];
    sponsor: sway.ILegislator;
    locale?: sway.ISwayLocale;
    user_vote?: sway.IUserVote;
    bill_score?: sway.IBillScore;
}

const DEFAULT_ORGANIZATION: sway.IOrganization = {
    id: -1,
    sway_locale_id: -1,
    name: "Sway",
    icon_path: "sway-us-light.png",
    positions: [
        {
            id: -1,
            bill_id: -1,
            support: Support.Abstain,
            summary: "",
        },
    ],
};

const BillComponent: React.FC<IProps> = ({ bill, bill_score, sponsor, organizations, user_vote }) => {
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
            handleNavigate(ROUTES.legislator(localeName, bill.legislator_id.toString()));
        },
        [localeName, bill.legislator_id, handleNavigate],
    );

    const legislatorsVotedText = useMemo(() => {
        if (!bill.vote_date_time_utc) {
            return (
                <Alert variant="warning" className="my-1">
                    <span>Legislators have not yet voted on a final version of this bill.</span>
                    <br />
                    <span>It may be amended before a final vote.</span>
                </Alert>
            );
        }
        if (!bill.house_vote_date_time_utc && !bill.senate_vote_date_time_utc) {
            return `Legislators voted on - ${formatDate(bill.vote_date_time_utc)}`;
        }
        if (bill.house_vote_date_time_utc && !bill.senate_vote_date_time_utc) {
            return `House voted on - ${formatDate(bill.house_vote_date_time_utc)}`;
        }
        if (!bill.house_vote_date_time_utc && bill.senate_vote_date_time_utc) {
            return `Senate voted on - ${formatDate(bill.senate_vote_date_time_utc)}`;
        }
        return (
            <>
                <span>{`House voted on - ${formatDate(bill.house_vote_date_time_utc)}`}</span>
                <span>{`Senate voted on - ${formatDate(bill.senate_vote_date_time_utc)}`}</span>
            </>
        );
    }, [bill.house_vote_date_time_utc, bill.senate_vote_date_time_utc, bill.vote_date_time_utc]);

    const title = useMemo(() => {
        return `${(bill.external_id || "").toUpperCase()} - ${bill?.title}`;
    }, [bill.external_id, bill?.title]);

    return (
        <>
            <div className="col p-2 pb-5">
                {bill.vote_date_time_utc && !bill.active && (
                    <div className="row">
                        <div className="col">
                            <span>Legislators that voted on this bill may no longer be in office.</span>
                        </div>
                    </div>
                )}

                <div className="row my-1">
                    <div className="col">
                        <div className="bold">{title}</div>
                        <div>{legislatorsVotedText}</div>
                    </div>
                </div>

                {locale && bill && (
                    <div className="row mt-3 mb-1">
                        <div className="col">
                            <p className="fw-semibold m-0">Your Vote</p>
                            <VoteButtonsContainer bill={bill} user_vote={user_vote} onUserVote={onUserVote} />
                        </div>
                    </div>
                )}
                {user_vote && (
                    // Render this below summary when there is no user vote
                    <Suspense fallback={null}>
                        <BillMobileChartsContainer
                            bill={bill}
                            bill_score={bill_score}
                            onScoreReceived={onScoreReceived}
                        >
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

                {!user_vote && (
                    // Render this below summary when there is no user vote
                    <Suspense fallback={null}>
                        <BillMobileChartsContainer
                            bill={bill}
                            bill_score={bill_score}
                            onScoreReceived={onScoreReceived}
                        >
                            <p className="fw-semibold mb-2">How Others Voted</p>
                        </BillMobileChartsContainer>
                    </Suspense>
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
                                <ActionButtons>
                                    <ShareButtons />
                                    {user_vote && <UserLegislatorEmailForm />}
                                </ActionButtons>
                            </Suspense>
                        </div>
                    </div>
                )}

                {user_vote && (
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
                            {sponsor?.full_name}
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
