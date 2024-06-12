import SwaySpinner from "app/frontend/components/SwaySpinner";
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
    callback?: () => void;
}

const toSelectOption = (l: sway.ISwayLocale): ISelectOption => ({ label: toFormattedLocaleName(l.name), value: l.id });

const LocaleSelector: React.FC<IProps> = ({ callback }) => {
    const { options, isLoading: isLoadingLocales } = useLocales();
    const [locale, getLocale, isLoadingLocale] = useLocale();

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
                getLocale(Number(o.value)).then(callback).catch(console.error);
            }
        },
        [callback, getLocale],
    );

    return (
        <Animate play={!!locale} start={{ opacity: 0 }} end={{ opacity: 1 }}>
            <div className="row mt-2">
                <div className={isLoadingLocales ? "col-11" : "col-12"}>
                    <Select
                        name="locales"
                        options={options}
                        value={selected}
                        onChange={handleChange}
                        styles={REACT_SELECT_STYLES}
                        isDisabled={isLoadingLocales || isLoadingLocale}
                    />
                </div>
                {isLoadingLocale ||
                    (isLoadingLocales && (
                        <div className="col-1">
                            <SwaySpinner isHidden={false} />
                        </div>
                    ))}
            </div>
        </Animate>
    );
};

export default LocaleSelector;
