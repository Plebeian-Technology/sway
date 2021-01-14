/** @format */

import { Avatar, SvgIconTypeMap } from "@material-ui/core";
import AppBar from "@material-ui/core/AppBar";
import IconButton from "@material-ui/core/IconButton";
import { OverridableComponent } from "@material-ui/core/OverridableComponent";
import { createStyles, makeStyles, Theme } from "@material-ui/core/styles";
import Toolbar from "@material-ui/core/Toolbar";
import Typography from "@material-ui/core/Typography";
import MenuIcon from "@material-ui/icons/Menu";
import clsx from "clsx";
import React from "react";
import { useHistory } from "react-router-dom";
import { sway } from "sway";
import { useOpenCloseElement } from "../../hooks";
import { swayWhite } from "../../utils";

const useStyles = makeStyles((theme: Theme) =>
    createStyles({
        appBar: {
            color: swayWhite,
            zIndex: theme.zIndex.drawer + 1,
            transition: theme.transitions.create(["margin", "width"], {
                easing: theme.transitions.easing.sharp,
                duration: theme.transitions.duration.leavingScreen,
            }),
        },
        appBarShift: {
            width: `calc(100% - ${DRAWER_WIDTH}px)`,
            marginLeft: DRAWER_WIDTH,
            transition: theme.transitions.create(["margin", "width"], {
                easing: theme.transitions.easing.easeOut,
                duration: theme.transitions.duration.enteringScreen,
            }),
        },
        menuTitle: {
            display: "flex",
            flexDirection: "row",
            alignItems: "center",
        },
        menuAvatar: {
            marginRight: theme.spacing(1),
        },
        menuButton: {
            marginRight: theme.spacing(2),
        },
        hide: {
            display: "none",
        },
    }),
);

const DRAWER_WIDTH = 240;

type MenuItem = {
    route: string;
    Icon: OverridableComponent<SvgIconTypeMap<Record<string, unknown>, "svg">>;
    text: string;
};

interface IProps {
    locale: sway.ILocale;
    menuChoices: MenuItem[];
}

const AppHeaderBar = React.forwardRef<HTMLElement, IProps>(
    ({ locale, menuChoices }, ref) => {
        const classes = useStyles();
        const history = useHistory();
        const [open, setOpen] = useOpenCloseElement(
            ref as React.RefObject<HTMLElement>,
        );

        const menuTitle = (): string => {
            const title = (history?.location?.state as sway.IPlainObject)
                ?.title;
            if (title) return title;

            const items: MenuItem[] = menuChoices.filter(
                (item: MenuItem) => item.route === history?.location?.pathname,
            );
            if (!items || items.length === 0) {
                return menuChoices[0].text;
            }
            return items[0].text;
        };

        return (
            <AppBar
                ref={ref}
                position="fixed"
                className={clsx(classes.appBar, {
                    [classes.appBarShift]: open,
                })}
            >
                <Toolbar
                    style={{ cursor: "pointer" }}
                    onClick={() => setOpen(!open)}
                >
                    <IconButton
                        color="inherit"
                        aria-label="open drawer"
                        edge="start"
                        className={clsx(
                            classes.menuButton,
                            open && classes.hide,
                        )}
                    >
                        <MenuIcon />
                    </IconButton>
                    {locale && (
                        <div className={classes.menuTitle}>
                            <Avatar
                                className={classes.menuAvatar}
                                alt={`${locale.name} avatar`}
                                src={`/avatars/${locale.name}.svg`}
                            />
                            <Typography variant="h6" noWrap>
                                {menuTitle() || "Sway"}
                            </Typography>
                        </div>
                    )}
                </Toolbar>
            </AppBar>
        );
    },
);
export default AppHeaderBar;
