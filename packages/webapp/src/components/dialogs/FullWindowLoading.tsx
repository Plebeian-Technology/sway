/** @format */

import SwaySpinner from "../SwaySpinner";

const FullWindowLoading = ({ message }: { message?: string }) => {
    return (
        <div className="container text-center col">
            <div className="row mt-5">
                <div className="col">{message && <div>{message}</div>}</div>
            </div>
            <div className="row mt-3">
                <div className="col">
                    <SwaySpinner />
                </div>
            </div>
        </div>
    );
};

export default FullWindowLoading;
