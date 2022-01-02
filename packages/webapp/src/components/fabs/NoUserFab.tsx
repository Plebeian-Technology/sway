/** @format */
import { makeStyles } from "@mui/styles";
import { Theme } from "@mui/material";
import Fab from "@mui/material/Fab";
import { Gavel, Navigation } from "@mui/icons-material";
import { DEFAULT_USER_SETTINGS, ROUTES } from "@sway/constants";
import { useState } from "react";
import { useDispatch } from "react-redux";
import { useHistory } from "react-router-dom";
import { sway } from "sway";
import { setUser } from "../../redux/actions/userActions";
import "../../scss/menu.scss";
import { signInAnonymously } from "../../users/signinAnonymously";
import { handleError, IS_MOBILE_PHONE, notify, swayWhite } from "../../utils";
import CenteredLoading from "../dialogs/CenteredLoading";

const useStyles = makeStyles((theme: Theme) => ({
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
}));

interface IProps {
    user: sway.IUser | undefined;
}

const NoUserFab: React.FC<IProps> = (props) => {
    const classes = useStyles();
    const history = useHistory();
    const dispatch = useDispatch();
    const [isLoading, setIsLoading] = useState<boolean>(false);

    const pathname = history.location.pathname || "";

    const onBillPage =
        pathname.includes("bill") || pathname.includes("legislator");
    const needsCompleteRegistration =
        props?.user?.isRegistrationComplete === false;

    const handleAnonAuthed = (
        anon: firebase.default.auth.UserCredential | undefined,
        route: string,
    ) => {
        if (!anon || !anon.user) {
            notify({
                level: "error",
                title: "Error. Please try creating an account instead of viewing the Bill of the Week anonymously.",
            });
        }
        dispatch(
            setUser({
                user: {
                    email: "testymctesterson@sway.vote",
                    uid: anon?.user?.uid,
                    isRegistrationComplete: false,
                    isAnonymous: true,
                },
                settings: DEFAULT_USER_SETTINGS,
                loading: false,
                isAdmin: false,
            } as sway.IUserWithSettingsAdmin & { loading: false }),
        );
        setIsLoading(false);
        history.push(route);
    };

    const handleAnonAuthError = (error: Error) => {
        setIsLoading(false);
        handleError(error);
    };

    const handleClick = () => {
        if (onBillPage && needsCompleteRegistration) {
            setIsLoading(true);
            signInAnonymously()
                .then((anon) => {
                    handleAnonAuthed(anon, ROUTES.registrationV2);
                })
                .catch(handleAnonAuthError);
        } else if (!onBillPage) {
            setIsLoading(true);
            signInAnonymously()
                .then((anon) => {
                    handleAnonAuthed(anon, ROUTES.billOfTheWeek);
                })
                .catch(handleAnonAuthError);
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
                            style={
                                IS_MOBILE_PHONE
                                    ? { margin: 0, marginRight: 5 }
                                    : {}
                            }
                            className={classes.fabIcon}
                        />
                        {IS_MOBILE_PHONE
                            ? "Preview"
                            : "Preview Bill of the Week"}
                    </>
                )}
                {onBillPage && !needsCompleteRegistration && (
                    <>
                        <Navigation
                            style={IS_MOBILE_PHONE ? { margin: 0 } : {}}
                            className={classes.fabIcon}
                        />
                        {IS_MOBILE_PHONE ? "Sign In" : "Sign In"}
                    </>
                )}
                {onBillPage && needsCompleteRegistration && (
                    <>
                        <Navigation
                            style={IS_MOBILE_PHONE ? { margin: 0 } : {}}
                            className={classes.fabIcon}
                        />
                        {IS_MOBILE_PHONE ? "Register" : "Complete Registration"}
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
