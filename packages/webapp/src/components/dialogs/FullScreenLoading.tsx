/** @format */

import { Modal, Spinner } from "react-bootstrap";

const FullScreenLoading = ({ message }: { message?: string }) => {
    return (
        <Modal
            show={true}
            size="xl"
            aria-labelledby="contained-modal-title-vcenter"
            centered
            backdrop="static"
            style={{
                backgroundColor: "transparent",
                textAlign: "center",
                margin: "0 auto",
            }}
            contentClassName={"transparent-modal"}
        >
            <Modal.Title>{message || "Loading Sway..."}</Modal.Title>
            <Modal.Body className="bg-transparent border-0">
                <Spinner animation="border" className="m-3" />
            </Modal.Body>
        </Modal>
    );
};

export default FullScreenLoading;
