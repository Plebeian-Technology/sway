/** @format */

import SwaySpinner from "../SwaySpinner";

const FullWindowLoading = ({ message }: { message?: string }) => {
    return (
        <div className="container text-center m-5">
            <SwaySpinner />
            {message && <p className="m-3">{message}</p>}
        </div>
    );
};

export default FullWindowLoading;
