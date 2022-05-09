import { LOCALES } from "@sway/constants";
import { logDev, toFormattedLocaleName } from "@sway/utils";
import { useCallback, useMemo } from "react";
import { Form } from "react-bootstrap";
import Select, { SingleValue } from "react-select";
import { sway } from "sway";
import { notify } from "../../utils";

interface IProps {
    locale?: sway.ILocale;
    locales?: sway.ILocale[];
    setLocale: (locale: sway.ILocale) => void;
    containerStyle?: sway.IPlainObject;
}

const LocaleSelector: React.FC<IProps> = ({ locale, setLocale, locales }) => {
    const possibleLocales = locales ? locales : LOCALES;
    const selected = locale || possibleLocales[0];
    const stringLocales = [JSON.stringify(possibleLocales)];

    const handleSetLocale = useCallback(
        (value: SingleValue<{ value: string; label: string }>) => {
            if (!value?.value) return;
            if (value.value === "not_listed?_select_congress_below") return;

            const newLocale = possibleLocales.find((l) => l.name === value.value);
            if (!newLocale) {
                console.error("issue setting new locale, newLocale was falsey");
                logDev(value, newLocale);
                notify({
                    level: "error",
                    title: "Error changing locale. Sorry about that. We're looking into it.",
                });
                return;
            }

            logDev("Dispatch new locale", newLocale.name);
            setLocale(newLocale);
        },
        [stringLocales],
    );

    const possibleValues = useMemo(
        () =>
            possibleLocales.map((l) => {
                return {
                    label: toFormattedLocaleName(l.name),
                    value: l.name,
                };
            }),
        stringLocales,
    );

    if (!selected) return null;
    // if (possibleLocales.length < 2) return null;

    return (
        <Form.Group controlId="locale-selector" className="mt-2">
            <Select
                value={{ value: selected.name, label: toFormattedLocaleName(selected.name) }}
                onChange={handleSetLocale}
                name="locales"
                options={possibleValues}
                styles={{
                    control: (provided) => ({
                        ...provided,
                        cursor: "pointer",
                    }),
                    option: (provided) => ({
                        ...provided,
                        cursor: "pointer",
                    }),
                }}
            />
        </Form.Group>
    );
};

export default LocaleSelector;
