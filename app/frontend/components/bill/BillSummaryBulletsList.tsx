import { Fragment } from "react";

const BillSummaryBulletsList: React.FC<{
    points: string[];
    klass: string | undefined;
}> = ({ points, klass }) => {
    return (
        <ul className="mt-3">
            {points.map((point: string, index: number) => {
                if (index === 0) {
                    const [intro, first] = point.split(":");
                    if (!first) {
                        return (
                            <li key={index} className="m-2">
                                <span className={klass ? klass : ""}>{point}</span>
                            </li>
                        );
                    }
                    return (
                        <Fragment key={index}>
                            <span className={klass ? klass : ""}>{`${intro}:`}</span>
                            <li key={index} className="m-2">
                                <span className={klass ? klass : ""}>{first}</span>
                            </li>
                        </Fragment>
                    );
                }
                return (
                    <li key={index} className="m-2">
                        <span className={klass ? klass : ""}>{point}</span>
                    </li>
                );
            })}
        </ul>
    );
};

export default BillSummaryBulletsList;
