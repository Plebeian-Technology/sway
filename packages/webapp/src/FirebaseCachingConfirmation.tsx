/** @format */

import ConfirmationDialog from "./components/dialogs/ConfirmationDialog";
import LoginBubbles from "./components/user/LoginBubbles";

interface IProps {
    enablePersistence: (enable: boolean) => void;
}

const FirebaseCachingConfirmation: React.FC<IProps> = ({ enablePersistence }) => {
    return (
        <LoginBubbles>
            <ConfirmationDialog
                open={true}
                handleClose={enablePersistence}
                title={"Private Computer?"}
                text={
                    "Sway sometimes stores data in your browser to speed things up, but it's best to only do this on non-public computers. Would you like to enable this feature?"
                }
                options={{
                    truthy: "Yes",
                    falsey: "No",
                }}
            />
        </LoginBubbles>
    );
};

export default FirebaseCachingConfirmation;
