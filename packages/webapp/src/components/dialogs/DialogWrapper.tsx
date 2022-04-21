/** @format */

import { useTheme } from "@mui/material/styles";
import useMediaQuery from "@mui/material/useMediaQuery";
import React from "react";
import { Button, Modal } from "react-bootstrap";
import { sway } from "sway";
import { IS_MOBILE_PHONE } from "../../utils";

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
        <Modal
            style={style && style}
            className={"hover-chart-dialog"}
            fullScreen={!IS_MOBILE_PHONE && fullScreen}
            open={open}
            onClose={setOpen}
            aria-labelledby="responsive-dialog-title"
        >
            <Modal.Body>{children}</Modal.Body>
            <Modal.Footer>
                <Button onClick={setOpen} variant="danger">
                    Close
                </Button>
            </Modal.Footer>
        </Modal>
    );
};

export default DialogWrapper;
