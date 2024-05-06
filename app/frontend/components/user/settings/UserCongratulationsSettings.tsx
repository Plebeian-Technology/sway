import { sway } from "sway";
import SwayCheckbox from "../../shared/SwayCheckbox";

interface IProps {
    congratulationTypes: sway.ICongratulationsSettings;
    setCongratulationsTypes: (types: sway.ICongratulationsSettings) => void;
}

const UserCongratulationsSettings: React.FC<IProps> = ({
    congratulationTypes,
    setCongratulationsTypes,
}) => {
    const updateCongratulationTypes = (e: React.ChangeEvent<HTMLInputElement>) => {
        const { name } = e.target;
        setCongratulationsTypes({
            ...congratulationTypes,
            [name]: !congratulationTypes[name],
        });
    };

    return (
        <div className="col m-2">
            <div>
                <h4>Congratulations Settings</h4>
            </div>
            <div className="ms-3">
                <SwayCheckbox
                    name={"isCongratulateOnUserVote"}
                    id={"isCongratulateOnUserVote"}
                    label={"When you vote on a bill."}
                    checked={congratulationTypes.isCongratulateOnUserVote}
                    onChange={updateCongratulationTypes}
                    disabled={false}
                />
            </div>
            <div className="ms-3">
                <SwayCheckbox
                    name={"isCongratulateOnInviteSent"}
                    id={"isCongratulateOnInviteSent"}
                    label={"When you send an invite to a friend."}
                    checked={congratulationTypes.isCongratulateOnInviteSent}
                    onChange={updateCongratulationTypes}
                    disabled={false}
                />
            </div>
            <div className="ms-3">
                <SwayCheckbox
                    name={"isCongratulateOnSocialShare"}
                    id={"isCongratulateOnSocialShare"}
                    label={"When you share a bill on social media or through email."}
                    checked={congratulationTypes.isCongratulateOnSocialShare}
                    onChange={updateCongratulationTypes}
                    disabled={false}
                />
            </div>
        </div>
    );
};

export default UserCongratulationsSettings;
