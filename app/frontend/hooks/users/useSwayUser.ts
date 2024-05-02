import { omit } from "lodash";
import { useCallback } from "react";
import { useDispatch, useSelector } from "react-redux";
import { sway } from "sway";
import { IUserState, NON_SERIALIZEABLE_FIREBASE_FIELDS } from "../../sway_constants/users";
import { setUser } from "../../redux/actions/userActions";

const userState = (state: sway.IAppState): IUserState => {
    return state.user;
};

export const useSwayUser = (): [
    sway.IUser,
    (newUser: sway.IUser) => void,
] => {
    const dispatch = useDispatch();
    const setSwayUser = useCallback(
        (newUser: sway.IUser) => {
            if (newUser) {
                dispatch(setUser(omit(newUser, NON_SERIALIZEABLE_FIREBASE_FIELDS)));
            }
        },
        [dispatch],
    );
    return [useSelector(userState), setSwayUser];
};
