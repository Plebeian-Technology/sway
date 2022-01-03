/** @format */
import { makeStyles } from "@mui/styles";
import { Button, ButtonClasses } from "@mui/material";
import Avatar from "@mui/material/Avatar";
import ListItemAvatar from "@mui/material/ListItemAvatar";
import ListItemText from "@mui/material/ListItemText";
import { Theme } from "@mui/material/styles";
import Typography from "@mui/material/Typography";
import { InfoRounded } from "@mui/icons-material";
import { ROUTES } from "@sway/constants";
import { titleize, userLocaleFromLocales } from "@sway/utils";
import React from "react";
import { useNavigate } from "react-router-dom";
import { sway } from "sway";
import { IS_MOBILE_PHONE, SWAY_COLORS } from "../../utils";
import CenteredDivRow from "../shared/CenteredDivRow";
import VoteButtonsContainer from "../uservote/VoteButtonsContainer";
import BillChartsContainer, {
    BillChartFilters,
} from "./charts/BillChartsContainer";

const useStyles = makeStyles((theme: Theme) => ({
    heavyText: {
        fontWeight: "bold",
    },
    button: {
        padding: theme.spacing(2),
        margin: theme.spacing(1),
        backgroundColor: SWAY_COLORS.primaryLight,
    },
    buttonLabel: {
        fontWeight: "bold",
        color: SWAY_COLORS.white,
    },
}));

interface IProps {
    user: sway.IUser | undefined;
    locale: sway.ILocale | undefined;
    bill: sway.IBill;
    organizations?: sway.IOrganization[];
    userVote?: sway.IUserVote;
    index: number;
}

const BillsListItem: React.FC<IProps> = ({
    user,
    locale,
    bill,
    organizations,
    userVote,
    index,
}) => {
    const classes = useStyles();
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

    const userLocale =
        user && locale && userLocaleFromLocales(user, locale.name);

    return (
        <div className={"bill-list-item"}>
            <div className={"row"}>
                <div className={"column"}>
                    <ListItemAvatar>
                        <CenteredDivRow
                            style={{
                                justifyContent: "flex-start",
                            }}
                        >
                            <Avatar
                                alt={`${index + 1}`}
                                src={
                                    locale?.name
                                        ? `/avatars/${locale.name}.svg`
                                        : "/logo300.png"
                                }
                                style={{ marginRight: 5 }}
                            />
                            <Typography
                                variant={"body2"}
                                component={"span"}
                                color="textSecondary"
                            >
                                {bill.category && titleize(bill.category)}
                            </Typography>
                        </CenteredDivRow>
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
                    {locale && (
                        <VoteButtonsContainer
                            user={user}
                            locale={locale}
                            bill={bill}
                            organizations={organizations}
                            userVote={userVote}
                        />
                    )}
                    <div
                        className={"column"}
                        style={{ textAlign: "center", width: "100%" }}
                    >
                        <Button
                            className={classes.button}
                            variant="contained"
                            style={{ backgroundColor: SWAY_COLORS.primary }}
                            classes={
                                {
                                    text: classes.buttonLabel,
                                } as ButtonClasses
                            }
                            onClick={handleGoToSingleBill}
                            size={"small"}
                            startIcon={<InfoRounded />}
                        >
                            {"Show More Info"}
                        </Button>
                        {locale &&
                            bill.votedate &&
                            new Date(bill.votedate) <
                                new Date(locale.currentSessionStartDate) && (
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
                {userLocale && userVote && !IS_MOBILE_PHONE ? (
                    <div className={"column"}>
                        <BillChartsContainer
                            bill={bill}
                            userLocale={userLocale}
                            userVote={userVote}
                            filter={BillChartFilters.total}
                        />
                    </div>
                ) : IS_MOBILE_PHONE ? null : (
                    <div className={"column"} />
                )}
            </div>
        </div>
    );
};

export default BillsListItem;
