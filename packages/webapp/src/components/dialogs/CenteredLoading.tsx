import SwaySpinner from "../SwaySpinner";

const CenteredLoading = ({
    message,
    style,
}: {
    message?: string;
    color?: "primary" | "secondary";
    style?: React.CSSProperties;
}) => {
    const _style = style ? style : {};
    return (
        <div
            className="row align-items-center justify-content-center no-gutters text-center w-100"
            style={{
                cursor: "wait",
                ..._style,
            }}
        >
            <SwaySpinner />
            &nbsp;
            {message && message}
        </div>
    );
};

export default CenteredLoading;
