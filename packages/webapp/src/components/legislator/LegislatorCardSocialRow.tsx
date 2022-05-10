import copy from "copy-to-clipboard";
import { sway } from "sway";
import { notify } from "../../utils";
import LegislatorEmail from "./LegislatorEmail";
import LegislatorPhone from "./LegislatorPhone";
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
                    title: `Copied ${value} to clipboard.`,
                }),
        });
    };

    return (
        <div className="col-6">
            {legislator.email && (
                <div className="mb-1">
                    <LegislatorEmail
                        user={user}
                        locale={locale}
                        legislator={legislator}
                        handleCopy={handleCopy}
                    />
                </div>
            )}
            {legislator.phone && (
                <div className="my-1">
                    <LegislatorPhone
                        user={user}
                        locale={locale}
                        legislator={legislator}
                        handleCopy={handleCopy}
                    />
                </div>
            )}
            {legislator.twitter && (
                <div className="my-1">
                    <LegislatorTwitter legislator={legislator} handleCopy={handleCopy} />
                </div>
            )}
        </div>
    );
};

export default LegislatorCardSocialRow;
