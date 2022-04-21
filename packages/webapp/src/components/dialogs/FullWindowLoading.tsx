/** @format */

import { Spinner } from "react-bootstrap";

const FullWindowLoading = ({ message }: { message?: string }) => {
    return (
        <div className="container text-center m-5">
            <Spinner animation="border" />
            {message && <p className="m-3">{message}</p>}
        </div>
    );
};

export default FullWindowLoading;
