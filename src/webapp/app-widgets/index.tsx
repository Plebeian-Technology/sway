import ReactDOM from "react-dom";
import { StrictMode } from "react";
import App from "./App";
import "../scss/main.scss";

ReactDOM.render(
    <StrictMode>
        <App />
    </StrictMode>,
    document.getElementById("root"),
);
