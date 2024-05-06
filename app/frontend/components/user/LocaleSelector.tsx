import CenteredLoading from "app/frontend/components/dialogs/CenteredLoading";
import { toFormattedLocaleName } from "app/frontend/sway_utils";
import { isEmpty } from "lodash";
import { useCallback, useMemo } from "react";
import Select, { SingleValue } from "react-select";
import { Animate } from "react-simple-animate";
import { ISelectOption, sway } from "sway";
import { useLocale, useLocales } from "../../hooks/useLocales";
import { REACT_SELECT_STYLES } from "../../sway_utils";

interface IProps {
    containerStyle?: React.CSSProperties;
}

const toSelectOption = (l: sway.ISwayLocale): ISelectOption => ({ label: toFormattedLocaleName(l.name), value: l.id });

const LocaleSelector: React.FC<IProps> = () => {
    const [locale, getLocale] = useLocale();
    const [locales] = useLocales();

    const options = useMemo(() => {
        return locales.map(toSelectOption);
    }, [locales]);

    const selected = useMemo(() => {
        if (locale) {
            return toSelectOption(locale);
        } else if (isEmpty(locales)) {
            return {} as ISelectOption;
        } else {
            return toSelectOption(locales.first());
        }
    }, [locale, locales]);

    const handleChange = useCallback(
        (o: SingleValue<ISelectOption>) => {
            if (o) {
                getLocale(Number(o.value));
            }
        },
        [getLocale],
    );

    if (isEmpty(locales)) {
        return <CenteredLoading />;
    }

    return (
        <Animate play={!!locale} start={{ opacity: 0 }} end={{ opacity: 1 }}>
            <div className="mt-2">
                <Select
                    name="locales"
                    options={options}
                    value={selected}
                    onChange={handleChange}
                    styles={REACT_SELECT_STYLES}
                />
            </div>
        </Animate>
    );
};

export default LocaleSelector;
