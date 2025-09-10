import LoginBubbles from "app/frontend/components/layouts/LoginBubbles";
import SwayBanner from "app/frontend/components/SwayBanner";
import { PropsWithChildren } from "react";
import { Alert } from "react-bootstrap";

interface IProps extends PropsWithChildren {
    isBubbles: true;
    [key: string]: any;
}

const NoAuthLayout: React.FC<IProps> = ({ children, isBubbles, ...props }) => {
    return (
        <LoginBubbles title={""} isBubbles={isBubbles}>
            {props.flash.alert && <Alert variant="danger">{props.flash.alert}</Alert>}
            {props.flash.notice && <Alert variant="info">{props.flash.notice}</Alert>}
            <div className="container">
                <div className="row align-items-center" style={{ height: "100vh" }}>
                    <div className="col-12 col-md-6">
                        <div className="row vh-100 align-items-center">
                            {children}
                            <div className="d-block d-md-none text-center mb-5 pb-5">
                                <SwayBanner maxWidth={"50vw"} />
                            </div>
                        </div>
                    </div>

                    <div className="d-none d-md-block col-12 col-md-6">
                        <div className="row">
                            <div className="col-1 col-md-0">&nbsp;</div>
                            <div className="col-10 col-lg-10 text-center">
                                <SwayBanner maxWidth={"30vw"} />
                            </div>
                            <div className="col-1 col-lg-2">&nbsp;</div>
                        </div>
                    </div>
                </div>
            </div>
        </LoginBubbles>
    );
};

// export default NoAuthLayout;

const NoAuthPageLayout = (page: React.JSX.Element) => {
    return <NoAuthLayout {...page.props}>{page}</NoAuthLayout>;
};
export default NoAuthPageLayout;
