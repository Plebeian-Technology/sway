import SwaySpinner from "../SwaySpinner";

const CenteredLoading = ({
    message,
    style,
    className,
}: {
    message?: string;
    style?: React.CSSProperties;
    className?: string;
}) => {
    const _style = style ? style : {};
    return (
        <div
            className={`d-flex flex-column align-items-center justify-content-center g-0 text-center w-100 h-100 ${
                className || ""
            }`}
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
