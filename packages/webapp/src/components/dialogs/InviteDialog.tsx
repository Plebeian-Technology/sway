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
import copy from "copy-to-clipboard";
import React, { useState } from "react";
import { sway } from "sway";
import { notify } from "../../utils";
import InviteForm from "../forms/InviteForm";
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
        },
        copyIcon: {
            maxHeight: 44,
        },
    }),
);

const InviteDialog: React.FC<IProps> = ({ user, open, handleClose }) => {
    const classes = useStyles();
    const theme = useTheme();
    const [isSendingInvites, setIsSendingInvites] = useState<boolean>(false);

    const link = `https://${process.env.REACT_APP_ORIGIN}/invite/${user.uid}`;

    const handleCopy = (value: string) => {
        copy(value, {
            message: "Click to Copy",
            format: "text/plain",
            onCopy: () =>
                notify({
                    level: "info",
                    title: "Copied link to clipboard.",
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
                            alt={"Copy Link"}
                            src={"/copy.svg"}
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
        </Dialog>
    );
};

export default InviteDialog;
