import { logDev } from "app/frontend/sway_utils";
import LoginBubbles from "./LoginBubbles";
import { PropsWithChildren } from "react";

const NoAuthLayout: React.FC<PropsWithChildren & { isBubbles?: boolean }> = ({ children, isBubbles }) => {
    logDev("NoAuthLayout.tsx", children)
    return (
        <LoginBubbles title={""} isBubbles={isBubbles}>
            <div>
                <div className="row pb-2">
                    <div className="col">
                        <img src={"/assets/sway-us-light.png"} alt="Sway" />
                    </div>
                </div>
                <div className="row mt-2">
                    <div className="col">{children}</div>
                </div>
            </div>
        </LoginBubbles>
    );
};

export default NoAuthLayout;
