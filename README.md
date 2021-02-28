[![Twitter](https://img.shields.io/twitter/follow/Sway_Vote?label=Follow%20Sway&style=social)](https://twitter.com/Sway_Vote)
[![Patreon](https://img.shields.io/badge/Patreon-contribute-yellow.svg)](https://patreon.com/sway_vote)

# Sway

Empower Your Vote

## What is Sway

Sway is a platform you can use to engage in the democratic process in the 21st century. With Sway, you can directly influence your elected representatives by voting on the same legislation that they do.

Sway was created to solve several issues of democracy:

1. Years can pass between elections that decide who will represent you.

2. Keeping track of how well your representatives have represented you can be difficult.

Because of these difficulties, it can be challenging to hold elected representatives accountable for their actions.

* [Contributing](#contributing)
* [Locales](#locales)
  * [Current Supported Locales](#current-supported-locales)
  * [Onboard a New Locale](#onboard-a-new-locale)
* [Feature Roadmap](#feature-roadmap)

## Contributing

Sway is a forever free to use and open source application. We do not have ads and never will, and we will never.

Sway relies on people like you to support this venture. To get started, please see our [contributing guide](/CONTRIBUTING.md).

tl;dr

* Create an issue.
* Fork this repo.
* Update code as needed.
* Open a pull request with your changes linked to the aforementioned issue.

## Adding a New Locale

Sway is designed to work with, and be extended to, multiple locations regardless of city, region or country and anyone and everyone is free to onboard a new municipality or `"locale"` into Sway.

### Current Supported Locales

* Baltimore City, Maryland, United States - `baltimore-maryland-united_states`
* Washington, District of Columbia, United States - `washington-district_of_columbia-united_states`

### Onboarding

To add a new locale, create a new [Issue](https://github.com/Plebeian-Technology/sway/issues) and label it as `locale` and include the below files:

* An SVG image avatar for the locale, usually a flag representing that municipality. See [packages/webapp/public/avatars/baltimore-maryland-united_states.svg](/packages/webapp/public/avatars/baltimore-maryland-united_states.svg) as an example. Wikipedia and Twitter are good sources to get these from.

* A `.geojson` file named `<city>-<region>-<country>.geojson` with locations of each district corresponding to the respective legislator. For an example see [packages/functions/geojson/baltimore-maryland-united_states.geojson](/packages/functions/geojson/baltimore-maryland-united_states.geojson).

* A Microsoft Excel `.xlsx` file or a Comma-Separated Values `.csv` spreadsheet with 5 sheets (For an example spreadsheet see [https://docs.google.com/spreadsheets/d/1gTg19Lev54xqH744oPCMXrM3vFnLywNxwiTD_ZHAyHE/edit?usp=sharing](https://docs.google.com/spreadsheets/d/1gTg19Lev54xqH744oPCMXrM3vFnLywNxwiTD_ZHAyHE/edit?usp=sharing)):

  1. A sheet named `Locale` sheet listing the city, region, region code, country, districts and icon file name for the locale. (**Required**)

  2. A sheet named `Legislators` sheet with the title, first name, last name, external id and more information about each legislator in the locale. (**Required**)

  3. A sheet named `Legislator Votes` sheet with external bill id, external legislator id and how each legislator voted on the bill. (Optional)

  4. A sheet named `Bills` sheet with information about a handful of bills in the municipality. (Optional)

  5. A sheet named `Organizations` sheet with information about how different organizations have commented on legislation in the locale. (Optional)

---

Once the above have been assembled, we will work with you to get them into Sway!

## Built With

* [Firebase](https://firebase.google.com)
  * [Firestore](https://firebase.google.com/docs/firestore)
  * [Functions](https://firebase.google.com/docs/functions)
* [Create React App](https://github.com/facebook/create-react-app)
* [TypeScript](https://github.com/Microsoft/TypeScript)
* [Sass](https://sass-lang.com)

## Local Development

Local development can be done using the [firebase emulator suite](https://firebase.google.com/docs/emulator-suite), which can be installed with the [firebase-tools npm module](https://www.npmjs.com/package/firebase-tools).

```bash
npm i -g firebase-tools
```

Once installed, the Sway emulator can be started by running `./emulate.sh` from the root directory. Then start Sway by running the below from the root directory:

```bash
npm run start:emulate
```

Seed data for the emulator can be added by running from the root directory:

```bash
npm run seed:emulate
```

## Copyright / License

Copyright 2020 Plebeian Technologies, Inc.

Licensed under the GNU General Public License Version 3.0 (or later);
you may not use this work except in compliance with the License.
You may obtain a copy of the License in the LICENSE file, or at:

   [https://www.gnu.org/licenses/agpl-3.0.en.html](https://www.gnu.org/licenses/agpl-3.0.en.html)

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

Plebeian Technologies, Inc. is a 501(c)(3) not-for-profit corporation.
