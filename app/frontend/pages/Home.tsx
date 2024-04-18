import { logDev } from "app/frontend/sway_utils";
import LoginForm from "../components/user/LoginForm";

const Home: React.FC<{ name: string }> = ({ name }: { name: string }) => {
  logDev("HOME", name)
  return (
    <LoginForm />
  );
};

export default Home;
