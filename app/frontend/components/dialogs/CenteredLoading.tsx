import SwayLoading from "app/frontend/components/SwayLoading";

const CenteredLoading = ({
    className,
    isHidden,
    message,
    style,
}: {
    message?: string;
    style?: React.CSSProperties;
    className?: string;
    isHidden?: boolean;
}) => {
    return (
        <div
            className={`d-flex flex-column align-items-center justify-content-center g-0 text-center w-100 h-100 ${
                className || ""
            } ${isHidden ? "hidden" : ""}`}
            style={{
                cursor: isHidden ? "auto" : "wait",
                ...style,
            }}
        >
            <SwayLoading isHidden={isHidden} className={className} />
            &nbsp;
            {message}
        </div>
    );
};

export default CenteredLoading;
