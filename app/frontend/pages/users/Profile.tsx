import React from "react";
import { router } from "@inertiajs/react";
import { Card, CardContent, CardHeader, CardTitle } from "app/frontend/components/ui/card";
import { Button } from "app/frontend/components/ui/button";

interface IAddress {
    full_address: string;
}

interface IProps {
    user: {
        id: number;
        email: string;
        full_name: string;
        created_at: string;
    };
    address?: IAddress;
    is_api_user: boolean;
}

const Profile: React.FC<IProps> = ({ user, address, is_api_user }) => {
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
                                href="/sway_registration/edit"
                                className="text-sm text-blue-600 hover:underline"
                            >
                                Change Address
                            </a>
                        </div>
                    </div>
                </CardContent>
            </Card>

            <Card>
                <CardHeader>
                    <CardTitle>Account Management</CardTitle>
                </CardHeader>
                <CardContent className="space-y-4">
                    <a href="/users/passkeys" className="block text-blue-600 hover:underline">
                        Manage Passkeys
                    </a>
                    <a href="/notifications" className="block text-blue-600 hover:underline">
                        Notification Preferences
                    </a>
                    {is_api_user && (
                        <a href="/api_keys" className="block text-blue-600 hover:underline">
                            Manage API Keys
                        </a>
                    )}
                    <div className="pt-4 border-t space-y-2">
                        <Button
                            variant="destructive"
                            onClick={() => router.post(`/users/${user.id}/revoke_all_devices`)}
                            className="w-full"
                        >
                            Sign out all devices
                        </Button>
                        <Button
                            variant="destructive"
                            onClick={() => {
                                if (confirm("Are you sure? This action cannot be undone.")) {
                                    router.delete(`/users/${user.id}`)
                                }
                            }}
                            className="w-full"
                        >
                            Delete Account
                        </Button>
                    </div>
                </CardContent>
            </Card>
        </div>
    );
};

export default Profile;
