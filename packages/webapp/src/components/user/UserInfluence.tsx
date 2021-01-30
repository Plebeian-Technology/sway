import Paper from "@material-ui/core/Paper";
import Table from "@material-ui/core/Table";
import TableBody from "@material-ui/core/TableBody";
import TableCell from "@material-ui/core/TableCell";
import TableContainer from "@material-ui/core/TableContainer";
import TableHead from "@material-ui/core/TableHead";
import TableRow from "@material-ui/core/TableRow";
import { CLOUD_FUNCTIONS } from "@sway/constants";
import { useEffect, useState } from "react";
import { sway } from "sway";
import { getUserLocales, isEmptyObject } from "@sway/utils";
import { functions } from "../../firebase";
import CenteredLoading from "../dialogs/CenteredLoading";
import { handleError } from "../../utils";
import LocaleSelector from "./LocaleSelector";
import { useLocale } from "../../hooks";

interface IProps {
    user: sway.IUser;
}

interface IResponseData {
    locale: sway.IUserLocale;
    userSway: sway.IUserSway;
}

const UserInfluence: React.FC<IProps> = ({ user }) => {
    const [locale, setLocale] = useLocale(user);
    const [sways, setSway] = useState<IResponseData[]>([]);
    useEffect(() => {
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
                    setSway(responses.map((r) => r.data));
                },
            )
            .catch(handleError);
    }, [setSway]);

    if (isEmptyObject(sways)) {
        return <CenteredLoading />;
    }

    return (
        <>
            <div className={"locale-selector-container"}>
                <LocaleSelector
                    locale={locale}
                    locales={getUserLocales(user)}
                    setLocale={setLocale}
                    containerStyle={{ width: "90%" }}
                />
            </div>
            <TableContainer component={Paper}>
                <Table aria-label="simple table">
                    <TableHead>
                        <TableRow>
                            <TableCell>Votes</TableCell>
                            <TableCell align="right">
                                Invitations Sent
                            </TableCell>
                            <TableCell align="right">Bills Shared</TableCell>
                            <TableCell align="right">Total Shares</TableCell>
                        </TableRow>
                    </TableHead>
                    <TableBody>
                        {sways
                            .filter((s) => s.locale.name === locale.name)
                            .map((s: IResponseData) => (
                                <TableRow key={s.locale.name}>
                                    <TableCell component="th" scope="row">
                                        {s.userSway.countBillsVotedOn}
                                    </TableCell>
                                    <TableCell align="right">
                                        {s.userSway.countInvitesUsed}
                                    </TableCell>
                                    <TableCell align="right">
                                        {s.userSway.countBillsShared}
                                    </TableCell>
                                    <TableCell align="right">
                                        {s.userSway.countAllBillShares}
                                    </TableCell>
                                </TableRow>
                            ))}
                    </TableBody>
                </Table>
            </TableContainer>
        </>
    );
};

export default UserInfluence;
