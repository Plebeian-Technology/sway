import { Phone } from "@material-ui/icons";
import copy from "copy-to-clipboard";
import { sway } from "sway";
import { notify } from "../../utils";
import LegislatorCardSocialItem from "./LegislatorCardSocialItem";
import LegislatorEmail from "./LegislatorEmail";
import LegislatorTwitter from "./LegislatorTwitter";

interface IProps {
    user: sway.IUser;
    locale: sway.ILocale;
    legislator: sway.ILegislator;
}

const LegislatorCardSocialRow: React.FC<IProps> = ({ user, locale, legislator }) => {
    const handleCopy = (value: string) => {
        copy(value, {
            message: "Click to Copy",
            format: "text/plain",
            onCopy: () =>
                notify({
                    level: "info",
                    title: "Copied!",
                    message: `Copied ${value} to clipboard`,
                }),
        });
    };

    return (
        <>
            {legislator.phone && (
                <LegislatorCardSocialItem
                    title={"Phone"}
                    text={legislator.phone}
                    handleCopy={handleCopy}
                    Icon={Phone}
                />
            )}
            {legislator.email && (
                <LegislatorEmail
                    user={user}
                    locale={locale}
                    legislator={legislator}
                    handleCopy={handleCopy}
                />
            )}
            {legislator.twitter && (
                <LegislatorTwitter
                    legislator={legislator}
                    handleCopy={handleCopy}
                />
            )}
        </>
    );
};

export default LegislatorCardSocialRow;
