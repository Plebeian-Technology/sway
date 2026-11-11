import React from "react";
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "app/frontend/components/ui/dialog";
import PasskeyPanel from "app/frontend/components/auth/PasskeyPanel";
import { sway } from "sway";

interface IProps {
    bill: sway.IBill;
    provisionalSupport?: sway.TUserSupport | null;
    open: boolean;
    onOpenChange: (open: boolean) => void;
}

// @lat: [[low-friction-voting#Provisional vote capture and cookie lifecycle]]
export const ProvisionalRegistrationModal: React.FC<IProps> = ({ bill, provisionalSupport, open, onOpenChange }) => {
    return (
        <Dialog open={open} onOpenChange={onOpenChange}>
            <DialogContent
                data-testid="provisional-registration-modal"
                className="sm:max-w-md p-0 overflow-hidden border-0 bg-transparent shadow-none"
            >
                <div className="sr-only">
                    <DialogHeader>
                        <DialogTitle>Verify your vote on {bill.external_id}</DialogTitle>
                        <DialogDescription>
                            Your provisional {provisionalSupport} vote is saved. Register to make your vote count.
                        </DialogDescription>
                    </DialogHeader>
                </div>
                <PasskeyPanel
                    title={`Verify your vote on ${bill.external_id}`}
                    subtitle={`You selected ${provisionalSupport ?? "a vote"}. Complete quick registration to make your voice count with your representative.`}
                />
            </DialogContent>
        </Dialog>
    );
};

export default ProvisionalRegistrationModal;
