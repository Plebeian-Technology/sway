import { logDev } from "app/frontend/sway_utils";
import SignupPasskey from "app/frontend/pages/Passkey";

const Home: React.FC<{ name: string }> = ({ name }: { name: string }) => {
  logDev("HOME", name)
  return (
    <SignupPasskey />
  );
};

export default Home;
