import { logDev } from "app/frontend/sway_utils";
import LoginBubbles from "./LoginBubbles";
import { PropsWithChildren } from "react";
import SwayLogo from "app/frontend/components/SwayLogo";

const NoAuthLayout: React.FC<PropsWithChildren & { isBubbles?: boolean }> = ({ children, isBubbles }) => {
    logDev("NoAuthLayout.tsx", isBubbles)
    return (
        <LoginBubbles title={""} isBubbles={isBubbles}>
            <div>
                <div className="row pb-2">
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
export default NoAuthPageLayout
