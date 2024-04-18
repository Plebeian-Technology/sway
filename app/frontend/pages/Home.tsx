import LoginForm from "../components/user/LoginForm";

const Home: React.FC<{ name: string }> = ({ name }: { name: string }) => {
  return (
    <LoginForm />
  );
};

export default Home;
