import { Twitter } from "@mui/icons-material";
import { titleize } from "@sway/utils";
import { sway } from "sway";
import { SWAY_COLORS } from "../../utils";
import LegislatorCardSocialItem from "./LegislatorCardSocialItem";

interface IProps {
    legislator: sway.ILegislator;
    handleCopy: (twitter: string) => void;
}

const Button = ({ city, twitter }: { twitter: string; city: string }) => {
    const handleClick = () => {
        try {
            window.open(
                `https://twitter.com/intent/tweet?&hashtags=Sway${titleize(
                    city,
                )}&screen_name=${twitter.replace("@", "")}&ref_src=twsrc%5Etfw`,
                "_blank",
                `menubar=no,toolbar=no,location=yes,height=900,width=900,left=${window.screenX}`,
            );
        } catch (error) {
            console.error(error);
        }
    };

    return (
        <Twitter style={{ color: SWAY_COLORS.white }} onClick={handleClick} />
    );
};

const LegislatorTwitter: React.FC<IProps> = ({ legislator, handleCopy }) => {
    const { twitter, city } = legislator;
    if (!twitter) return null;

    const formatTwitter = () => {
        if (twitter.startsWith("@")) return twitter;

        return `@${twitter}`;
    };

    return (
        <LegislatorCardSocialItem
            title={"Twitter"}
            text={formatTwitter()}
            handleCopy={handleCopy}
            Icon={() => <Button city={city} twitter={twitter} />}
        />
    );
};

export default LegislatorTwitter;