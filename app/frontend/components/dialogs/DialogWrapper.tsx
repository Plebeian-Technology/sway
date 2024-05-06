/** @format */

import Footer from "app/frontend/components/Footer";
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
            {...props}
        >
            <Modal.Body>{children}
            <Footer /></Modal.Body>
            <Modal.Footer>
                <div className="col text-end">
                <Button onClick={onHide} variant="danger" className="mb-5">
                    Close
                </Button>
                <div>&nbsp;</div>
                <div>&nbsp;</div>
                <div>&nbsp;</div>
                </div>
            </Modal.Footer>
        </Modal>
    );
};

export default DialogWrapper;
