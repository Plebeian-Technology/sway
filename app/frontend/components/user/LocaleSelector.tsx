import CenteredLoading from "app/frontend/components/dialogs/CenteredLoading";
import { toFormattedLocaleName } from "app/frontend/sway_utils";
import { isEmpty } from "lodash";
import { useCallback, useMemo } from "react";
import { Form } from "react-bootstrap";
import Select, { SingleValue } from "react-select";
import { ISelectOption, sway } from "sway";
import { useLocale, useLocales } from "../../hooks/useLocales";
import { REACT_SELECT_STYLES } from "../../sway_utils";

interface IProps {
    containerStyle?: React.CSSProperties;
}

const toSelectOption = (l: sway.ISwayLocale): ISelectOption => ({ label: toFormattedLocaleName(l.name), value: l.id })

const LocaleSelector: React.FC<IProps> = () => {
    const [locales] = useLocales();
    const [locale, getLocale] = useLocale();

    const options = useMemo(() => {
        return locales.map(toSelectOption)
    }, [locales])

    const selected = useMemo(() => {
        if (locale) {
            return toSelectOption(locale)
        } else if (isEmpty(locales)) {
            return {} as ISelectOption;
        } else {
            return toSelectOption(locales.first());
        }
    }, [locale, locales])

    const handleChange = useCallback((o: SingleValue<ISelectOption>) => {
        if (o) {
            getLocale(Number(o.value))
        }
    }, [getLocale])

    if (isEmpty(locales)) {
        return <CenteredLoading />
    }

    return (
        <Form.Group controlId="locale-selector" className="mt-2">
            <Select
                name="locales"
                options={options}
                value={selected}
                onChange={handleChange}
                styles={REACT_SELECT_STYLES}
            />
        </Form.Group>
    );
};

export default LocaleSelector;
