import { sway } from "sway";
import { useLocale, useLocales } from "../../hooks";
import { isEmptyObject, IS_DEVELOPMENT, notify } from "../../utils";
import { toFormattedLocaleName } from "../../utils/locales";
import SwaySelect from "../forms/SwaySelect";

interface IProps {
    containerStyle?: sway.IPlainObject;
}

const LocaleSelector: React.FC<IProps> = ({ containerStyle }) => {
    const locales = useLocales();
    const [locale, dispatchLocale] = useLocale();

    const value = locale || locales[0];
    if (!value) return null;

    const handleSetLocale = (_fieldName: string, newLocaleName: string) => {
        const newLocale = locales.find((l) => l.name === newLocaleName);
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

        IS_DEVELOPMENT && console.log("Dispatch new locale (dev)", newLocale.name);
        dispatchLocale(newLocale);
    };

    if (isEmptyObject(locales)) return null;

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
                possibleValues: locales.map((l) => {
                    return {
                        label: toFormattedLocaleName(l.name),
                        value: l.name,
                    };
                }),
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
