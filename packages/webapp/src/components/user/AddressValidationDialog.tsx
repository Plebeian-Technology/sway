/** @format */

import { Button, Modal } from "react-bootstrap";
import { sway } from "sway";
import CenteredLoading from "../dialogs/CenteredLoading";
import { IValidateResponseData } from "./RegistrationV2";
interface IAddressValidation {
    localeName: string;
    original: Partial<sway.IUser>;
    validated: IValidateResponseData;
}

interface IProps {
    cancel: () => void;
    confirm: ({ original, validated, localeName }: IAddressValidation) => void;
    original: Partial<sway.IUser>;
    validated: IValidateResponseData;
    localeName: string;
    isLoading: boolean;
    loadingMessage: string;
}

const AddressValidationDialog: React.FC<IProps> = ({
    confirm,
    cancel,
    original,
    validated,
    localeName,
    isLoading,
    loadingMessage,
}) => {
    const handleConfirm = () => {
        confirm({
            original,
            validated,
            localeName,
        });
    };

    const handleCancel = () => {
        cancel();
    };

    return (
        <Modal
            className={"hover-chart-dialog"}
            fullScreen={false}
            fullWidth
            open
            maxWidth={"xs"}
            onClose={cancel}
            aria-labelledby="address-validation-dialog"
        >
            <Modal.Header>
                <Modal.Title>
                    {validated ? "Confirm Your Address" : "Error Validating Address"}
                </Modal.Title>
            </Modal.Header>
            <Modal.Body>
                {isLoading && (
                    <CenteredLoading
                        textStyle={{
                            textAlign: "left",
                            margin: 5,
                            marginLeft: 0,
                        }}
                        message={loadingMessage}
                    />
                )}
                {validated && (
                    <div>
                        <div>
                            <p>{"Address: "}</p>
                            <p>{validated.address1}</p>
                        </div>
                        {validated.address2 && (
                            <div>
                                <p>{"Address 2: "}</p>
                                <p>{validated.address2}</p>
                            </div>
                        )}
                        <div>
                            <p>{"City: "}</p>
                            <p>{validated.city}</p>
                        </div>
                        <div>
                            <p>{"State: "}</p>
                            <p>{validated.region}</p>
                        </div>
                        <div>
                            <p>{"Zip Code: "}</p>
                            <p>{validated.postalCode}</p>
                        </div>
                        <div>
                            <p>{"Zip +4: "}</p>
                            <p>{validated.postalCodeExtension}</p>
                        </div>
                    </div>
                )}
                {!validated && <p>No worries, just keep going and we'll figure it out later.</p>}
            </Modal.Body>
            <Modal.Footer>
                <Button onClick={handleCancel} variant="secondary">
                    Cancel
                </Button>
                <Button onClick={handleConfirm} variant="primary" disabled={isLoading}>
                    {validated ? "Confirm" : "Okay"}
                </Button>
            </Modal.Footer>
        </Modal>
    );
};

export default AddressValidationDialog;
