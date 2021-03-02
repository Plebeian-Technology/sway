import { CircularProgress } from "@material-ui/core";
import { sway } from "sway";

const CenteredLoading = ({
    message,
    color,
    style,
}: {
    message?: string;
    color?: "primary" | "secondary";
    style?: sway.IPlainObject;
}) => {
    const _style = style ? style : {};
    return (
        <div
            style={{
                textAlign: "center",
                margin: "0 auto",
                cursor: "wait",
                ..._style,
            }}
        >
            <CircularProgress color={color ? color : "primary"} />
            {message && <span>{message}</span>}
        </div>
    );
};

export default CenteredLoading;
