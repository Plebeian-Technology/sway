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

* Create an issue
* Fork this repo
* Update code as needed
* Open a pull request with your changes linked to the aforementioned issue

## Locales

Sway is designed to work with, and be extended to, multiple localities regardless of city, region or country.

### Current Supported Locales

* Baltimore City, Maryland, United States
* Washington, District of Columbia, United States

### Onboard A New Locale

Onboarding a new location is simple in principle, although it can require a moderate amount of work to gather all the necessary data to launch.

First, keep in mind that the structure of a locale's name takes the form `<city>-<region>-<country>` where any part that is two or more words (ex. United States) is separated by an underscore (united_states). For example, for the City of Baltimore, Maryland the locale name would be:

```text
baltimore-maryland-united_states
```

In the above example the `<region>` is the US state where Baltimore is located.

To add a new locale, create a new [Issue](https://github.com/Plebeian-Technology/sway/issues) and label it as `locale` and include the below data:

Required:

* A link to a website for bills and votes can be found for the locale. For example:
  * [Baltimore, MD - Legistar](https://baltimore.legistar.com/Legislation.aspx)
  * [Washington, DC - LIMS](https://lims.dccouncil.us/)

* Add an svg avatar for the locale to `packages/webapp/public/avatars/<locale-name>.svg`

* Avatar images for each legislator in the locale. These will be uploaded to the firebase bucket.

* A Typescript file with an array of each Postal/Zip Codes (strings) in the locale. For example see [packages/seeds/src/data/united_states/maryland/baltimore/postalCodes.ts](/packages/seeds/src/data/united_states/maryland/baltimore/postalCodes.ts)

* A Typescript file with an array of district numbers in the locale. For example see [packages/seeds/src/data/united_states/maryland/baltimore/districts.ts](/packages/seeds/src/data/united_states/maryland/baltimore/districts.ts)

* A Typescript file with details of each legislator in the locale, see [packages/seeds/src/data/united_states/maryland/baltimore/legislators/index.ts](/packages/seeds/src/data/united_states/maryland/baltimore/legislators/index.ts) for functionality details.

* A geojson file named `<city>-<region>-<country>.geojson` with locations of each district corresponding to the respective legislator. For example see [packages/functions/geojson/baltimore-maryland-united_states.geojson](/packages/functions/geojson/baltimore-maryland-united_states.geojson)

Strongly Suggested:

* A Typescript file containing the external id of bills that have been voted on and each legislator's id and how they voted on that bill (For | Against | Abstain). For example see [packages/seeds/src/data/united_states/maryland/baltimore/legislator_votes/index.ts](/packages/seeds/src/data/united_states/maryland/baltimore/legislator_votes/index.ts)

* A Typescript file listing organizations and their positions on legislation in the locale. Used for seeding organizations. For example see [packages/seeds/src/data/united_states/maryland/baltimore/organizations/index.ts](/packages/seeds/src/data/united_states/maryland/baltimore/organizations/index.ts)

---

Once the above have been assembled, we will work with you to get them into Sway. You should be cognizant that this is not the end of what we need from you. Sway releases new bills of the week weekly for each locale, which requires a continued donation of time to discover, summarize and find opinions on, new bills of the week in your locale.

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
