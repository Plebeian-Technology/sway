/** @format */
import { IS_MOBILE_PHONE, ROUTES } from "app/frontend/sway_constants";
import { titleize } from "app/frontend/sway_utils";
import { lazy, Suspense, useCallback } from "react";

import { Button, Fade } from "react-bootstrap";
import { FiInfo } from "react-icons/fi";
import { sway } from "sway";

import { Link as InertiaLink, router } from "@inertiajs/react";
import CenteredLoading from "app/frontend/components/dialogs/CenteredLoading";
import LocaleAvatar from "app/frontend/components/locales/LocaleAvatar";
import { useAxios_NOT_Authenticated_GET } from "app/frontend/hooks/useAxios";
import { useLocale } from "app/frontend/hooks/useLocales";
import VoteButtonsContainer from "../uservote/VoteButtonsContainer";
import { BillChartFilters } from "./charts/constants";

const BillChartsContainer = lazy(() => import("./charts/BillChartsContainer"));

interface IProps {
    bill: sway.IBill;
    organizations?: sway.IBillOrganization[];
    index: number;
    isLastItem: boolean;
    inView: boolean;
}

const BillsListItem: React.FC<IProps> = ({ bill, isLastItem, inView }) => {
    const [locale] = useLocale();

    const { id, category, externalId, title } = bill;

    const { items: userVote } = useAxios_NOT_Authenticated_GET<sway.IUserVote>(`/user_votes/${bill.id}`);

    const handleGoToSingleBill = useCallback(() => {
        router.visit(ROUTES.bill(bill.id));
    }, [bill.id]);

    return (
        <Fade in={inView} mountOnEnter>
            <div className={`row py-3 justify-content-center ${!isLastItem ? "border-bottom border-2" : ""}`}>
                <div className="col">
                    <div className="row mb-3">
                        <div className="col-3 text-start">
                            <LocaleAvatar />
                        </div>
                        <div className="col text-end">
                            {category && <span className="bold">{titleize(category)}</span>}
                        </div>
                    </div>
                    <InertiaLink href={ROUTES.bill(id)} className="no-underline">
                        <div className="row">
                            <div className="text-black bold">{`Bill ${externalId}`}</div>
                            <div className="text-secondary">{title}</div>
                        </div>
                    </InertiaLink>

                    <VoteButtonsContainer bill={bill} userVote={userVote} />

                    <div className="col text-center w-100">
                        <Button
                            variant="outline-primary"
                            style={{ opacity: "70%" }}
                            onClick={handleGoToSingleBill}
                            className="py-3 px-5"
                        >
                            <FiInfo />
                            &nbsp;<span className="align-text-top">Show More Info</span>
                        </Button>
                        {bill.voteDateTimeUtc && !bill.active && (
                            <div className={"row g-0 my-2"}>
                                <span>Legislators that voted on this bill may no longer be in office.</span>
                            </div>
                        )}
                    </div>
                </div>
                {locale && userVote && !IS_MOBILE_PHONE && (
                    <div className="col">
                        <Suspense fallback={<CenteredLoading />}>
                            <BillChartsContainer
                                bill={bill}
                                locale={locale}
                                userVote={userVote}
                                filter={BillChartFilters.total}
                            />
                        </Suspense>
                    </div>
                )}
            </div>
        </Fade>
    );
};

export default BillsListItem;
