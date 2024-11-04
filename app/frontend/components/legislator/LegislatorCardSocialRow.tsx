import copy from "copy-to-clipboard";
import { useCallback } from "react";
import { sway } from "sway";
import { notify } from "../../sway_utils";
import LegislatorEmail from "./LegislatorEmail";
import LegislatorPhone from "./LegislatorPhone";
import LegislatorTwitter from "./LegislatorTwitter";

interface IProps {
    legislator: sway.ILegislator;
}

const LegislatorCardSocialRow: React.FC<IProps> = ({ legislator }) => {
    const handleCopy = useCallback(
        (value: string) => {
            copy(value, {
                message: "Click to Copy",
                format: "text/plain",
                onCopy: () =>
                    notify({
                        id: `legislator-${legislator.id}-${value}`,
                        level: "info",
                        title: (
                            <span>
                                Copied <span className="bold text-primary">{value}</span> to clipboard.
                            </span>
                        ),
                    }),
            });
        },
        [legislator.id],
    );

    return (
        <div className="col-6 col-sm-8">
            {legislator.email && (
                <div className="mb-1">
                    <LegislatorEmail legislator={legislator} handleCopy={handleCopy} />
                </div>
            )}
            {legislator.phone && (
                <div className="my-1">
                    <LegislatorPhone legislator={legislator} handleCopy={handleCopy} />
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
