/** @format */

import { useCallback } from "react";
import { Button, Modal } from "react-bootstrap";

interface IProps {
    open: boolean;
    setOpen: (open: boolean) => void;
    children: React.ReactNode;
    style?: React.CSSProperties;
}

const DialogWrapper: React.FC<IProps> = ({ open, setOpen, children, style }) => {
    const onHide = useCallback(() => setOpen(false), [setOpen]);

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
