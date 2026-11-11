import { usePoll } from "@inertiajs/react";

import { useSwayLocale, useSwayLocales } from "app/frontend/hooks/useSwayLocales";
import { useScoreSubscription } from "app/frontend/hooks/useScoreSubscription";
import { toFormattedLocaleName } from "app/frontend/sway_utils";
import InfluencePanel from "app/frontend/components/influence/InfluencePanel";
import { Label } from "app/frontend/components/ui/label";
import SwayLocalePicker from "app/frontend/components/locales/SwayLocalePicker";
import { sway } from "sway";

interface IProps {
    user: sway.IUser;
    influence: sway.IInfluence;
}

// @lat: [[partial-reload-poll-lists#Partial reload poll lists#What a tab's list has to carry besides its own props]]
const LOCALE_SWITCH_PROPS = ["influence", "sway_locale"];

const POLLING_PROPS = ["influence"];

const Influence: React.FC<IProps> = ({ influence }) => {
    usePoll(15000, { only: POLLING_PROPS }, { background: "pause" });
    useScoreSubscription(POLLING_PROPS);
    const [swayLocale, getSwayLocale, pendingSwayLocaleId] = useSwayLocale(LOCALE_SWITCH_PROPS);
    const { options } = useSwayLocales();

    return (
        <div className="space-y-6">
            <h1 className="text-2xl font-black">Your Sway</h1>

            <div className="space-y-2 rounded-xl border border-border bg-surface-2 p-4">
                <Label htmlFor="v2-influence-locale">Locale</Label>
                <SwayLocalePicker
                    id="v2-influence-locale"
                    options={options}
                    value={pendingSwayLocaleId ?? swayLocale?.id}
                    onChange={getSwayLocale}
                />
            </div>

            <InfluencePanel influence={influence} swayLocaleLabel={toFormattedLocaleName(swayLocale?.name ?? "")} />
        </div>
    );
};

export default Influence;
