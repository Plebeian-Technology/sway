import SwayRegistration from "app/frontend/pages/SwayRegistration";

const AddressEdit = (props: any) => {
    return <SwayRegistration {...props} isChangeAddressMode={props.mode === "change_address"} />;
};

export default AddressEdit;
