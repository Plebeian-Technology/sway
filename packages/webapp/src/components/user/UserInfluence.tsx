import Paper from "@material-ui/core/Paper";
import Table from "@material-ui/core/Table";
import TableBody from "@material-ui/core/TableBody";
import TableCell from "@material-ui/core/TableCell";
import TableContainer from "@material-ui/core/TableContainer";
import TableHead from "@material-ui/core/TableHead";
import TableRow from "@material-ui/core/TableRow";
import { Facebook, Telegram, Twitter, WhatsApp } from "@material-ui/icons";
import { CLOUD_FUNCTIONS } from "@sway/constants";
import { isEmptyObject, toFormattedLocaleName } from "@sway/utils";
import React, { useEffect, useState } from "react";
import { sway } from "sway";
import { functions } from "../../firebase";
import { handleError } from "../../utils";
import CenteredLoading from "../dialogs/CenteredLoading";

interface IProps {
    user: sway.IUser | undefined;
}

interface IResponseData {
    locale: sway.IUserLocale;
    userSway: sway.IUserSway;
}

const UserInfluence: React.FC<IProps> = ({ user }) => {
    const [sways, setSway] = useState<IResponseData[]>([]);

    useEffect(() => {
        user &&
            user.locales &&
            Promise.all(
                user.locales.map((userLocale: sway.IUserLocale) => {
                    const getter = functions.httpsCallable(
                        CLOUD_FUNCTIONS.getUserSway,
                    );
                    return getter({
                        uid: user.uid,
                        locale: userLocale,
                    });
                }),
            )
                .then(
                    (
                        responses: firebase.default.functions.HttpsCallableResult[],
                    ) => {
                        console.log(responses);

                        setSway(responses.map((r) => r.data));
                    },
                )
                .catch(handleError);
    }, [setSway]);

    console.log({ sways });

    if (!user) {
        return null;
    }

    if (isEmptyObject(sways)) {
        return (
            <CenteredLoading
                message={"Loading Your Sway..."}
                style={{ margin: "20px auto" }}
            />
        );
    }

    return (
        <>
            {sways.map((s: IResponseData, i: number) => (
                <div
                    key={s.locale.name}
                    style={{
                        width: "80%",
                        margin: "50px auto",
                    }}
                >
                    <h2>{toFormattedLocaleName(s.locale.name)}</h2>
                    <TableContainer component={Paper}>
                        <Table aria-label="simple table">
                            <TableHead>
                                <TableRow>
                                    <TableCell>Votes</TableCell>
                                    <TableCell>Invitations Used</TableCell>
                                    <TableCell>Bills Shared</TableCell>
                                    <TableCell>Total Shares</TableCell>
                                    <TableCell>
                                        <Twitter />
                                    </TableCell>
                                    <TableCell>
                                        <Facebook />
                                    </TableCell>
                                    <TableCell>
                                        <WhatsApp />
                                    </TableCell>
                                    <TableCell>
                                        <Telegram />
                                    </TableCell>
                                </TableRow>
                            </TableHead>
                            <TableBody>
                                <TableRow key={s.locale.name + i}>
                                    <TableCell>
                                        {s.userSway.countBillsVotedOn}
                                    </TableCell>
                                    <TableCell>
                                        {s.userSway.countInvitesUsed}
                                    </TableCell>
                                    <TableCell>
                                        {s.userSway.countBillsShared}
                                    </TableCell>
                                    <TableCell>
                                        {s.userSway.countAllBillShares}
                                    </TableCell>
                                    <TableCell>
                                        {s.userSway.countTwitterShares}
                                    </TableCell>
                                    <TableCell>
                                        {s.userSway.countFacebookShares}
                                    </TableCell>
                                    <TableCell>
                                        {s.userSway.countWhatsappShares}
                                    </TableCell>
                                    <TableCell>
                                        {s.userSway.countTelegramShares}
                                    </TableCell>
                                </TableRow>
                            </TableBody>
                        </Table>
                    </TableContainer>
                </div>
            ))}
        </>
    );
};

export default UserInfluence;
