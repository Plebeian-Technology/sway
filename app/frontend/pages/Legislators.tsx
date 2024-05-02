/** @format */

import LegislatorCard from "app/frontend/components/legislator/LegislatorCard";
import LocaleAvatar from "app/frontend/components/locales/LocaleAvatar";
import LocaleSelector from "app/frontend/components/user/LocaleSelector";
import { useLocale } from "app/frontend/hooks/useLocales";
import { logDev } from "app/frontend/sway_utils";
import { Fragment, useMemo } from "react";
import { sway } from "sway";

interface IProps {
    user: sway.IUser;
    legislators: sway.ILegislator[];
}

const Legislators: React.FC<IProps> = ({ legislators: representatives }) => {
    const [locale] = useLocale();
    logDev("representatives", representatives);

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

    logDev("RENDER", { locale, representatives });

    const render = useMemo(() => {
        return representatives
            .filter((l) => l.swayLocaleId === locale.id)
            .map((legislator: sway.ILegislator, index: number) => (
                <Fragment key={legislator.externalId}>
                    <div className={`row g-0 my-3`}>
                        <LegislatorCard legislator={legislator} />
                    </div>
                    {index === representatives.length - 1 ? null : (
                        <div className="row">
                            <div className="col-12 text-center">
                                <LocaleAvatar />
                            </div>
                        </div>
                    )}
                </Fragment>
            ));
    }, [locale.id, representatives]);

    return (
        <div className="container">
            <div className="col">
                <LocaleSelector />

                {render}
            </div>
        </div>
    );
};

export default Legislators;
