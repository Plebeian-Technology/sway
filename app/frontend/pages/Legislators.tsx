/** @format */

import { router } from "@inertiajs/react";
import LegislatorCard from "app/frontend/components/legislator/LegislatorCard";
import LocaleAvatar from "app/frontend/components/locales/LocaleAvatar";
import SwayLoading from "app/frontend/components/SwayLoading";
import LocaleSelector from "app/frontend/components/user/LocaleSelector";
import { useFetch } from "app/frontend/hooks/useFetch";
import { useLocale } from "app/frontend/hooks/useLocales";
import { toFormattedLocaleName } from "app/frontend/sway_utils";
import { isEmpty } from "lodash";
import { useCallback, useMemo } from "react";
import { Button } from "react-bootstrap";
import { InView } from "react-intersection-observer";
import { sway } from "sway";

interface IProps {
    user: sway.IUser;
    sway_locale: sway.ISwayLocale;
    legislators: sway.ILegislator[];
}

const Legislators_: React.FC<IProps> = ({ legislators: representatives }) => {
    const [locale] = useLocale();

    const reps = useMemo(
        () => representatives.filter((l) => !locale?.id || l.sway_locale_id === locale?.id),
        [locale?.id, representatives],
    );

    const render = useMemo(() => {
        return reps.map((legislator: sway.ILegislator, index: number) => (
            <InView key={legislator.external_id} triggerOnce initialInView={index === 0}>
                {({ inView, ref }) => (
                    <div ref={ref}>
                        <div className={`row g-0 my-3`}>
                            <LegislatorCard legislator={legislator} inView={inView} />
                        </div>
                        {index === reps.length - 1 ? null : (
                            <div className="row">
                                <div className="col-12 text-center">
                                    <LocaleAvatar />
                                </div>
                            </div>
                        )}
                    </div>
                )}
            </InView>
        ));
    }, [reps]);

    const post = useFetch<void>("/user_legislators");
    const handleFindLegislators = useCallback(() => {
        if (!locale?.id) return;

        post({ sway_locale_id: locale.id })
            .then(() => {
                router.reload();
            })
            .catch(console.error);
    }, [locale?.id, post]);

    if (isEmpty(locale)) {
        return (
            <div className="mt-5">
                <SwayLoading />
            </div>
        );
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

const Legislators = Legislators_;
export default Legislators;
