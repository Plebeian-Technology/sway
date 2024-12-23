import PasskeyLogin from "app/frontend/pages/PasskeyLogin";
import { logDev } from "app/frontend/sway_utils";

const Home: React.FC<{ name?: string; isBubbles: boolean }> = ({ name, isBubbles: _isBubbles }) => {
    logDev("Home.tsx", name);
    return <PasskeyLogin />;
};

export default Home;
