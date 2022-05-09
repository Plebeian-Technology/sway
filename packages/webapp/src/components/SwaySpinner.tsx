import { Spinner } from "react-bootstrap";

interface IProps {
    className?: string;
    isHidden?: boolean;
}

const SwaySpinner: React.FC<IProps> = ({ className, isHidden }) => {
    return (
        <Spinner
            animation="border"
            className={`blue ${isHidden ? "invisible" : ""} ${className || ""}`}
        />
    );
};

export default SwaySpinner;
