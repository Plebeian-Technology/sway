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

-   [Contributing](#contributing)
-   [Locales](#locales)
    -   [Current Supported Locales](#current-supported-locales)
    -   [Onboard a New Locale](#onboard-a-new-locale)
-   [Feature Roadmap](#feature-roadmap)

## Contributing

Sway is a forever free to use and open source application. We do not have ads and we will never.

Sway relies on people like you to support this venture. To get started, please see our [contributing guide](/CONTRIBUTING.md).

tl;dr

-   Create an issue.
-   Fork this repo.
-   Update code as needed.
-   Open a pull request with your changes linked to the aforementioned issue.

## Adding a New Locale

Sway is designed to work with and be extended to multiple locations regardless of city, region or country, and anyone and everyone is free to onboard a new municipality or `"locale"` into Sway.

### Current Supported Locales

-   Baltimore City, Maryland, United States - `baltimore-maryland-united_states`

### Onboarding

To add a new locale, create a new [Issue](https://github.com/dcordz/sway-rails/issues) and label it as `locale` and include the below files:

-   An SVG image avatar for the locale, usually a flag representing that municipality. See [/public/images/avatars/baltimore-maryland-united_states.svg](/public/images/avatars/baltimore-maryland-united_states.svg) as an example. Wikipedia and Twitter are good sources to get these from.

-   A `.geojson` file named `<city>-<region>-<country>.geojson` with locations of each district corresponding to the respective legislator. For example, GeoJSON data for Baltimore City can be found [here](https://data.baltimorecity.gov/datasets/council-district-2021) - other cities may have similar sources.

-   Adding new Bills, Organizations and LegislatorVotes requires administrative access to Sway. More importantly it requires a commmitment to selecting, researching and summarizing a Bill of the Week each week for your Sway locale.

-   To add and/or update Legislators in Sway, please provide a `legislators.json` file. For an example of the file structure, see [the Baltimore legislators.json file.](/storage/seeds/data/united_states/maryland/baltimore/legislators.json)

---

## Development

#### Create SSL Certificates for Local Development

```zsh
brew install mkcert
mkcert -install
mkcert localhost
mv localhost.pem config/ssl/cert.pem
mv localhost-key.pem config/ssl/key.pem
```

Once the above have been assembled, we will work with you to get them into Sway!

## Copyright / License

Copyright 2024 Plebeian Technologies, Inc.

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
