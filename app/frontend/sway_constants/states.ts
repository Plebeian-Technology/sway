/** @format */

// https://en.wikipedia.org/wiki/List_of_North_American_Numbering_Plan_area_codes#United_States
const UNITED_STATES_AREA_CODES = [
    205, 251, 256, 334, 659, 938, 907, 236, 250, 778, 480, 520, 602, 623, 928, 327, 479, 501, 870, 209, 213, 279, 310,
    323, 341, 408, 415, 424, 442, 510, 530, 559, 562, 619, 626, 628, 650, 657, 661, 669, 707, 714, 747, 760, 805, 818,
    820, 831, 840, 858, 909, 916, 925, 949, 951, 303, 719, 720, 970, 203, 475, 860, 959, 302, 202, 771, 239, 305, 321,
    352, 386, 407, 448, 561, 656, 689, 727, 754, 772, 786, 813, 850, 863, 904, 941, 954, 229, 404, 470, 478, 678, 706,
    762, 770, 912, 943, 808, 208, 986, 217, 224, 309, 312, 331, 447, 464, 618, 630, 708, 730, 773, 779, 815, 847, 872,
    219, 260, 317, 463, 574, 765, 812, 930, 319, 515, 563, 641, 712, 316, 620, 785, 913, 270, 364, 502, 606, 859, 225,
    318, 337, 504, 985, 207, 227, 240, 301, 410, 443, 667, 339, 351, 413, 508, 617, 774, 781, 857, 978, 231, 248, 269,
    313, 517, 586, 616, 679, 734, 810, 906, 947, 989, 218, 320, 507, 612, 651, 763, 952, 228, 601, 662, 769, 314, 417,
    557, 573, 636, 660, 816, 975, 406, 308, 402, 531, 702, 725, 775, 603, 201, 551, 609, 640, 732, 848, 856, 862, 908,
    973, 505, 575, 212, 315, 332, 347, 516, 518, 585, 607, 631, 646, 680, 716, 718, 838, 845, 914, 917, 929, 934, 252,
    336, 704, 743, 828, 910, 919, 980, 984, 701, 216, 220, 234, 283, 326, 330, 380, 419, 440, 513, 567, 614, 740, 937,
    405, 539, 572, 580, 918, 458, 503, 541, 971, 215, 223, 267, 272, 412, 445, 484, 570, 582, 610, 717, 724, 814, 878,
    401, 803, 839, 843, 854, 864, 605, 423, 615, 629, 731, 865, 901, 931, 210, 214, 254, 281, 325, 346, 361, 409, 430,
    432, 469, 512, 682, 713, 726, 737, 806, 817, 830, 832, 903, 915, 936, 940, 945, 956, 972, 979, 385, 435, 801, 802,
    276, 434, 540, 571, 703, 757, 804, 826, 948, 206, 253, 360, 425, 509, 564, 304, 681, 262, 274, 414, 534, 608, 715,
    920, 307,
];

export const AREA_CODES_REGEX = new RegExp(`^(${UNITED_STATES_AREA_CODES.join("|")})\\d{7}`);

export const STATE_CODES_NAMES: {
    AL: "Alabama";
    AK: "Alaska";
    AS: "American Samoa";
    AZ: "Arizona";
    AR: "Arkansas";
    CA: "California";
    CO: "Colorado";
    CT: "Connecticut";
    DE: "Delaware";
    DC: "District Of Columbia";
    FM: "Federated States Of Micronesia";
    FL: "Florida";
    GA: "Georgia";
    GU: "Guam";
    HI: "Hawaii";
    ID: "Idaho";
    IL: "Illinois";
    IN: "Indiana";
    IA: "Iowa";
    KS: "Kansas";
    KY: "Kentucky";
    LA: "Louisiana";
    ME: "Maine";
    MH: "Marshall Islands";
    MD: "Maryland";
    MA: "Massachusetts";
    MI: "Michigan";
    MN: "Minnesota";
    MS: "Mississippi";
    MO: "Missouri";
    MT: "Montana";
    NE: "Nebraska";
    NV: "Nevada";
    NH: "New Hampshire";
    NJ: "New Jersey";
    NM: "New Mexico";
    NY: "New York";
    NC: "North Carolina";
    ND: "North Dakota";
    MP: "Northern Mariana Islands";
    OH: "Ohio";
    OK: "Oklahoma";
    OR: "Oregon";
    PW: "Palau";
    PA: "Pennsylvania";
    PR: "Puerto Rico";
    RI: "Rhode Island";
    SC: "South Carolina";
    SD: "South Dakota";
    TN: "Tennessee";
    TX: "Texas";
    UT: "Utah";
    VT: "Vermont";
    VI: "Virgin Islands";
    VA: "Virginia";
    WA: "Washington";
    WV: "West Virginia";
    WI: "Wisconsin";
    WY: "Wyoming";
} = {
    AL: "Alabama",
    AK: "Alaska",
    AS: "American Samoa",
    AZ: "Arizona",
    AR: "Arkansas",
    CA: "California",
    CO: "Colorado",
    CT: "Connecticut",
    DE: "Delaware",
    DC: "District Of Columbia",
    FM: "Federated States Of Micronesia",
    FL: "Florida",
    GA: "Georgia",
    GU: "Guam",
    HI: "Hawaii",
    ID: "Idaho",
    IL: "Illinois",
    IN: "Indiana",
    IA: "Iowa",
    KS: "Kansas",
    KY: "Kentucky",
    LA: "Louisiana",
    ME: "Maine",
    MH: "Marshall Islands",
    MD: "Maryland",
    MA: "Massachusetts",
    MI: "Michigan",
    MN: "Minnesota",
    MS: "Mississippi",
    MO: "Missouri",
    MT: "Montana",
    NE: "Nebraska",
    NV: "Nevada",
    NH: "New Hampshire",
    NJ: "New Jersey",
    NM: "New Mexico",
    NY: "New York",
    NC: "North Carolina",
    ND: "North Dakota",
    MP: "Northern Mariana Islands",
    OH: "Ohio",
    OK: "Oklahoma",
    OR: "Oregon",
    PW: "Palau",
    PA: "Pennsylvania",
    PR: "Puerto Rico",
    RI: "Rhode Island",
    SC: "South Carolina",
    SD: "South Dakota",
    TN: "Tennessee",
    TX: "Texas",
    UT: "Utah",
    VT: "Vermont",
    VI: "Virgin Islands",
    VA: "Virginia",
    WA: "Washington",
    WV: "West Virginia",
    WI: "Wisconsin",
    WY: "Wyoming",
};

export const STATE_NAMES_CODES: {
    Alabama: "AL";
    Alaska: "AK";
    "American Samoa": "AS";
    Arizona: "AZ";
    Arkansas: "AR";
    California: "CA";
    Colorado: "CO";
    Connecticut: "CT";
    Delaware: "DE";
    "District Of Columbia": "DC";
    "Federated States Of Micronesia": "FM";
    Florida: "FL";
    Georgia: "GA";
    Guam: "GU";
    Hawaii: "HI";
    Idaho: "ID";
    Illinois: "IL";
    Indiana: "IN";
    Iowa: "IA";
    Kansas: "KS";
    Kentucky: "KY";
    Louisiana: "LA";
    Maine: "ME";
    "Marshall Islands": "MH";
    Maryland: "MD";
    Massachusetts: "MA";
    Michigan: "MI";
    Minnesota: "MN";
    Mississippi: "MS";
    Missouri: "MO";
    Montana: "MT";
    Nebraska: "NE";
    Nevada: "NV";
    "New Hampshire": "NH";
    "New Jersey": "NJ";
    "New Mexico": "NM";
    "New York": "NY";
    "North Carolina": "NC";
    "North Dakota": "ND";
    "Northern Mariana Islands": "MP";
    Ohio: "OH";
    Oklahoma: "OK";
    Oregon: "OR";
    Palau: "PW";
    Pennsylvania: "PA";
    "Puerto Rico": "PR";
    "Rhode Island": "RI";
    "South Carolina": "SC";
    "South Dakota": "SD";
    Tennessee: "TN";
    Texas: "TX";
    Utah: "UT";
    Vermont: "VT";
    "Virgin Islands": "VI";
    Virginia: "VA";
    Washington: "WA";
    "West Virginia": "WV";
    Wisconsin: "WI";
    Wyoming: "WY";
} = {
    Alabama: "AL",
    Alaska: "AK",
    "American Samoa": "AS",
    Arizona: "AZ",
    Arkansas: "AR",
    California: "CA",
    Colorado: "CO",
    Connecticut: "CT",
    Delaware: "DE",
    "District Of Columbia": "DC",
    "Federated States Of Micronesia": "FM",
    Florida: "FL",
    Georgia: "GA",
    Guam: "GU",
    Hawaii: "HI",
    Idaho: "ID",
    Illinois: "IL",
    Indiana: "IN",
    Iowa: "IA",
    Kansas: "KS",
    Kentucky: "KY",
    Louisiana: "LA",
    Maine: "ME",
    "Marshall Islands": "MH",
    Maryland: "MD",
    Massachusetts: "MA",
    Michigan: "MI",
    Minnesota: "MN",
    Mississippi: "MS",
    Missouri: "MO",
    Montana: "MT",
    Nebraska: "NE",
    Nevada: "NV",
    "New Hampshire": "NH",
    "New Jersey": "NJ",
    "New Mexico": "NM",
    "New York": "NY",
    "North Carolina": "NC",
    "North Dakota": "ND",
    "Northern Mariana Islands": "MP",
    Ohio: "OH",
    Oklahoma: "OK",
    Oregon: "OR",
    Palau: "PW",
    Pennsylvania: "PA",
    "Puerto Rico": "PR",
    "Rhode Island": "RI",
    "South Carolina": "SC",
    "South Dakota": "SD",
    Tennessee: "TN",
    Texas: "TX",
    Utah: "UT",
    Vermont: "VT",
    "Virgin Islands": "VI",
    Virginia: "VA",
    Washington: "WA",
    "West Virginia": "WV",
    Wisconsin: "WI",
    Wyoming: "WY",
};

export const STATE_NAMES: [
    "Alabama",
    "Alaska",
    "American Samoa",
    "Arizona",
    "Arkansas",
    "California",
    "Colorado",
    "Connecticut",
    "Delaware",
    "District Of Columbia",
    "Federated States of Micronesia",
    "Florida",
    "Georgia",
    "Guam",
    "Hawaii",
    "Idaho",
    "Illinois",
    "Indiana",
    "Iowa",
    "Kansas",
    "Kentucky",
    "Louisiana",
    "Maine",
    "Marshall Islands",
    "Maryland",
    "Massachusetts",
    "Michigan",
    "Minnesota",
    "Mississippi",
    "Missouri",
    "Montana",
    "Nebraska",
    "Nevada",
    "New Hampshire",
    "New Jersey",
    "New Mexico",
    "New York",
    "North Carolina",
    "North Dakota",
    "Northern Mariana Islands",
    "Ohio",
    "Oklahoma",
    "Oregon",
    "Palau",
    "Pennsylvania",
    "Puerto Rico",
    "Rhode Island",
    "South Carolina",
    "South Dakota",
    "Tennessee",
    "Texas",
    "Utah",
    "Vermont",
    "Virgin Islands",
    "Virginia",
    "Washington",
    "West Virginia",
    "Wisconsin",
    "Wyoming",
] = [
    "Alabama",
    "Alaska",
    "American Samoa",
    "Arizona",
    "Arkansas",
    "California",
    "Colorado",
    "Connecticut",
    "Delaware",
    "District Of Columbia",
    "Federated States of Micronesia",
    "Florida",
    "Georgia",
    "Guam",
    "Hawaii",
    "Idaho",
    "Illinois",
    "Indiana",
    "Iowa",
    "Kansas",
    "Kentucky",
    "Louisiana",
    "Maine",
    "Marshall Islands",
    "Maryland",
    "Massachusetts",
    "Michigan",
    "Minnesota",
    "Mississippi",
    "Missouri",
    "Montana",
    "Nebraska",
    "Nevada",
    "New Hampshire",
    "New Jersey",
    "New Mexico",
    "New York",
    "North Carolina",
    "North Dakota",
    "Northern Mariana Islands",
    "Ohio",
    "Oklahoma",
    "Oregon",
    "Palau",
    "Pennsylvania",
    "Puerto Rico",
    "Rhode Island",
    "South Carolina",
    "South Dakota",
    "Tennessee",
    "Texas",
    "Utah",
    "Vermont",
    "Virgin Islands",
    "Virginia",
    "Washington",
    "West Virginia",
    "Wisconsin",
    "Wyoming",
];

export const COUNTRY_NAMES = ["United States"];
