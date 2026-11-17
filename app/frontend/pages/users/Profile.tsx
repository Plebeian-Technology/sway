import React from "react";
import { Card, CardContent, CardHeader, CardTitle } from "app/frontend/components/ui/card";

interface IAddress {
    full_address: string;
}

interface IProps {
    user: {
        email: string;
        full_name: string;
        created_at: string;
    };
    address?: IAddress;
}

const Profile: React.FC<IProps> = ({ user, address }) => {
    return (
        <div className="mx-auto w-full max-w-2xl space-y-6">
            <h1 className="text-2xl font-semibold tracking-tight">Your Profile</h1>
            <Card>
                <CardHeader>
                    <CardTitle>Account Details</CardTitle>
                </CardHeader>
                <CardContent className="space-y-4">
                    <div className="grid grid-cols-[1fr_2fr] gap-4">
                        <div className="font-semibold">Email:</div>
                        <div>{user.email}</div>
                        <div className="font-semibold">Full Name:</div>
                        <div>{user.full_name}</div>
                        <div className="font-semibold">Joined:</div>
                        <div>{new Date(user.created_at).toLocaleDateString()}</div>
                        <div className="font-semibold">Address:</div>
                        <div className="flex items-center justify-between">
                            <span>{address?.full_address || "No address set"}</span>
                            <a 
                                href="/sway_registration?action=change_address" 
                                className="text-sm text-blue-600 hover:underline"
                            >
                                Change Address
                            </a>
                        </div>
                    </div>
                </CardContent>
            </Card>
        </div>
    );
};

export default Profile;
