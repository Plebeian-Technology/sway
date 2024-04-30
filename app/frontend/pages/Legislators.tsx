/** @format */

import LocaleAvatar from "app/frontend/components/locales/LocaleAvatar";
import LocaleSelector from "app/frontend/components/user/LocaleSelector";
import { Fragment, useMemo } from "react";
import { sway } from "sway";


interface IProps {
    user: sway.IUserWithSettingsAdmin,
    legislators: sway.ILegislator[]
}

const Legislators: React.FC<IProps> = ({ legislators: representatives }) => {


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


    const render = useMemo(() => {
        return representatives.map((legislator: sway.ILegislator, index: number) => (
            <Fragment key={legislator.externalId}>
                <div
                    className={`row p-3 m-3 border rounded border-primary ${
                        index > 0 ? "my-3" : ""
                    }`}
                >
                    {/* <LegislatorCard legislator={legislator} /> */}
                </div>
                {index === representatives.length - 1 ? null : (
                    <div className="col-12 text-center">
                        <LocaleAvatar />
                    </div>
                )}
            </Fragment>
        ));
    }, [representatives]);

    return (
        <div className="row pb-5">
            <div className="col pb-5">
                <div className="row">
                    <div className="col">
                        <LocaleSelector />
                    </div>
                </div>

                <div className="row">
                    <div className="col">{render}</div>
                </div>
            </div>
        </div>
    );
};

export default Legislators;
