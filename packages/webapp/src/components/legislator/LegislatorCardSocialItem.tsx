import { Button } from "react-bootstrap";
import { FiCopy } from "react-icons/fi";

interface IProps {
    title: string;
    text: string;
    handleCopy: (text: string) => void;
    Icon: React.FC<any>;
}

const LegislatorCardSocialItem: React.FC<IProps> = ({ title, text, handleCopy, Icon }) => {
    const setCopy = () => {
        handleCopy(text);
    };

    return (
        <div className="col">
            <div className="row" onClick={setCopy}>
                <span className="bold">{title}:</span>
            </div>
            <div className="row" onClick={setCopy}>
                <span className="ellipses">{text}</span>
            </div>
            <div className="row align-items-center">
                <div className="col-3">
                    <Button onClick={setCopy}>
                        <FiCopy />
                    </Button>
                </div>
                <div className="col-6">
                    <Button>
                        <Icon />
                    </Button>
                </div>
            </div>
        </div>
    );
};

export default LegislatorCardSocialItem;
