/** @format */

import { CircularProgress } from "@mui/material";
import Button from "@mui/material/Button";
import Dialog from "@mui/material/Dialog";
import DialogActions from "@mui/material/DialogActions";
import DialogContent from "@mui/material/DialogContent";
import DialogContentText from "@mui/material/DialogContentText";
import DialogTitle from "@mui/material/DialogTitle";
import React from "react";

interface IProps {
    open: boolean;
    handleClose: (close: boolean) => void;
    title: string;
    text: string | React.ReactNode;
    isLoading?: boolean;
    className?: string;
    options: { truthy: string; falsey: string };
}

const ConfirmationDialog: React.FC<IProps> = (props) => {
    const { open, handleClose, title, text, isLoading, className } = props;

    return (
        <Dialog
            open={open}
            onClose={() => handleClose(false)}
            aria-labelledby="alert-dialog-title"
            aria-describedby="alert-dialog-description"
            className={
                className
                    ? `confirmation-dialog ${className}`
                    : "confirmation-dialog"
            }
        >
            <DialogTitle id="alert-dialog-title">{title}</DialogTitle>
            <DialogContent>
                <DialogContentText id="alert-dialog-description">
                    {text}
                </DialogContentText>
            </DialogContent>
            <DialogActions>
                <Button
                    onClick={() => handleClose(false)}
                    color="secondary"
                    className="confirmation-dialog-button-falsey"
                >
                    {props.options.falsey}
                </Button>
                <Button
                    onClick={() => handleClose(true)}
                    color="primary"
                    className="confirmation-dialog-button-truthy"
                >
                    {props.options.truthy}
                </Button>
            </DialogActions>
            <div style={{ textAlign: "center", margin: 20 }}>
                {isLoading && <CircularProgress />}
            </div>
        </Dialog>
    );
};

export default ConfirmationDialog;