import { Spinner } from "react-bootstrap";

interface IProps {
    className?: string;
    isHidden?: boolean;
    message?: string;
    small?: boolean;
    style?: React.CSSProperties;
}

const SwaySpinner: React.FC<IProps> = ({ className, isHidden, message, small, style }) => {
    return (
        <div className="text-center mx-auto">
            {message && <div className="my-2 bold">{message}</div>}
            <div>
                <Spinner
                    animation="border"
                    variant="info"
                    size={small ? "sm" : undefined}
                    className={`blue ${isHidden ? "invisible" : ""} ${className || ""}`}
                    style={style}
                />
            </div>
        </div>
    );
};

export default SwaySpinner;
