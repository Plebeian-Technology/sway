import { LOCALES } from "@sway/constants";
import {
    LOCALE_NOT_LISTED_LABEL,
    logDev,
    toFormattedLocaleName,
} from "@sway/utils";
import { sway } from "sway";
import { notify } from "../../utils";
import SwaySelect from "../forms/SwaySelect";

interface IProps {
    locale?: sway.ILocale;
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
                title: "Error changing locale. Sorry about that. We're looking into it.",
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
                subLabel:
                    value.name !== LOCALE_NOT_LISTED_LABEL
                        ? ""
                        : "That's okay, we'll find your Congressional representatives and add your local legislators once your locale is added to Sway.",
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
