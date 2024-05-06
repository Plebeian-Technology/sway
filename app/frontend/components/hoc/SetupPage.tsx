// NOSONAR

import { setSwayLocale, setSwayLocales } from "app/frontend/redux/actions/localeActions";
import { setUser } from "app/frontend/redux/actions/userActions";
import { useEffect } from "react";
import { useDispatch } from "react-redux";
import { sway } from "sway";

interface IBaseProps {
    sway_locale: sway.ISwayLocale;
    user: sway.IUser;
}

interface IProps extends IBaseProps {
    [key: string]: any;
}

const SetupPage =
    (Component: React.FC<any>): React.FC<IProps> =>
    ({ user, sway_locale, ...props }): React.ReactNode => {
        // eslint-disable-next-line
        const dispatch = useDispatch(); // NOSONAR

        // eslint-disable-next-line
        useEffect(() => { // NOSONAR
            dispatch(setUser(user));
            dispatch(setSwayLocale(sway_locale));
            dispatch(setSwayLocales([sway_locale]));
        }, [dispatch, sway_locale, user]);

        return <Component {...props} />;
    };

export default SetupPage;
