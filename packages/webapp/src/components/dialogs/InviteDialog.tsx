/** @format */

import {
    createStyles,
    makeStyles,
    Tooltip,
    Typography,
    useTheme,
} from "@material-ui/core";
import Button from "@material-ui/core/Button";
import Dialog from "@material-ui/core/Dialog";
import DialogActions from "@material-ui/core/DialogActions";
import DialogContent from "@material-ui/core/DialogContent";
import DialogContentText from "@material-ui/core/DialogContentText";
import DialogTitle from "@material-ui/core/DialogTitle";
import { AWARD_TYPES } from "@sway/constants";
import { findNotCongressLocale } from "@sway/utils";
import copy from "copy-to-clipboard";
import React, { useState } from "react";
import { sway } from "sway";
import { useUserSettings } from "../../hooks";
import { useCongratulations } from "../../hooks/awards";
import { notify } from "../../utils";
import InviteForm from "../forms/InviteForm";
import Award from "../user/awards/Award";
import CenteredLoading from "./CenteredLoading";

interface IProps {
    user: sway.IUser;
    open: boolean;
    handleClose: (close: boolean | React.MouseEvent<HTMLElement>) => void;
}

const useStyles = makeStyles(() =>
    createStyles({
        copyGroup: {
            cursor: "pointer",
        },
        copyIconContainer: {
            cursor: "pointer",
            textAlign: "center",
            fontSize: "1.5em",
        },
        copyIcon: {
            maxHeight: "1.5em",
        },
    }),
);

const InviteDialog: React.FC<IProps> = ({ user, open, handleClose }) => {
    const classes = useStyles();
    const theme = useTheme();
    const settings = useUserSettings();
    const [isCongratulations, setIsCongratulations] = useCongratulations();
    const [isSendingInvites, setIsSendingInvites] = useState<boolean>(false);

    const link = `https://${process.env.REACT_APP_ORIGIN}/invite/${user.uid}`;

    const isCongratulationsPermittedByUser =
        settings?.congratulations?.isCongratulateOnInviteSent === undefined
            ? true
            : settings?.congratulations?.isCongratulateOnInviteSent;

    const handleCopy = (value: string) => {
        copy(value, {
            message: "Click to Copy",
            format: "text/plain",
            onCopy: () =>
                notify({
                    level: "info",
                    title: "Copied!",
                    message: `Copied link to clipboard`,
                    duration: 3000,
                }),
        });
    };

    return (
        <Dialog
            open={open}
            onClose={() => handleClose(false)}
            aria-labelledby="alert-dialog-title"
            aria-describedby="alert-dialog-description"
        >
            <DialogTitle id="alert-dialog-title">
                {"Invite friends through email or a link."}
            </DialogTitle>
            <DialogContent style={{ cursor: "pointer" }}>
                <Typography
                    style={{ marginBottom: theme.spacing(2) }}
                    variant={"body1"}
                    component={"p"}
                >
                    The more friends you invite, the greater your sway.
                </Typography>
                {isSendingInvites && (
                    <CenteredLoading style={{ margin: "5px auto" }} />
                )}

                <InviteForm
                    user={user}
                    setIsSendingInvites={setIsSendingInvites}
                    setIsCongratulations={setIsCongratulations}
                />

                <DialogContentText
                    style={{ marginTop: theme.spacing(2) }}
                    onClick={() => handleCopy(link)}
                >
                    {"Or invite your friends using this link:"}
                </DialogContentText>
                <DialogContentText
                    style={{ marginTop: theme.spacing(2) }}
                    onClick={() => handleCopy(link)}
                >
                    {link}
                </DialogContentText>
                <Tooltip
                    title="Copy Link"
                    placement="right"
                    onClick={() => handleCopy(link)}
                >
                    <div
                        className={classes.copyIconContainer}
                        onClick={() => handleCopy(link)}
                    >
                        <img
                            alt={"copy button"}
                            src={"/copy.png"}
                            className={classes.copyIcon}
                        />
                    </div>
                </Tooltip>
            </DialogContent>
            <DialogActions>
                <Button onClick={handleClose} color="primary">
                    Close
                </Button>
            </DialogActions>
            {isCongratulationsPermittedByUser && isCongratulations && (
                <Award
                    user={user}
                    locale={findNotCongressLocale(user.locales)}
                    type={AWARD_TYPES.Invite}
                    setIsCongratulations={setIsCongratulations}
                />
            )}
        </Dialog>
    );
};

export default InviteDialog;
