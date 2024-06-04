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
        <div className={`text-center mx-auto ${isHidden ? "invisible" : ""}`}>
            {message && <div className="mt-3 bold blue">{message}</div>}
            <div>
                <Spinner
                    animation="border"
                    size={small ? "sm" : undefined}
                    className={className || "blue"}
                    style={style}
                />
            </div>
        </div>
    );
};

export default SwaySpinner;
