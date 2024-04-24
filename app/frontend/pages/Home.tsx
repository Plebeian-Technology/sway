import NoAuthLayout from "app/frontend/components/NoAuthLayout";
import Passkey from "app/frontend/pages/Passkey";
import { logDev } from "app/frontend/sway_utils";

const Home: React.FC<{ name?: string }> = ({ name }) => {
    logDev("Home.tsx", name);
    return <NoAuthLayout isBubbles><Passkey /></NoAuthLayout>;
};

export default Home;
