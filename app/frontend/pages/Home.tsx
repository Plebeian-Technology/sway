import Passkey from "app/frontend/pages/Passkey";

interface IProps {
    name?: string;
    isBubbles: boolean;
}

const Home: React.FC<IProps> = ({ name: _name, isBubbles: _isBubbles }) => {
    return <Passkey />;
};

export default Home;
