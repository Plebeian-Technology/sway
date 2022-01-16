/** @format */

import Button from "@mui/material/Button";
import Dialog from "@mui/material/Dialog";
import DialogActions from "@mui/material/DialogActions";
import DialogContent from "@mui/material/DialogContent";
import { useTheme } from "@mui/material/styles";
import useMediaQuery from "@mui/material/useMediaQuery";
import { sway } from "sway";
import React from "react";
import { IS_COMPUTER_WIDTH } from "../../utils";

interface IProps {
    open: boolean;
    setOpen: (event: React.MouseEvent<HTMLElement>) => void;
    children: React.ReactNode;
    style?: sway.IPlainObject;
}

const DialogWrapper: React.FC<IProps> = ({
    open,
    setOpen,
    children,
    style,
}) => {
    const theme = useTheme();
    const fullScreen = useMediaQuery(theme.breakpoints.down("sm"));

    return (
        <Dialog
            style={style && style}
            className={"hover-chart-dialog"}
            fullScreen={IS_COMPUTER_WIDTH && fullScreen}
            open={open}
            onClose={setOpen}
            aria-labelledby="responsive-dialog-title"
        >
            <DialogContent>{children}</DialogContent>
            <DialogActions>
                <Button onClick={setOpen} color="primary">
                    Close
                </Button>
            </DialogActions>
        </Dialog>
    );
};

export default DialogWrapper;
