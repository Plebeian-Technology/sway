/** @format */
import { ContentCopy } from "@mui/icons-material";
import { Tooltip, Typography } from "@mui/material";
import Button from "@mui/material/Button";
import Dialog from "@mui/material/Dialog";
import DialogActions from "@mui/material/DialogActions";
import DialogContent from "@mui/material/DialogContent";
import DialogContentText from "@mui/material/DialogContentText";
import DialogTitle from "@mui/material/DialogTitle";
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

const InviteDialog: React.FC<IProps> = ({ user, open, handleClose }) => {
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
            <DialogContent className="pointer">
                <Typography className="mb-2" variant={"body1"} component={"p"}>
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
                    className="mt-2"
                    onClick={() => handleCopy(link)}
                >
                    {"Or invite your friends using this link:"}
                </DialogContentText>
                <DialogContentText
                    className="ellipses mt-2"
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
                        className={"pointer text-center"}
                        onClick={() => handleCopy(link)}
                    >
                        <ContentCopy />
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
