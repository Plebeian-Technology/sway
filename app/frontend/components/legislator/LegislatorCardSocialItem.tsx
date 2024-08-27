import { IS_MOBILE_PHONE } from "app/frontend/sway_constants";
import { PropsWithChildren, useCallback } from "react";
import { Button } from "react-bootstrap";
import { FiCopy } from "react-icons/fi";

interface IProps {
    title: string;
    text: string;
    handleCopy: (text: string) => void;
    Icon: React.ReactNode;
}

const Div = ({ children, ...props }: PropsWithChildren<any>) => <div {...props}>{children}</div>;
const Span = ({ children, ...props }: PropsWithChildren<any>) => <span {...props}>{children}</span>;
const Component = IS_MOBILE_PHONE ? Div : Span;

const LegislatorCardSocialItem: React.FC<IProps> = ({ title, text, handleCopy, Icon }) => {
    const setCopy = useCallback(() => {
        handleCopy(text);
    }, [handleCopy, text]);

    return (
        <>
            <div className="row align-items-center mt-2">
                <div className="col">
                    <Component onClick={setCopy} className="bold">
                        {title}:
                    </Component>{" "}
                    <Component onClick={setCopy} className="text-break">
                        {text}
                    </Component>
                </div>
            </div>
            <div className="row mt-1">
                <div className="col-6 col-sm-4 col-md-3 col-lg-2">
                    <Button
                        variant="outline-primary"
                        className="text-primary-subtle border-primary-subtle"
                        onClick={setCopy}
                    >
                        <FiCopy />
                    </Button>
                </div>
                <div className="col-6 col-sm-4 col-md-3 col-lg-2 ps-0">
                    <Button variant="outline-primary" className="text-primary-subtle border-primary-subtle">
                        {Icon}
                    </Button>
                </div>
            </div>
        </>
    );
};

export default LegislatorCardSocialItem;
