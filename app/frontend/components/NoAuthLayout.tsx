import SwayLogo from "app/frontend/components/SwayLogo";
import { PropsWithChildren } from "react";
import LoginBubbles from "./LoginBubbles";

const NoAuthLayout: React.FC<PropsWithChildren & { isBubbles?: boolean }> = ({ children, isBubbles }) => {
    return (
        <LoginBubbles title={""} isBubbles={isBubbles}>
            <div className="fade-in-and-up">
                <div className="row pb-2 mt-5 pt-5">
                    <div className="col text-center">
                        <SwayLogo />
                    </div>
                </div>
                <div className="row mt-2">
                    <div className="col">{children}</div>
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
