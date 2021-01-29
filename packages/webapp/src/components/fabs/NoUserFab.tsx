/** @format */

import { createStyles, makeStyles, Theme } from "@material-ui/core";
import Fab from "@material-ui/core/Fab";
import { Gavel, Navigation } from "@material-ui/icons";
import { ROUTES } from "@sway/constants";
import { useState } from "react";
import { useHistory } from "react-router-dom";
import { sway } from "sway";
import "../../scss/menu.scss";
import { signInAnonymously } from "../../users/signinAnonymously";
import { handleError, isMobilePhone, swayWhite } from "../../utils";
import CenteredLoading from "../dialogs/CenteredLoading";

const useStyles = makeStyles((theme: Theme) =>
    createStyles({
        fabContainer: {
            position: "fixed",
            bottom: theme.spacing(5),
            right: theme.spacing(5),
            zIndex: 3,
        },
        fabList: {
            display: "block",
            position: "relative",
            width: "100%",
            textAlign: "center",
            zIndex: 3,
            marginBottom: theme.spacing(2),
        },
        fabListItem: {
            cursor: "pointer",
            display: "block",
            padding: 0,
            margin: 0,
            marginBottom: theme.spacing(2),
            textAlign: "center",
        },
        fab: {
            padding: theme.spacing(3),
            color: swayWhite,
        },
        fabIcon: {
            marginRight: theme.spacing(1),
        },
    }),
);

interface IProps {
    user: sway.IUser | undefined;
}

const NoUserFab: React.FC<IProps> = (props) => {
    const classes = useStyles();
    const history = useHistory();
    const [isLoading, setIsLoading] = useState<boolean>(false);

    const pathname = history.location.pathname || "";

    const onBillPage =
        pathname.includes("bill") || pathname.includes("legislator");
    const needsCompleteRegistration = props?.user?.isRegistrationComplete === false;

    const handleClick = () => {
        if (onBillPage && needsCompleteRegistration) {
            setIsLoading(true);
            signInAnonymously()
                .then(() => {
                    setIsLoading(false);
                    history.push(ROUTES.registrationIntroduction);
                })
                .catch((error) => {
                    setIsLoading(false);
                    handleError(error);
                });
        } else if (!onBillPage) {
            setIsLoading(true);
            signInAnonymously()
                .then(() => {
                    setIsLoading(false);
                    history.push(ROUTES.billOfTheWeek);
                })
                .catch((error) => {
                    setIsLoading(false);
                    handleError(error);
                });
        } else {
            window.location.href = "/";
        }
    };

    return (
        <div className={"support-fab-container"}>
            <Fab
                size={"large"}
                color={"primary"}
                className={"support-fab"}
                variant="extended"
                onClick={handleClick}
            >
                {!onBillPage && (
                    <>
                        <Gavel
                            style={isMobilePhone ? { margin: 0 } : {}}
                            className={classes.fabIcon}
                        />
                        {isMobilePhone ? "" : "Bill of the Week"}
                    </>
                )}
                {onBillPage && !needsCompleteRegistration && (
                    <>
                        <Navigation
                            style={isMobilePhone ? { margin: 0 } : {}}
                            className={classes.fabIcon}
                        />
                        {isMobilePhone ? "" : "Sign In"}
                    </>
                )}
                {onBillPage && needsCompleteRegistration && (
                    <>
                        <Navigation
                            style={isMobilePhone ? { margin: 0 } : {}}
                            className={classes.fabIcon}
                        />
                        {isMobilePhone ? "" : "Complete Registration"}
                    </>
                )}
                {isLoading && (
                    <CenteredLoading
                        style={{
                            display: "flex",
                            flexDirection: "column",
                            alignItems: "center",
                            marginLeft: 10,
                        }}
                        color={"secondary"}
                    />
                )}
            </Fab>
        </div>
    );
};

export default NoUserFab;
