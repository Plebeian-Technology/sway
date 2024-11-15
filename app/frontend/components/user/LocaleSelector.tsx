import { toFormattedLocaleName } from "app/frontend/sway_utils";
import { isEmpty } from "lodash";
import { useCallback, useMemo } from "react";
import { Fade } from "react-bootstrap";
import Select, { SingleValue } from "react-select";
import { ISelectOption, sway } from "sway";
import { useLocale, useLocales } from "../../hooks/useLocales";
import { REACT_SELECT_STYLES } from "../../sway_utils";

interface IProps {
    containerStyle?: React.CSSProperties;
    callback?: () => void;
}

const toSelectOption = (l: sway.ISwayLocale): ISelectOption => ({ label: toFormattedLocaleName(l.name), value: l.id });

const LocaleSelector: React.FC<IProps> = ({ callback }) => {
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
                callback?.();
            }
        },
        [getLocale, callback],
    );

    return (
        <Fade in={!!locale}>
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
        </Fade>
    );
};

export default LocaleSelector;
