[![Twitter](https://img.shields.io/twitter/follow/Sway_Vote?label=Follow%20Sway&style=social)](https://twitter.com/Sway_Vote)
[![Patreon](https://img.shields.io/badge/Patreon-contribute-yellow.svg)](https://patreon.com/sway_vote)

<!-- [![Sway Logo](public/images/sway-us-light.png)](https://sway.vote) -->

<p align="center" width="100%">
    <img width="33%" src="public/images/Sway3.png"> 
</p>

Empower Your Vote - [https://sway.vote](https://sway.vote)

## What is Sway

Sway is a platform you can use to engage in the democratic process in the 21st century. With Sway, you can directly influence your elected representatives by voting on the same legislation that they do.

Sway was created to solve several issues of democracy:

1. Years can pass between elections that decide who will represent you.

2. Keeping track of how well your representatives have represented you can be difficult.

Because of these difficulties, it can be challenging to hold elected representatives accountable for their actions.

- [Participating](#participating)
- [Locales](#locales)
    - [Current Supported Locales](#current-supported-locales)
    - [Onboard a New Locale](#onboard-a-new-locale)
- [Development](#development)
    - [Environment Variables](#environment-variables)
    - [Running Sway](#running-sway)

## Participating

Sway is a forever free to use and open source application. We do not have ads and we will never.

Sway relies on people like you to support this venture. To get started, please see our [contributing guide](/CONTRIBUTING.md).

tl;dr

- Create an issue.
- Fork this repo.
- Update code as needed.
- Open a pull request with your changes linked to the aforementioned issue.

## Adding Your City, Region, and/or Country to Sway

Sway is designed to work with and be extended to multiple locations regardless of city, region or country, and anyone and everyone is free to onboard a new municipality or `"locale"` into Sway.

### Current Supported Locales

- Baltimore City, Maryland, United States - `baltimore-maryland-united_states`
- The State of Maryland, United States - `maryland-maryland-united_states`
- United States Congress - `congress-congress-united_states`

### Onboarding

To add a new locale, create a new [Issue](https://github.com/Plebeian-Technology/sway/issues) and label it as `locale` and include the below files:

- An SVG image avatar for the locale, usually a flag representing that municipality. See [/public/images/flags/baltimore-maryland-united_states.svg](/public/images/flags/baltimore-maryland-united_states.svg) as an example. Wikipedia and Twitter are good sources to get these from.

- A `.geojson` file named `<city>-<region>-<country>.geojson` with locations of each district corresponding to the respective legislator. For example, GeoJSON data for Baltimore City can be found [here](https://data.baltimorecity.gov/datasets/council-district-2021) - other cities may have similar sources.

- Adding new [Bills](/app/models/bill.rb), [Organizations](/app/models/organization.rb) and [LegislatorVotes](/app/models/legislator_vote.rb) requires administrative access to Sway. More importantly it requires a commmitment to selecting, researching and summarizing a [Bill of the Week](/app/controllers/bill_of_the_week_controller.rb) each week for your Sway locale.

- To add and/or update Legislators in Sway, please provide a `legislators.json` file. For an example of the file structure, see [the Baltimore legislators.json file.](/storage/seeds/data/united_states/maryland/baltimore/legislators.json)

- Existing seed files can be downloaded from Sway using `gsutil`:

```zsh
mkdir -p storage && gsutil -m cp -r \
  "gs://sway-assets/seeds" \
  storage/.
```

Once the above have been assembled, we will work with you to get them into Sway!

---

## Development

### Environment Variables

#### Create a .env.development file at the root directory of the project.

NOTE: All the values set here are only used for development and should NOT be commited to git. Values should not include opening and closing "".

#### Create a secret for API Key generation

```zsh
API_KEY_HMAC_SECRET_KEY=
```

This key can be created with the command:

```zsh
openssl rand -hex 32
```

#### Get an API Key from congress.gov for reading data from the Congress API:

- Visit [http://gpo.congress.gov/sign-up/](http://gpo.congress.gov/sign-up/)

```zsh
CONGRESS_GOV_API_KEY=
```

#### Get an API Key from Open States for reading data from the OpenStates API:

- Visit [https://docs.openstates.org/api-v3/](https://docs.openstates.org/api-v3/) and register for an API Key via pluralpolicy.com

```zsh
OPEN_STATES_API_KEY=
```

#### Sign up for Twilio and set the values the below keys:

[https://console.twilio.com/](https://console.twilio.com/)

You can get the ACCOUNT_SID and AUTH_TOKEN values by clicking "Account" at the top-right and then "API keys & tokens" on the left sidebar.

```zsh
TWILIO_ACCOUNT_SID=
TWILIO_AUTH_TOKEN=
TWILIO_VERIFY_SERVICE_SID=
```

To get a VERIFY_SERVICE_SID you must sign up for Twilio Verify, which Sway uses as one factor in the user authentication flow. To create a Verification Service you can use the Twilio API via the guide here - [https://www.twilio.com/docs/verify/api](https://www.twilio.com/docs/verify/api), or you can use the Twilio Console:

1. Click the "Develop" tab on the left sidebar.

2. Click "Explore Products +" on the left sidebar.

3. Scroll down and click "Verify".

4. Create a new Verify service.

#### Create a Google Cloud account and add values for the below keys:

[https://cloud.google.com/](https://cloud.google.com/)

```zsh
GOOGLE_MAPS_API_KEY=
```

Sway uses Google Maps for geocoding user addresses into latitude/longitude coordinates during registration. These coordinates are then used with a geojson file and Census.gov API to determine a user's representatives in a given SwayLocale.

To create this key:

1. Click on the Navigation menu.

2. Hover over APIs & Services and click 'Enabled APIs & services'

3. Click the "+ ENABLE APIS AND SERVICES" button at the top.

4. Enable the "Maps JavaScript API"

5. On the sidebar, click "Keys & Credentials"

6. Generate an API Key with:

    - a website restriction to localhost
    - The "Maps JavaScript API" selected
    - The "Places API" selected
    - The "Geocoding API" selected

#### Create VAPID keys and set values for the keys below:

```zsh
VAPID_PUBLIC_KEY=
VAPID_PRIVATE_KEY=
```

Sway uses these keys to send web push notifications via the [web-push](https://github.com/pushpad/web-push) ruby gem.

You can generate keys after running `bundle install` by opening the rails console with `rails c` and running:

```ruby
irb(main):001> WebPush.generate_key

=> #<WebPush::VapidKey:67d4 :public_key=BDH9S_5CtkeVBJmtGxcrXD7_bXyp4GyxYMiuH4Rlh0RW6dhsj3Arurxkf-0_BI2kLaUBFLcfIi9fi2K8wqxSUq0= :private_key=wsx-vK4_ZFULdXlqSnE2VJPc548k1ihydsfzqZKtDFY=>
```

Copy the full key, including the `=` at the end into each environment variable above.

You can read more about web push notifications here:

- [https://developer.mozilla.org/en-US/docs/Web/API/Push_API/Best_Practices](https://developer.mozilla.org/en-US/docs/Web/API/Push_API/Best_Practices)

- [https://web.dev/articles/push-notifications-web-push-protocol](https://web.dev/articles/push-notifications-web-push-protocol)

- [https://medium.com/@dejanvu.developer/implementing-web-push-notifications-in-a-ruby-on-rails-application-dcd829e02df0](https://medium.com/@dejanvu.developer/implementing-web-push-notifications-in-a-ruby-on-rails-application-dcd829e02df0)

#### Add your phone number as an Admin phone number by setting the below key in the same format:

```zsh
ADMIN_PHONES=1234567890
```

Only administrators can create new Bills in Sway.

#### Set a database password:

```zsh
SWAY_DATABASE_PASSWORD=sway2000!!
```

Just a reminder that this is only used for development.

### Running Sway

#### Create SSL Certificates

```zsh
brew install mkcert nss
mkcert -install
mkcert localhost
mkdir -p config/ssl
mv localhost.pem config/ssl/cert.pem
mv localhost-key.pem config/ssl/key.pem
```

1. In one terminal window/tab/pane:

#### Set up Rails

```zsh
bundle install
bundle exec rails db:create
bundle exec rails db:migrate
bundle exec rails db:schema:load

# Load seeds including locales and geojson files
bundle exec rails db:seed
```

#### Run Rails

```zsh
bin/rails server -b 'ssl://localhost:3000?key=config/ssl/key.pem&cert=config/ssl/cert.pem&verify_mode=none'
```

2. In a second terminal window/tab/pane:

#### Setup React with Vite

```zsh
npm install
```

#### Run React with Vite

```zsh
./bin/vite dev
```

#### Browser

Open your browser to [https://localhost:3000](https://localhost:3000) to begin working with Sway.

## Copyright / License

Copyright 2025 Plebeian Technologies, Inc.

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
