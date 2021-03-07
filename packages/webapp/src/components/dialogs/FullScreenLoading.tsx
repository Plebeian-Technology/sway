/** @format */

import React from "react";
import { Backdrop, CircularProgress } from "@material-ui/core";
import { SWAY_COLORS } from "../../utils";

const FullScreenLoading = ({ message }: { message?: string }) => {
    return (
        <Backdrop
            style={{
                display: "flex",
                flexDirection: "column",
                alignItems: "center",
                justifyContent: "center",
                zIndex: 100,
                color: SWAY_COLORS.primaryDark,
                cursor: "wait"
            }}
            open={true}
        >
            <CircularProgress color="inherit" />
            {message && <p style={{ margin: 10 }}>{message}</p>}
        </Backdrop>
    );
};

export default FullScreenLoading;
