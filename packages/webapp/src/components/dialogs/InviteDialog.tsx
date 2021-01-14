/** @format */

import {
    createStyles,
    Divider,
    makeStyles,

    Tooltip,
    Typography,
    useTheme
} from "@material-ui/core";
import Button from "@material-ui/core/Button";
import Dialog from "@material-ui/core/Dialog";
import DialogActions from "@material-ui/core/DialogActions";
import DialogContent from "@material-ui/core/DialogContent";
import DialogContentText from "@material-ui/core/DialogContentText";
import DialogTitle from "@material-ui/core/DialogTitle";
import copy from "copy-to-clipboard";
import React from "react";
import { sway } from "sway";
import { notify } from "../../utils";

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
    })
);

const InviteDialog: React.FC<IProps> = ({ user, open, handleClose }) => {
    const classes = useStyles();
    const theme = useTheme();

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

    const link = `https://${process.env.REACT_APP_ORIGIN}/invite/${user.uid}`;

    return (
        <Dialog
            open={open}
            onClose={() => handleClose(false)}
            aria-labelledby="alert-dialog-title"
            aria-describedby="alert-dialog-description"
        >
            <DialogTitle id="alert-dialog-title">
                {"Invite friends using the below link (click to copy):"}
            </DialogTitle>
            <DialogContent
                style={{ cursor: "pointer" }}
                onClick={() => handleCopy(link)}
            >
                <Typography
                    style={{ marginBottom: theme.spacing(2) }}
                    variant={"body1"}
                    component={"p"}
                >
                    The more friends you invite, the higher your influence
                    ranking.
                </Typography>
                <Divider />
                <DialogContentText style={{ marginTop: theme.spacing(2) }}>
                    {link}
                </DialogContentText>
                <Tooltip title="Copy Link" placement="right">
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
        </Dialog>
    );
};

export default InviteDialog;
