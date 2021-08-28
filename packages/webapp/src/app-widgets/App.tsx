import { createMuiTheme, ThemeProvider } from "@material-ui/core";
import { IS_MOBILE_PHONE, swayDarkBlue } from "../utils";
import VoteWidget from "./VoteWidget";

const App = () => {
    const theme = createMuiTheme({
        palette: {
            primary: {
                main: swayDarkBlue,
            },
        },
        typography: {
            fontFamily: [
                "Exo",
                "-apple-system",
                "BlinkMacSystemFont",
                '"Segoe UI"',
                "Roboto",
                '"Helvetica Neue"',
                "Arial",
                "sans-serif",
                '"Apple Color Emoji"',
                '"Segoe UI Emoji"',
                '"Segoe UI Symbol"',
            ].join(","),
        },
        overrides: {
            MuiInputBase: {
                root: {
                    color: "inherit",
                },
                input: {
                    color: "inherit",
                },
            },
            MuiFormLabel: {
                root: {
                    color: "inherit",
                    borderColor: "inherit",
                },
            },
            MuiOutlinedInput: {
                notchedOutline: {
                    borderColor: "inherit",
                },
            },
            MuiToolbar: {
                regular: {
                    minHeight: 50,
                },
            },
            MuiDialog: {
                paper: {
                    margin: IS_MOBILE_PHONE ? "0px" : "32px", // 32px is default
                },
            },
        },
    });

    return (
        <ThemeProvider theme={theme}>
            <VoteWidget />
        </ThemeProvider>
    );
};

export default App;
