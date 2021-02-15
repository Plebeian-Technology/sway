import { Typography } from "@material-ui/core";
import React from "react";
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
    const updateCongratulationTypes = (
        e: React.ChangeEvent<HTMLInputElement>,
    ) => {
        const { name } = e.target;
        console.log({ name });

        setCongratulationsTypes({
            ...congratulationTypes,
            [name]: !congratulationTypes[name],
        });
    };

    return (
        <div
            style={{
                margin: 10,
                display: "flex",
                flexDirection: "column",
                alignItems: "flex-start",
                justifyContent: "center",
            }}
        >
            <div>
                <Typography variant={"h4"} component={"h4"}>
                    Congratulations Settings
                </Typography>
            </div>
            <div style={{ marginLeft: 20 }}>
                <SwayCheckbox
                    name={"isCongratulateOnUserVote"}
                    id={"isCongratulateOnUserVote"}
                    label={"When you vote on a bill."}
                    checked={congratulationTypes.isCongratulateOnUserVote}
                    onChange={updateCongratulationTypes}
                    disabled={false}
                />
            </div>
            <div style={{ marginLeft: 20 }}>
                <SwayCheckbox
                    name={"isCongratulateOnInviteSent"}
                    id={"isCongratulateOnInviteSent"}
                    label={"When you send an invite to a friend."}
                    checked={congratulationTypes.isCongratulateOnInviteSent}
                    onChange={updateCongratulationTypes}
                    disabled={false}
                />
            </div>
            <div style={{ marginLeft: 20 }}>
                <SwayCheckbox
                    name={"isCongratulateOnSocialShare"}
                    id={"isCongratulateOnSocialShare"}
                    label={
                        "When you share a bill on social media or through email."
                    }
                    checked={congratulationTypes.isCongratulateOnSocialShare}
                    onChange={updateCongratulationTypes}
                    disabled={false}
                />
            </div>
        </div>
    );
};

export default UserCongratulationsSettings;
