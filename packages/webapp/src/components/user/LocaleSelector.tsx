import { LOCALES } from "@sway/constants";
import { toFormattedLocaleName } from "@sway/utils";
import { isEmpty } from "lodash";
import { useCallback, useMemo } from "react";
import { Form } from "react-bootstrap";
import Select, { SingleValue } from "react-select";
import { sway } from "sway";
import { useLocale, getDefaultSwayLocale } from "../../hooks/useLocales";
import { useUserLocales } from "../../hooks/useUsers";
import { notify, REACT_SELECT_STYLES, toSelectOption } from "../../utils";

interface IProps {
    containerStyle?: React.CSSProperties;
}

const LocaleSelector: React.FC<IProps> = () => {
    const [locale, dispatchLocale] = useLocale();
    const userLocales = useUserLocales();

    const possibleLocales = useMemo(
        () => (!isEmpty(userLocales) ? userLocales : LOCALES),
        [userLocales],
    );
    const selectedLocale = useMemo(() => {
        const l = locale || possibleLocales.first();
        if (l && !isEmpty(l)) {
            return l;
        } else {
            return getDefaultSwayLocale();
        }
    }, [locale, possibleLocales]);

    const handleSetLocale = useCallback(
        (selected: SingleValue<sway.TOption>) => {
            if (!selected?.value) return;

            const newLocale = possibleLocales.find(
                (l: sway.ILocale) => l.name === (selected.value as string),
            ) as sway.ILocale | null;
            if (!newLocale) {
                notify({
                    level: "error",
                    title: "Error changing locale. Sorry about that. We're looking into it.",
                });
            } else {
                dispatchLocale(newLocale);
            }
        },
        [possibleLocales, dispatchLocale],
    );

    const possibleValues = useMemo(
        () => possibleLocales.map((l) => toSelectOption(toFormattedLocaleName(l.name), l.name)),
        [possibleLocales],
    );

    return (
        <Form.Group controlId="locale-selector" className="mt-2">
            <Select
                name="locales"
                options={possibleValues}
                value={toSelectOption(
                    toFormattedLocaleName(selectedLocale.name),
                    selectedLocale.name,
                )}
                onChange={handleSetLocale}
                styles={REACT_SELECT_STYLES}
            />
        </Form.Group>
    );
};

export default LocaleSelector;
