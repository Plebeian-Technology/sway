import { CircularProgress, Typography } from "@material-ui/core";
import { sway } from "sway";

const CenteredLoading = ({
    message,
    color,
    style,
    textStyle,
}: {
    message?: string;
    color?: "primary" | "secondary";
    style?: sway.IPlainObject;
    textStyle?: sway.IPlainObject
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
            {message && message.split("\n").map((text: string, i: number) => {
                return <Typography key={i} variant={"body2"}  style={textStyle}>{text}</Typography>
            })}
        </div>
    );
};

export default CenteredLoading;
