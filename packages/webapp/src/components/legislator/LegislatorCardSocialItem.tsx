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
        <div className="row align-items-center">
            <div onClick={setCopy} className="bold col-12 col-sm-2">
                {title}:
            </div>
            <div onClick={setCopy} className="ellipses col-12 col-sm-10 col-lg-8">
                {text}
            </div>
            <div className="col-3 col-md-3 col-lg-2 me-1">
                <Button onClick={setCopy}>
                    <FiCopy />
                </Button>
            </div>
            <div className="col-3 col-md-3 col-lg-2">
                <Button>
                    <Icon />
                </Button>
            </div>
        </div>
    );
};

export default LegislatorCardSocialItem;
