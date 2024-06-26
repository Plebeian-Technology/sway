// NOSONAR

import { setSwayLocale } from "app/frontend/redux/actions/localeActions";
import { setUser } from "app/frontend/redux/actions/userActions";
import { useEffect } from "react";
import { useDispatch } from "react-redux";
import { sway } from "sway";

interface IBaseProps {
    swayLocale: sway.ISwayLocale;
    user: sway.IUser;
}

interface IProps extends IBaseProps {
    [key: string]: any;
}

const SetupPage =
    (Component: React.FC<any>): React.FC<IProps> =>
    (props): React.ReactNode => {
        // eslint-disable-next-line
        const dispatch = useDispatch(); // NOSONAR

        // eslint-disable-next-line
        useEffect(() => {
            // NOSONAR
            dispatch(setUser(props.user));
            dispatch(setSwayLocale(props.swayLocale));
            // dispatch(setSwayLocales([props.swayLocale]));
        }, [dispatch, props.swayLocale, props.user]);

        return <Component {...props} />;
    };

export default SetupPage;
