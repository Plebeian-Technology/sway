/** @format */

import FullScreenLoading from "app/frontend/components/dialogs/FullScreenLoading";
import SetupPage from "app/frontend/components/hoc/SetupPage";
import LegislatorCard from "app/frontend/components/legislator/LegislatorCard";
import LocaleAvatar from "app/frontend/components/locales/LocaleAvatar";
import LocaleSelector from "app/frontend/components/user/LocaleSelector";
import { useAxiosPost } from "app/frontend/hooks/useAxios";
import { useLocale } from "app/frontend/hooks/useLocales";
import { toFormattedLocaleName } from "app/frontend/sway_utils";
import { isEmpty } from "lodash";
import { Fragment, useCallback, useMemo } from "react";
import { Button } from "react-bootstrap";
import { sway } from "sway";

interface IProps {
    user: sway.IUser;
    swayLocale: sway.ISwayLocale;
    legislators: sway.ILegislator[];
}

const _Legislators: React.FC<IProps> = ({ legislators: representatives, swayLocale }) => {
    const [locale] = useLocale(swayLocale);

    // useEffect(() => {
    //     const searchParams = new URLSearchParams(window.location.search);
    //     const queryStringCompletedRegistration =
    //         searchParams && searchParams.get(NOTIFY_COMPLETED_REGISTRATION);
    //     if (queryStringCompletedRegistration === "1") {
    //         if (localGet(NOTIFY_COMPLETED_REGISTRATION)) {
    //             searchParams.delete(NOTIFY_COMPLETED_REGISTRATION);
    //         } else {
    //             localSet(NOTIFY_COMPLETED_REGISTRATION, "1");
    //             notify({
    //                 level: "success",
    //                 title: withTadas("Welcome to Sway"),
    //                 message: "Click/tap here to start voting and earning Sway!",
    //                 tada: true,
    //                 duration: 200000,
    //                 onClick: () => navigate(ROUTES.billOfTheWeek),
    //             });
    //         }
    //     }
    // }, [navigate, search]);

    const reps = useMemo(
        () => representatives.filter((l) => !locale?.id || l.swayLocaleId === locale?.id),
        [locale?.id, representatives],
    );

    const render = useMemo(() => {
        return reps.map((legislator: sway.ILegislator, index: number) => (
            <Fragment key={legislator.externalId}>
                <div className={`row g-0 my-3`}>
                    <LegislatorCard legislator={legislator} />
                </div>
                {index === reps.length - 1 ? null : (
                    <div className="row">
                        <div className="col-12 text-center">
                            <LocaleAvatar />
                        </div>
                    </div>
                )}
            </Fragment>
        ));
    }, [reps]);

    const { post } = useAxiosPost("/user_legislators");
    const handleFindLegislators = useCallback(() => {
        if (!locale?.id) return;

        post({ swayLocale_id: locale?.id }).catch(console.error);
    }, [locale?.id, post]);

    if (isEmpty(locale)) {
        return <FullScreenLoading />;
    } else if (isEmpty(reps)) {
        return (
            <div className="container">
                <div className="col">
                    <LocaleSelector />

                    <div className="text-center py-5">
                        No representatives found for {toFormattedLocaleName(locale.name)}
                    </div>
                    <div className="text-center my-3">
                        <Button variant="primary" onClick={handleFindLegislators}>
                            Search Again
                        </Button>
                    </div>
                </div>
            </div>
        );
    } else {
        return (
            <div className="container">
                <div className="col">
                    <LocaleSelector />

                    {render}
                </div>
            </div>
        );
    }
};

const Legislators = SetupPage(_Legislators);
export default Legislators;
