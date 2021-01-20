import { LOCALES } from "@sway/constants";
import { sway } from "sway";
import { useLocale } from "../../hooks";
import { IS_DEVELOPMENT, notify } from "../../utils";
import { toFormattedLocaleName } from "../../utils/locales";
import SwaySelect from "../forms/SwaySelect";

interface IProps {
    locales?: sway.ILocale[];
    setLocale?: (locale: sway.ILocale) => void;
    containerStyle?: sway.IPlainObject;
}

const LocaleSelector: React.FC<IProps> = ({ locales, setLocale, containerStyle }) => {
    const [locale, dispatchLocale] = useLocale();

    const possibleLocales = locales ? locales : LOCALES;
    const value = locale || possibleLocales[0];
    if (!value) return null;


    const handleSetLocale = (_fieldName: string, newLocaleName: string) => {
        const newLocale = possibleLocales.find((l) => l.name === newLocaleName);
        if (!newLocale) {
            if (IS_DEVELOPMENT) {
                console.error("issue setting new locale, newLocale was falsey");
                console.log(newLocale, newLocaleName);
            }
            notify({
                level: "error",
                title: "Error Changing Locale",
                message: "Sorry about that. We're looking into it.",
            });
            return;
        }

        IS_DEVELOPMENT &&
            console.log("Dispatch new locale (dev)", newLocale.name);
        setLocale ? setLocale(newLocale) : dispatchLocale(newLocale);
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
