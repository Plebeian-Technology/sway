import { REACT_SELECT_STYLES, toFormattedLocaleName } from "app/frontend/sway_utils";
import { isEmpty } from "lodash";
import { useCallback, useEffect, useMemo } from "react";
import Select, { SingleValue } from "react-select";
import { ISelectOption, sway } from "sway";
import { useLocale, useLocales } from "../../hooks/useLocales";

interface IProps {
    containerStyle?: React.CSSProperties;
    callahead?: () => void;
}

const toSelectOption = (l: sway.ISwayLocale): ISelectOption => ({ label: toFormattedLocaleName(l.name), value: l.id });

const LocaleSelector: React.FC<IProps> = ({ callahead }) => {
    // react-select renders without stylings the first time this is rendered
    // there are a few issues on github about this
    // https://github.com/JedWatson/react-select/issues/3309
    // https://github.com/JedWatson/react-select/issues/3680
    // https://github.com/JedWatson/react-select/issues/5710
    // https://github.com/JedWatson/react-select/issues/5937
    useEffect(() => {
        if (!localStorage.getItem("@sway/reloaded/react-select")) {
            localStorage.setItem("@sway/reloaded/react-select", "1");
            window.location.reload();
        }
    }, []);

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
                callahead?.();
                getLocale(Number(o.value));
            }
        },
        [getLocale, callahead],
    );

    return (
        <div className="row mt-2">
            <div className={"col-12"}>
                <Select
                    name="locales"
                    options={options}
                    value={selected}
                    onChange={handleChange}
                    menuPortalTarget={document.body}
                    menuPosition="fixed"
                    styles={REACT_SELECT_STYLES}
                />
            </div>
        </div>
    );
};

export default LocaleSelector;
