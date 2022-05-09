import SwaySpinner from "../SwaySpinner";

const CenteredLoading = ({
    message,
    style,
    textStyle,
}: {
    message?: string;
    color?: "primary" | "secondary";
    style?: React.CSSProperties;
    textStyle?: React.CSSProperties;
}) => {
    const _style = style ? style : {};
    return (
        <div
            className="text-center mx-auto"
            style={{
                cursor: "wait",
                ..._style,
            }}
        >
            <SwaySpinner />
            {message &&
                message.split("\n").map((text: string, i: number) => {
                    return (
                        <span key={i} style={textStyle}>
                            {text}
                        </span>
                    );
                })}
        </div>
    );
};

export default CenteredLoading;
