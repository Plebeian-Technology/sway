/** @format */

import { useCallback } from "react";
import { Button, Modal } from "react-bootstrap";
import { sway } from "sway";

interface IProps {
    open: boolean;
    setOpen: (open: boolean) => void;
    children: React.ReactNode;
    style?: sway.IPlainObject;
}

const DialogWrapper: React.FC<IProps> = ({ open, setOpen, children, style }) => {
    const onHide = useCallback(() => setOpen(false), []);

    return (
        <Modal
            centered
            show={open}
            onHide={onHide}
            style={style && style}
            className={"hover-chart-dialog"}
            aria-labelledby="responsive-dialog-title"
        >
            <Modal.Body>{children}</Modal.Body>
            <Modal.Footer>
                <Button onClick={onHide} variant="danger">
                    Close
                </Button>
            </Modal.Footer>
        </Modal>
    );
};

export default DialogWrapper;
