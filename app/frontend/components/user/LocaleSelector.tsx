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
    const { options } = useLocales();
    const [locale, getLocale] = useLocale();

    const selected = useMemo(() => {
        if (locale) {
            return toSelectOption(locale);
        } else if (isEmpty(options)) {
            return {} as ISelectOption;
        } else {
            return options.first();
        }
    }, [locale, options]);

    const handleChange = useCallback(
        (o: SingleValue<ISelectOption>) => {
            if (o) {
                getLocale(Number(o.value));
            }
        },
        [getLocale],
    );

    return (
        <Animate play={!!locale} start={{ opacity: 0 }} end={{ opacity: 1 }}>
            <div className="row mt-2">
                <div className={"col-12"}>
                    <Select
                        name="locales"
                        options={options}
                        value={selected}
                        onChange={handleChange}
                        styles={REACT_SELECT_STYLES}
                    />
                </div>
            </div>
        </Animate>
    );
};

export default LocaleSelector;
