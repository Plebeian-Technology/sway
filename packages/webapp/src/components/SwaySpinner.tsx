import { Spinner } from "react-bootstrap";

interface IProps {
    className?: string;
    isHidden?: boolean;
    style?: React.CSSProperties;
}

const SwaySpinner: React.FC<IProps> = ({ className, isHidden, style }) => {
    return (
        <Spinner
            animation="border"
            className={`blue ${isHidden ? "invisible" : ""} ${className || ""}`}
            style={style}
        />
    );
};

export default SwaySpinner;
