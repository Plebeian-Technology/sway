import { PropsWithChildren } from "react";
import { Button } from "react-bootstrap";
import { FiCopy } from "react-icons/fi";
import { IS_MOBILE_PHONE } from "../../utils";

interface IProps {
    title: string;
    text: string;
    handleCopy: (text: string) => void;
    Icon: React.FC<any>;
}

const Div = ({ children, ...props }: PropsWithChildren<any>) => <div {...props}>{children}</div>;
const Span = ({ children, ...props }: PropsWithChildren<any>) => <span {...props}>{children}</span>;

const LegislatorCardSocialItem: React.FC<IProps> = ({ title, text, handleCopy, Icon }) => {
    const setCopy = () => {
        handleCopy(text);
    };

    const Component = IS_MOBILE_PHONE ? Div : Span;

    return (
        <>
            <div className="row align-items-center mt-2">
                <div className="col">
                    <Component onClick={setCopy} className={"bold"}>
                        {title}:
                    </Component>{" "}
                    <Component onClick={setCopy}>{text}</Component>
                </div>
            </div>
            <div className="row mt-1">
                <div className="col-6 col-sm-4 col-md-3 col-lg-2">
                    <Button onClick={setCopy}>
                        <FiCopy />
                    </Button>
                </div>
                <div className="col-6 col-sm-4 col-md-3 col-lg-2 ps-0">
                    <Button>
                        <Icon />
                    </Button>
                </div>
            </div>
        </>
    );
};

export default LegislatorCardSocialItem;
