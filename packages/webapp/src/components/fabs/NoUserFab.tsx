/** @format */

import { createStyles, makeStyles, Theme } from "@material-ui/core";
import Fab from "@material-ui/core/Fab";
import { Gavel, Navigation } from "@material-ui/icons";
import { ROUTES } from "@sway/constants";
import { useEffect, useState } from "react";
import { useHistory } from "react-router-dom";
import { sway } from "sway";
import { auth, authConstructor } from "../../firebase";
import "../../scss/menu.scss";
import { handleError, isPhoneWidth, swayWhite } from "../../utils";

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
    const [recaptchaVerifier, setRecaptchaVerifier] = useState<
        firebase.default.auth.RecaptchaVerifier | undefined
    >();

    const pathname = history.location.pathname || "";

    const onBillPage =
        pathname.includes("bill") || pathname.includes("legislator");
    const needsCompleteRegistration =
        props.user && props.user.locale && !props.user.isRegistrationComplete;

    useEffect(() => {
        // set recaptcha object after component has mounted
        // this is done so that the <div id="recaptcha" /> has been rendered
        setRecaptchaVerifier(
            new authConstructor.RecaptchaVerifier("recaptcha", {
                size: "invisible",
            }),
        );
    }, []);

    const signInAnonymously = async () => {
        if (!recaptchaVerifier) {
            console.error("error verifying captcha for anon user signin");
            return;
        }
        return recaptchaVerifier
            .render()
            .then(() => {
                return recaptchaVerifier
                    .verify()
                    .then(() => {
                        return auth.signInAnonymously();
                    })
                    .catch(handleError);
            })
            .catch(handleError);
    };

    const handleClick = () => {
        if (onBillPage && needsCompleteRegistration) {
            signInAnonymously()
                .then(() => {
                    history.push(ROUTES.registrationIntroduction);
                })
                .catch(handleError);
        } else if (!onBillPage) {
            signInAnonymously()
                .then(() => {
                    history.push(ROUTES.billOfTheWeek);
                })
                .catch(handleError);
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
                            style={isPhoneWidth ? { margin: 0 } : {}}
                            className={classes.fabIcon}
                        />
                        {isPhoneWidth ? "" : "Bill of the Week"}
                    </>
                )}
                {onBillPage && !needsCompleteRegistration && (
                    <>
                        <Navigation
                            style={isPhoneWidth ? { margin: 0 } : {}}
                            className={classes.fabIcon}
                        />
                        {isPhoneWidth ? "" : "Sign In"}
                    </>
                )}
                {onBillPage && needsCompleteRegistration && (
                    <>
                        <Navigation
                            style={isPhoneWidth ? { margin: 0 } : {}}
                            className={classes.fabIcon}
                        />
                        {isPhoneWidth ? "" : "Complete Registration"}
                    </>
                )}
            </Fab>
        </div>
    );
};

export default NoUserFab;
