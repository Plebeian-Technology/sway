import SwaySpinner from "../SwaySpinner";

const CenteredLoading = ({
    className,
    isHidden,
    message,
    style,
}: {
    message?: string;
    style?: React.CSSProperties;
    className?: string;
    isHidden?: boolean
}) => {
    const _style = style ? style : {};
    return (
        <div
            className={`d-flex flex-column align-items-center justify-content-center g-0 text-center w-100 h-100 ${
                className || ""
            } ${isHidden ? "hidden" : ""}`}
            style={{
                cursor: "wait",
                ..._style,
            }}
        >
            <SwaySpinner isHidden={isHidden} className={className} style={style} />
            &nbsp;
            {message && message}
        </div>
    );
};

export default CenteredLoading;
