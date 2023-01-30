/** @format */

import { Modal } from "react-bootstrap";
import SwaySpinner from "../SwaySpinner";

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
            contentClassName={"bg-transparent border-0 py-5"}
        >
            <Modal.Title className="blue">{message || "Loading Sway..."}</Modal.Title>
            <Modal.Body className="bg-transparent border-0">
                <SwaySpinner />
            </Modal.Body>
        </Modal>
    );
};

export default FullScreenLoading;
