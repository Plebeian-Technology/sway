/** @format */

import { useCallback } from "react";
import { Button, Modal, ModalProps } from "react-bootstrap";

interface IProps extends ModalProps {
    open: boolean;
    setOpen: (open: boolean) => void;
    children: React.ReactNode;
}

const DialogWrapper: React.FC<IProps> = ({ open, setOpen, children, ...props }) => {
    const onHide = useCallback(() => setOpen(false), [setOpen]);

    return (
        <Modal
            centered
            show={open}
            onHide={onHide}
            aria-labelledby="responsive-dialog-title"
            className="px-0"
            {...props}
        >
            <Modal.Body>{children}</Modal.Body>
            <Modal.Footer>
                <div className="col text-end">
                    <Button onClick={onHide} variant="danger">
                        Close
                    </Button>
                </div>
            </Modal.Footer>
        </Modal>
    );
};

export default DialogWrapper;
