/** @format */

import Button from "@mui/material/Button";
import Dialog from "@mui/material/Dialog";
import DialogActions from "@mui/material/DialogActions";
import DialogContent from "@mui/material/DialogContent";
import { sway } from "sway";
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
    return (
        <Dialog
            style={style && style}
            className={"hover-chart-dialog"}
            fullScreen={IS_COMPUTER_WIDTH}
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
