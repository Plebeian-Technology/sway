import LoginBubbles from "./LoginBubbles";
import { PropsWithChildren } from "react";

const NoAuthLayout: React.FC<PropsWithChildren> = ({ children }) => (
    <LoginBubbles title={""}>
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

const NoAuthLayoutWithPage = (page: React.ReactNode) => <NoAuthLayout>{page}</NoAuthLayout>;

export default NoAuthLayoutWithPage;
