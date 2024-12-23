/** @format */

import { sway } from "sway";
import AddressAutocomplete from "./AddressAutocomplete";

interface IProps<T> {
    user: sway.IUser;
    field: sway.IFormField<T>;
    isLoading: boolean;
    // setCoordinates: (coords: { lat: number | undefined; lng: number | undefined }) => void;
    setLoading: (l: boolean) => void;
}

const RegistrationFields = <T,>({ setLoading, field }: IProps<T>) => {
    return <AddressAutocomplete key={field.name} field={field} setLoading={setLoading} />;
};

export default RegistrationFields;
