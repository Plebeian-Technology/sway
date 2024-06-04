/** @format */

import { isCongressLocale, isEmptyObject, logDev } from "app/frontend/sway_utils";
import { useRef, useState } from "react";
import { sway } from "sway";
import { useOpenCloseElement } from "../../../hooks/elements/useOpenCloseElement";
import { isEmptyScore } from "../../../sway_utils/charts";
import DialogWrapper from "../../dialogs/DialogWrapper";
import { BillChartFilters } from "./constants";
import DistrictVotesChart from "./DistrictVotesChart";
import TotalVotesChart from "./TotalVotesChart";
import { useAxiosGet } from "app/frontend/hooks/useAxios";
import FullScreenLoading from "app/frontend/components/dialogs/FullScreenLoading";
import { Button } from "react-bootstrap";

interface IProps {
    bill: sway.IBill;
    locale: sway.ISwayLocale;
    userVote: sway.IUserVote;
    filter?: string;
}

export interface IChildChartProps {
    bill: sway.IBill;
    score: sway.IBillScore;
    district: sway.IDistrict;
    isEmptyScore: boolean;
}

interface IChartChoice {
    key: string;
    Component: React.FC<IChildChartProps>;
    props: { district: sway.IDistrict };
}

const BillChartsContainer: React.FC<IProps> = ({ bill, locale, filter }) => {
    const ref: React.MutableRefObject<HTMLDivElement | null> = useRef(null);
    const [open, setOpen] = useOpenCloseElement(ref);
    const [selected, setSelected] = useState<number>(-1);

    const { items: billScore } = useAxiosGet<sway.IBillScore>(`/bill_scores/${bill.id}`);

    const handleSetSelected = (index: number) => {
        setOpen(true);
        setSelected(index);
    };
    const handleClose = () => {
        setOpen(false);
        setSelected(-1);
    };

    const components = [
        {
            key: BillChartFilters.district,
            Component: DistrictVotesChart,
            props: {
                district: locale.districts.find((d) => d.number !== 0) as sway.IDistrict,
            },
        },
        isCongressLocale(locale)
            ? {
                  key: BillChartFilters.state,
                  Component: DistrictVotesChart,
                  props: {
                      district: locale.districts.find((d) => d.number !== 0) as sway.IDistrict,
                  },
              }
            : null,
        {
            key: BillChartFilters.total,
            Component: TotalVotesChart,
            props: {
                district: locale.districts.find((d) => d.number === 0) as sway.IDistrict,
            },
        },
    ];

    if (isEmptyObject(billScore)) {
        logDev(`Empty bill scores for bill - ${bill.externalId} - skipping render bill charts.`);
        return null;
    }

    const selectedChart = selected > -1 && components[selected];

    const charts = [];
    for (const component of components) {
        if (component) {
            if (filter) {
                if (component?.key === filter) {
                    charts.push(component);
                } else {
                    // no-op, component key !== filter
                }
            } else {
                charts.push(component);
            }
        }
    }

    if (!billScore) {
        return <FullScreenLoading />;
    }

    return (
        <div ref={ref} className="row">
            {charts.map((item: IChartChoice | null, index: number) => {
                if (!item) return null;

                if (isCongressLocale(locale) && index === 1) {
                    return (
                        <Button
                            key={index}
                            className="d-block col hover-chart w-100"
                            onClick={() => handleSetSelected(index)}
                        >
                            <item.Component
                                score={billScore}
                                bill={bill}
                                isEmptyScore={isEmptyScore(billScore)}
                                district={item.props.district as sway.IDistrict}
                            />
                        </Button>
                    );
                }
                return (
                    <div key={index} className="col hover-chart" onClick={() => handleSetSelected(index)}>
                        <item.Component
                            score={billScore}
                            bill={bill}
                            isEmptyScore={isEmptyScore(billScore)}
                            district={item.props.district as sway.IDistrict}
                        />
                    </div>
                );
            })}
            {selectedChart && (
                <DialogWrapper open={open} setOpen={handleClose}>
                    <selectedChart.Component
                        score={billScore}
                        bill={bill}
                        isEmptyScore={isEmptyScore(billScore)}
                        district={selectedChart.props.district as sway.IDistrict}
                    />
                </DialogWrapper>
            )}
        </div>
    );
};

export default BillChartsContainer;
