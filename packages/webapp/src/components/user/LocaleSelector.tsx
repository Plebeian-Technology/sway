import { LOCALES } from "@sway/constants";
import { logDev, toFormattedLocaleName } from "@sway/utils";
import { sway } from "sway";
import { notify } from "../../utils";
import SwaySelect from "../forms/SwaySelect";

interface IProps {
    locale: sway.ILocale;
    locales?: sway.ILocale[];
    setLocale: (locale: sway.ILocale) => void;
    containerStyle?: sway.IPlainObject;
}

const LocaleSelector: React.FC<IProps> = ({
    locale,
    setLocale,
    locales,
    containerStyle,
}) => {
    const possibleLocales = locales ? locales : LOCALES;
    const value = locale || possibleLocales[0];
    if (!value) return null;

    const handleSetLocale = (_fieldName: string, newLocaleName: string) => {
        if (!newLocaleName) return;
        if (newLocaleName === "not_listed?_select_congress_below") return;

        const newLocale = possibleLocales.find((l) => l.name === newLocaleName);
        if (!newLocale) {
            console.error("issue setting new locale, newLocale was falsey");
            logDev(newLocaleName, newLocale);
            notify({
                level: "error",
                message:
                    "Error changing locale. Sorry about that. We're looking into it.",
            });
            return;
        }

        logDev("Dispatch new locale", newLocale.name);
        setLocale(newLocale);
    };

    const possibleValues = possibleLocales.map((l) => {
        return {
            label: toFormattedLocaleName(l.name),
            value: l.name,
        };
    });

    return (
        <SwaySelect
            field={{
                name: "locales",
                type: "text",
                component: "select",
                label: "Locale",
                isRequired: false,
                default: value.name,
                disabled: false,
                possibleValues,
            }}
            error={""}
            handleSetTouched={() => null}
            setFieldValue={handleSetLocale}
            value={value.name}
            containerStyle={containerStyle && containerStyle}
        />
    );
};

export default LocaleSelector;
