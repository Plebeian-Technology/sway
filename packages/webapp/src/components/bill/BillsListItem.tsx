/** @format */

import { CURRENT_COUNCIL_START_DATE } from "@sway/constants";
import { Button } from "@material-ui/core";
import Avatar from "@material-ui/core/Avatar";
import ListItemAvatar from "@material-ui/core/ListItemAvatar";
import ListItemText from "@material-ui/core/ListItemText";
import { createStyles, makeStyles, Theme } from "@material-ui/core/styles";
import Typography from "@material-ui/core/Typography";
import { InfoRounded } from "@material-ui/icons";
import { sway } from "sway";
import React from "react";
import { useHistory } from "react-router-dom";
import { useUserVote } from "../../hooks/user_votes";
import {
    isPhoneWidth,
    swayLightBlue,
    swayWhite,
    SWAY_COLORS,
    titleize,
} from "../../utils";
import VoteButtonsContainer from "../uservote/VoteButtonsContainer";
import BillChartsContainer, {
    BillChartFilters,
} from "./charts/BillChartsContainer";

const useStyles = makeStyles((theme: Theme) =>
    createStyles({
        heavyText: {
            fontWeight: "bold",
        },
        button: {
            padding: theme.spacing(2),
            margin: theme.spacing(1),
            backgroundColor: swayLightBlue,
            color: swayWhite,
        },
    })
);

interface IProps {
    user: sway.IUser | undefined;
    locale: sway.ILocale | undefined;
    bill: sway.IBill;
    organizations: sway.IOrganization[];
    index: number;
}

const BillsListItem: React.FC<IProps> = ({
    user,
    locale,
    bill,
    organizations,
    index,
}) => {
    const classes = useStyles();
    const history = useHistory();
    const [userVote, isLoadingUserVote] = useUserVote(bill.firestoreId);

    const firestoreId = bill.firestoreId;

    const handleGoToSingleBill = () => {
        history.push({
            pathname: `/bill/${firestoreId}`,
            state: {
                bill,
                organizations,
                userVote,
                title: `Bill ${firestoreId}`,
                locale,
            },
        });
    };

    return (
        <div className={"bill-list-item"}>
            <div className={"row"}>
                <div className={"column"}>
                    <ListItemAvatar>
                        <div
                            className={"row"}
                            style={{
                                justifyContent: "space-between",
                                alignItems: "center",
                            }}
                        >
                            <Avatar
                                alt={`${index + 1} baltimore city flag`}
                                src={locale?.name ? `/avatars/${locale.name}.svg` : "/logo192.png"}
                            />
                            <Typography
                                variant={"body2"}
                                component={"span"}
                                color="textSecondary"
                            >
                                {bill.category && titleize(bill.category)}
                            </Typography>
                        </div>
                    </ListItemAvatar>
                    <ListItemText
                        primary={
                            <Typography
                                component="p"
                                variant="body1"
                                color="textPrimary"
                                className={"bolded-text"}
                            >
                                {`Bill ${firestoreId}`}
                            </Typography>
                        }
                        secondary={
                            <Typography
                                component="p"
                                variant="body1"
                                color="textPrimary"
                            >
                                {bill.title}
                            </Typography>
                        }
                    />
                    <VoteButtonsContainer
                        user={user}
                        bill={bill}
                        organizations={organizations}
                        userVote={userVote}
                        isLoadingUserVote={isLoadingUserVote}
                    />
                    <div
                        className={"column"}
                        style={{ textAlign: "center", width: "100%" }}
                    >
                        <Button
                            className={classes.button}
                            variant="contained"
                            style={{ backgroundColor: SWAY_COLORS.primary }}
                            onClick={handleGoToSingleBill}
                            size={"small"}
                            startIcon={<InfoRounded />}
                        >
                            {"Show More Info"}
                        </Button>
                        {bill.votedate &&
                        new Date(bill.votedate) <
                            CURRENT_COUNCIL_START_DATE && (
                            <div className={"bill-list-item-expired-text"}>
                                <Typography variant="h6">
                                    {
                                        "Legislators that voted on this bill may no longer be in office."
                                    }
                                </Typography>
                            </div>
                        )}
                    </div>
                </div>
                {userVote && !isPhoneWidth ? (
                    <div className={"column"}>
                        <BillChartsContainer
                            bill={bill}
                            filter={BillChartFilters.total}
                        />
                    </div>
                ) : isPhoneWidth ? null : (
                    <div className={"column"} />
                )}
            </div>
        </div>
    );
};

export default BillsListItem;
