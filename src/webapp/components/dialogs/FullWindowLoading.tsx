/** @format */

import { CircularProgress } from "@mui/material";
import { SWAY_COLORS } from "../../utils";

const FullWindowLoading = ({ message }: { message?: string }) => {
    return (
        <div
            style={{
                display: "flex",
                flexDirection: "column",
                alignItems: "center",
                justifyContent: "center",
                minHeight: "20vh",
                color: SWAY_COLORS.primary,
                cursor: "wait",
            }}
        >
            <CircularProgress color="inherit" />
            {message && <p style={{ margin: 10 }}>{message}</p>}
        </div>
    );
};

export default FullWindowLoading;
