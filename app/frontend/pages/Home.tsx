import LoginBubbles from "../components/user/LoginBubbles";

const Home: React.FC<{ name: string }> = ({ name }: { name: string }) => {
  return (
    <LoginBubbles title={""}>
      <div>
        <div className="row pb-2">
          <div className="col">
            <img src={"/assets/sway-us-light.png"} alt={name} />
            {/* <img src={"<%= image-url('/sway-us-light.png') %>"} alt={name} /> */}
          </div>
        </div>
      </div>
    </LoginBubbles>
  );
};

export default Home;
