/** @format */

import Button from "@material-ui/core/Button";
import Dialog from "@material-ui/core/Dialog";
import DialogActions from "@material-ui/core/DialogActions";
import DialogContent from "@material-ui/core/DialogContent";
import { useTheme } from "@material-ui/core/styles";
import useMediaQuery from "@material-ui/core/useMediaQuery";
import { sway } from "sway";
import React from "react";
import { isComputerWidth } from "../../utils";

interface IProps {
    open: boolean;
    setOpen: (event: React.MouseEvent<HTMLElement>) => void;
    children: React.ReactNode;
    style?: sway.IPlainObject;
}

const DialogWrapper: React.FC<IProps> = ({ open, setOpen, children, style }) => {
    const theme = useTheme();
    const fullScreen = useMediaQuery(theme.breakpoints.down("sm"));

    return (
        <Dialog
            style={style && style}
            className={"hover-chart-dialog"}
            fullScreen={isComputerWidth && fullScreen}
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
