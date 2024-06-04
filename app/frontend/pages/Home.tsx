import Passkey from "app/frontend/pages/Passkey";
import { logDev } from "app/frontend/sway_utils";

const Home: React.FC<{ name?: string; isBubbles: boolean }> = ({ name, isBubbles }) => {
    logDev("Home.tsx", name);
    return <Passkey />;
};

export default Home;
