/** @format */

import { Button, Modal } from "react-bootstrap";
import SwaySpinner from "../SwaySpinner";

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
        <Modal
            centered
            show={open}
            onHide={() => handleClose(false)}
            aria-labelledby="alert-dialog-title"
            aria-describedby="alert-dialog-description"
            className={className ? `confirmation-dialog ${className}` : "confirmation-dialog"}
        >
            <Modal.Header>
                <Modal.Title id="alert-dialog-title">{title}</Modal.Title>
            </Modal.Header>
            <Modal.Body>
                <div className="my-2" id="alert-dialog-description">
                    {text}
                </div>
            </Modal.Body>
            <Modal.Footer>
                <SwaySpinner isHidden={!isLoading} />
                <Button
                    onClick={() => handleClose(false)}
                    variant="secondary"
                    className="confirmation-dialog-button-falsey"
                >
                    {props.options.falsey}
                </Button>
                <Button
                    onClick={() => handleClose(true)}
                    variant="primary"
                    className="confirmation-dialog-button-truthy"
                >
                    {props.options.truthy}
                </Button>
            </Modal.Footer>
        </Modal>
    );
};

export default ConfirmationDialog;
