/** @format */
import { ROUTES } from "@sway/constants";
import { titleize, userLocaleFromLocales } from "@sway/utils";

import { Button, Image } from "react-bootstrap";
import { FiInfo } from "react-icons/fi";
import { useNavigate } from "react-router-dom";
import { sway } from "sway";
import { IS_MOBILE_PHONE } from "../../utils";
import VoteButtonsContainer from "../uservote/VoteButtonsContainer";
import BillChartsContainer, { BillChartFilters } from "./charts/BillChartsContainer";

interface IProps {
    user: sway.IUser | undefined;
    locale: sway.ILocale | undefined;
    bill: sway.IBill;
    organizations?: sway.IOrganization[];
    userVote?: sway.IUserVote;
    index: number;
    isLastItem: boolean;
}

const BillsListItem: React.FC<IProps> = ({
    user,
    locale,
    bill,
    organizations,
    userVote,
    index,
    isLastItem,
}) => {
    const navigate = useNavigate();

    const firestoreId = bill.firestoreId;

    const handleGoToSingleBill = () => {
        if (!locale) return;

        navigate(ROUTES.bill(locale.name, firestoreId), {
            state: {
                bill,
                organizations,
                userVote,
                title: `Bill ${firestoreId}`,
                locale,
            },
        });
    };

    const userLocale = user && locale && userLocaleFromLocales(user, locale.name);

    return (
        <div
            className={`row py-3 justify-content-center ${
                !isLastItem ? "border-bottom border-2" : ""
            }`}
        >
            <div className="col">
                <div className="row mb-3">
                    <div className="col-3 text-start">
                        <Image
                            alt={`${index + 1}`}
                            src={locale?.name ? `/avatars/${locale.name}.svg` : "/logo300.png"}
                            rounded
                            thumbnail
                        />
                    </div>
                    <div className="col text-end">
                        {bill.category && <span>{titleize(bill.category)}</span>}
                    </div>
                </div>
                <div className="row">
                    <div className="bold">{`Bill ${firestoreId}`}</div>
                    <div>{bill.title}</div>
                </div>

                {locale && (
                    <VoteButtonsContainer
                        user={user}
                        locale={locale}
                        bill={bill}
                        userVote={userVote}
                    />
                )}
                <div className="col text-center w-100">
                    <Button
                        variant="outline-primary"
                        onClick={handleGoToSingleBill}
                        className="p-3"
                    >
                        <FiInfo />
                        &nbsp;<span className="align-text-top">Show More Info</span>
                    </Button>
                    {locale &&
                        bill.votedate &&
                        new Date(bill.votedate) < new Date(locale.currentSessionStartDate) && (
                            <div className={"row g-0 my-2"}>
                                <span>
                                    Legislators that voted on this bill may no longer be in office.
                                </span>
                            </div>
                        )}
                </div>
            </div>
            {userLocale && userVote && !IS_MOBILE_PHONE ? (
                <div className="col">
                    <BillChartsContainer
                        bill={bill}
                        userLocale={userLocale}
                        userVote={userVote}
                        filter={BillChartFilters.total}
                    />
                </div>
            ) : IS_MOBILE_PHONE ? null : (
                <div className="col" />
            )}
        </div>
    );
};

export default BillsListItem;
