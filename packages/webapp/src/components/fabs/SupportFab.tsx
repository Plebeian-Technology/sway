/** @format */

import {
    createStyles,
    List,
    ListItem,
    ListItemIcon,
    ListItemText,
    makeStyles,
    Theme,
    Zoom,
} from "@material-ui/core";
import Fab from "@material-ui/core/Fab";
import {
    ContactSupport,
    GroupAdd,
    HowToVote,
    NotificationImportant,
    // QuestionAnswer,
} from "@material-ui/icons";
import React from "react";
import { sway } from "sway";
import { messaging } from "../../firebase";
import { useOpenCloseElement, useUserSettings } from "../../hooks";
import "../../scss/menu.scss";
import { handleError, swayFireClient, swayWhite } from "../../utils";
import InviteDialog from "../dialogs/InviteDialog";

const useStyles = makeStyles((theme: Theme) =>
    createStyles({
        fabList: {
            backgroundColor: swayWhite,
            display: "block",
            position: "relative",
            width: "100%",
            textAlign: "center",
            zIndex: 3,
            marginBottom: theme.spacing(2),
            padding: theme.spacing(2),
        },
        fabListItem: {
            cursor: "pointer",
            display: "block",
            padding: 0,
            margin: 0,
            marginBottom: theme.spacing(2),
            textAlign: "center",
            justifyContent: "center",
        },
        iconContainer: { justifyContent: "center" },
    }),
);

interface IProps {
    user: sway.IUser | undefined;
}

const SupportFab: React.FC<IProps> = ({ user }) => {
    const classes = useStyles();
    const userSettings = useUserSettings();
    const ref: React.MutableRefObject<HTMLButtonElement | null> = React.useRef(
        null,
    );
    const [open, setOpen] = useOpenCloseElement(ref);
    const [showInviteDialog, setShowInviteDialog] = React.useState(false);

    const handleOpen = React.useCallback(() => setOpen(true), [setOpen]);
    const handleClose = React.useCallback(() => setOpen(false), [setOpen]);

    const uid = user?.uid;
    const hasCheckedSupportFab = userSettings.hasCheckedSupportFab;

    React.useEffect(() => {
        if (uid && !hasCheckedSupportFab) {
            swayFireClient()
                .userSettings(uid)
                .update({
                    hasCheckedSupportFab: true,
                } as sway.IUserSettings)
                .catch(console.error);
        }
    }, [uid, hasCheckedSupportFab]);

    const registered = user?.isRegisteredToVote;

    const handleShowInviteDialog = () => {
        setShowInviteDialog(true);
    };

    const handleSetupNotifications = () => {
        if (!messaging) return;
        if (!user || !user.uid) return;

        messaging
            .getToken({ vapidKey: process.env.REACT_APP_FIREBASE_FCM_KEY })
            .then((currentToken: string) => {
                if (currentToken) {
                    swayFireClient()
                        .userSettings(user.uid)
                        .update({
                            messagingRegistrationToken: currentToken,
                            hasCheckedSupportFab: true,
                        } as sway.IUserSettings)
                        .then(() => {
                            setOpen(false);
                        })
                        .catch(handleError);
                } else {
                    handleError(
                        new Error(
                            "no notification registration token returned from fcm gettoken",
                        ),
                        "Error registering for browser notifications. Please try again later.",
                    );
                    window?.Notification &&
                        window?.Notification.requestPermission();
                }
            })
            .catch((err: Error) => {
                if (err.message.includes("messaging/permission-blocked")) {
                    window?.Notification &&
                        window?.Notification.requestPermission();
                    return;
                }
                console.log(
                    "An error occurred while retrieving messaging token.",
                );
                handleError(err);
            });
    };

    const fabClassName = hasCheckedSupportFab
        ? "support-fab"
        : "support-fab support-fab-glow";
    const isRegisteredForNotifications =
        window?.Notification &&
        window?.Notification?.permission === "granted" &&
        userSettings.messagingRegistrationToken;

    return (
        <>
            {open && (
                <div className={"support-fab-container"}>
                    <Zoom in={open}>
                        <List className={classes.fabList}>
                            {!isRegisteredForNotifications && (
                                <ListItem
                                    className={classes.fabListItem}
                                    onClick={handleSetupNotifications}
                                >
                                    <ListItemIcon
                                        className={classes.iconContainer}
                                    >
                                        <NotificationImportant />
                                    </ListItemIcon>
                                    <ListItemText>
                                        Enable Notifications
                                    </ListItemText>
                                </ListItem>
                            )}
                            <ListItem
                                className={classes.fabListItem}
                                onClick={() => {
                                    const url = registered
                                        ? "https://www.vote.org/am-i-registered-to-vote"
                                        : "https://www.vote.org/register-to-vote";
                                    window.open(url);
                                }}
                            >
                                <ListItemIcon className={classes.iconContainer}>
                                    <HowToVote />
                                </ListItemIcon>
                                <ListItemText>
                                    {!registered
                                        ? "Register to Vote"
                                        : "Check Voter Registration"}
                                </ListItemText>
                            </ListItem>
                            {user && (
                                <ListItem
                                    className={classes.fabListItem}
                                    onClick={handleShowInviteDialog}
                                >
                                    <ListItemIcon
                                        className={classes.iconContainer}
                                    >
                                        <GroupAdd />
                                    </ListItemIcon>
                                    <ListItemText>Invite Friends</ListItemText>
                                </ListItem>
                            )}
                            {/* <ListItem
                                className={classes.fabListItem}
                                onClick={() => null}
                            >
                                <ListItemIcon className={classes.iconContainer}>
                                    <QuestionAnswer />
                                </ListItemIcon>
                                <ListItemText>Message Support</ListItemText>
                            </ListItem> */}
                        </List>
                    </Zoom>
                </div>
            )}
            <Fab
                ref={ref}
                style={{ padding: 0 }}
                size={"large"}
                color={"primary"}
                className={fabClassName}
                variant={"extended"}
                onClick={open ? handleClose : handleOpen}
            >
                <ContactSupport />
            </Fab>
            {user && showInviteDialog && (
                <InviteDialog
                    user={user}
                    open={showInviteDialog}
                    handleClose={() => setShowInviteDialog(false)}
                />
            )}
        </>
    );
};

export default SupportFab;
