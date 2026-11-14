// @lat: [[parity-copy-snapshot-testing#Why parityCopy.ts stands alone]]

export const PARITY_COPY = {
    bills: {
        title: "Past bills",
        allBillsTitle: "All Bills",
        pastBillsOfTheMonthTitle: "Past Bills of the Month",
        sessionLabel: "Session",
        showingCount: (count: number, formattedSwayLocaleName: string) =>
            `Showing ${count} bills for ${formattedSwayLocaleName}.`,
        noneFound: (formattedSwayLocaleName: string) => `No bills found for ${formattedSwayLocaleName}.`,
        loading: "Loading bills…",
        categoriesLabel: "Categories",
        allCategoriesLabel: "All categories",
        categoryFilterPlaceholder: "Filter categories…",
        noCategoriesFound: "No categories match.",
        clearCategoriesLabel: "Clear all",
        // @lat: [[bills-controller-design#Why the search and sort labels in parityCopy.ts note the underlying split]]
        searchLabel: "Search",
        searchPlaceholder: "Search bills…",
        sortLabel: "Sort",
        sortOptions: [
            { value: "introduced_date_time_utc:desc", label: "Newest first" },
            { value: "introduced_date_time_utc:asc", label: "Oldest first" },
            { value: "title:asc", label: "Title A–Z" },
            { value: "title:desc", label: "Title Z–A" },
        ] as const,
    },

    bill: {
        content: {
            howOthersVoted: "How others voted",
            voteBreakdown: "How the vote breaks down",
            swaysSummary: "Sway summary",
            whySupport: "Why support this bill",
            whyOppose: "Why oppose this bill",
            takeNextStep: "Take the next step",
        },
        officialSourceUnavailable: "Official source link is not available for this bill.",
        // @lat: [[ai-unreviewed-notice-component-design#Why the notice sentence lives in PARITY_COPY rather than component props]]
        aiUnreviewedNotice: "Generated using AI, not yet reviewed by a human.",
        viewOriginalText: "View official bill text",
        reportInaccurateSummary: "Report inaccurate summary",
        reportDialogTitle: "Report Inaccurate Summary",
        reportDialogDescription:
            "Help us improve Sway. If this summary contains factual errors, a misleading tone, or is missing amendments, let our editors know.",
        reportSubmittedTitle: "Thank you for your report",
        reportSubmittedMessage:
            "Our editors have been notified and will review the summary against the official legislative text.",
        alreadyReportedNotice:
            "You have already submitted a report for this bill summary. Our editors are reviewing it.",
        reportRateLimited: "You have sent several reports recently. Please wait a little while before sending another.",
        reportOffline: "Could not reach Sway. Check your connection and try again. Your report is still here.",
        reportFailed: "Could not send your report. Please try again.",
        detailError: "Could not load this bill. Pull to refresh.",
        noVotesYet: "No votes recorded yet.",
        compareWithReps: "Compare with representatives",
        voteOnPastLegislation: "Vote on past legislation",
        summaryPending: "Summary pending. Check back soon.",
        showMore: "Show more",
        showLess: "Show less",
        shareBill: "Share bill",
        shareCopied: "Bill link copied to clipboard.",
        asIntroduced: "As introduced",
        voteStatus: {
            notYetVoted:
                "Legislators have not yet voted on a final version of this bill. Until they do, Sway records the sponsor and any co-sponsors as voting For.",
            houseAndSenate: (house: string, senate: string) => `House voted on ${house}. Senate voted on ${senate}.`,
            houseOnly: (house: string) => `House voted on ${house}.`,
            senateOnly: (senate: string) => `Senate voted on ${senate}.`,
            voted: (date: string) => `Legislators voted on ${date}.`,
            maybeNoLongerInOffice: "Legislators that voted on this bill may no longer be in office.",
        },
    },

    org: {
        noSupport: "Sway has not yet found any statements of support for this legislation.",
        noOppose: "Sway has not yet found any statements of opposition for this legislation.",
    },

    votePanel: {
        title: "Your vote",
        forLabel: "For",
        forSublabel: "Support this legislation",
        againstLabel: "Against",
        againstSublabel: "Oppose this legislation",
        archivedBill: "This bill is archived, so voting is closed.",
        recordedVote: (support: "FOR" | "AGAINST") =>
            support === "FOR" ? "You recorded a For vote on this bill." : "You recorded an Against vote on this bill.",
    },

    billOfTheMonth: {
        empty: "No Bill of the Month is featured right now. Check back soon.",
        // @lat: [[bill-of-the-month-no-redirect-on-empty#Why an empty Bill of the Month stays on the page#Why the empty-state copy names the jurisdiction]]
        noneForLocale: (formattedSwayLocaleName: string) => `No Bill of the Month for ${formattedSwayLocaleName}.`,
        browseBills: "Browse all bills",
        title: "Bill of the Month",
    },

    vote: {
        confirmTitle: "This vote is final",
        confirmMessage: (support: "FOR" | "AGAINST", externalId: string) =>
            `Cast a ${support === "FOR" ? "For" : "Against"} vote on ${externalId}? Once recorded, it cannot be changed or withdrawn.`,
        confirmCancel: "Go back",
        confirmConfirm: "Cast vote",
        offlineMessage: "You need to be online to vote. Connect to the internet and try again.",
        processing: (support: "FOR" | "AGAINST") => `Saving your ${support === "FOR" ? "For" : "Against"} vote`,
    },

    localePicker: {
        title: "Select Locale",
        cancel: "Cancel",
    },

    legislators: {
        title: "Legislators",
        noneFound: (formattedSwayLocaleName: string) => `No representatives found for ${formattedSwayLocaleName}.`,
        // @lat: [[legislators-controller-design#Why waiting_for_new_term distinguishes empty list causes]]
        waitingForNewTerm: (formattedSwayLocaleName: string) =>
            `The term has ended for ${formattedSwayLocaleName}. Sway does not have the new term's representatives yet.`,
        searchAgain: "Search again",
        showCharts: "Show voter agreement",
        hideCharts: "Hide voter agreement",
        loading: "Loading legislators…",
        scoreAgreed: "Agreed",
        scoreDisagreed: "Disagreed",
        scoreNoVote: "No vote",
        // @lat: [[legislator-resource-design#Why term toggle and history copy coordinates with display_term]]
        tabCurrentTerm: "Current term",
        tabLifetime: "Lifetime",
        tabHistory: "History",
        endedStamp: "Ended",
        historyEmptyHeading: "No history yet",
        historyEmptyBody: "History builds when terms end or your representatives change.",
        historyLoadError: "Couldn't load your history. Try again.",
        historyRetry: "Try again",
        // @lat: [[legislator-botm-record#Bill of the Month voting record on the legislator page]]
        votingRecordHeading: "Bill of the Month Voting Record",
        votingRecordEmpty: "No Bills of the Month have come before this representative yet.",
        votingRecordLoadError: "Couldn't load the voting record.",
        legislatorVoteLabel: "Representative vote",
        yourVoteLabel: "Your vote",
        noRecordedVote: "No vote recorded",
        notVotedYet: "Not voted",
        agreedBadge: "Agreed",
        disagreedBadge: "Disagreed",
    },

    orgs: {
        title: "Organizations",
        noneFound: (formattedSwayLocaleName: string) => `No organizations found for ${formattedSwayLocaleName}.`,
        noPositions: "This organization hasn't published any positions yet.",
        follow: "Follow",
        following: "Following",
        followerLabel: (count: number) => (count === 1 ? "1 follower" : `${count} followers`),
        unfollow: "Unfollow",
    },

    // @lat: [[org-notification-cascade-and-defaults#Where organization notification copy is shared across pickers and settings]]
    orgNotifications: {
        prefsTitle: "Notification preferences",
        prefsSubtitle: (orgName: string) => `Choose what you hear about from ${orgName}.`,
        savePreferences: "Save preferences",
        skipForNow: "Skip for now",
        cadenceEveryChange: "Every change",
        cadenceDaily: "Daily digest",
        cadenceWeekly: "Weekly digest",
        eventNewPosition: "New position on a bill",
        eventSupportChange: "Change in support (for/against)",
        eventSummaryChange: "Summary update",
        panelTitle: "Organization position updates",
        panelDescription: "Get notified when organizations you follow publish or update their position on legislation.",
        defaultsEventsLabel: "Default for new follows",
        defaultsCadenceLabel: "Default delivery",
    },

    memberships: {
        title: "My Organizations",
        activeSectionLabel: "Active",
        pendingSectionLabel: "Pending invites",
        activeEmpty: "You are not a member of any organizations.",
        pendingEmpty: "No pending invitations.",
        tabPositions: "Positions",
        tabPendingChanges: "Pending Changes",
        tabMembers: "Members",
        acceptLabel: "Accept invite",
        declineLabel: "Decline",
        declineConfirmTitle: "Decline invitation?",
        declineConfirmBody: "You can request to join again later.",
        declineConfirmAction: "Decline",
    },

    positions: {
        supports: "Supports",
        opposes: "Opposes",
        empty: "No positions have been published for this organization.",
        newModalTitle: "Propose new position",
        newSubmitLabel: "Propose position",
        newBillPickerPlaceholder: "Search bills…",
        newSummaryPlaceholder: "Describe the organization's position…",
        newSourceUrlPlaceholder: "https://…",
    },

    pendingChanges: {
        empty: "No pending changes.",
        approveLabel: "Approve change",
        rejectLabel: "Reject",
        rejectConfirmTitle: "Reject this proposed change?",
        rejectConfirmBody: "This action cannot be undone.",
        rejectConfirmAction: "Reject",
    },

    members: {
        empty: "No members yet.",
        inviteLabel: "Invite a member",
        inviteSubmitLabel: "Send invite",
        inviteSuccess: "Invitation sent.",
        leaveOrgLabel: "Leave organization",
        leaveOrgConfirmTitle: "Leave organization?",
        leaveOrgConfirmBody: "You will lose access to this organization's membership features.",
        leaveOrgConfirmAction: "Leave",
    },

    auth: {
        passkeyPanel: {
            title: "Start or login with your phone number.",
            subtitle: "We'll use your phone to login with a passkey.",
            signInWithPasskey: "Sign in with a passkey",
            // @lat: [[discoverable-passkey-design#What the reader sees during passkey fallback and why it names no cause]]
            passkeyFallback: "Signing in with a passkey didn't work. Use your phone number below to continue.",
            orContinueWithPhone: "or continue with your phone",
            phoneLabel: "Phone number",
            phonePlaceholder: "(410) 555-0199",
            infoHint: "Your device may ask for permission to discover passkeys.",
            codeLabel: "Confirmation code",
            codePlaceholder: "123456",
            cancelCta: "Cancel",
            previewSway: "Preview Sway",
            // @lat: [[identity-and-access#Identity and access#The admin gate is a lint rule#Adding a passkey re-verifies by SMS first]]
            previewSwayUrl: "https://sway.vote/bill_of_the_month",
            continuePhone: "Continue with Phone",
            confirmCode: "Confirm code",
            resendCode: "Send a new code",
            codeResent: "We sent you a new code.",
            passkeyUnsupported: "This browser can't use passkeys yet. Update your browser or try another one.",
            inAppBrowserTitle: "Open Sway in your browser",
            inAppBrowserMessage:
                "This app's built-in browser can't set up a passkey. Copy the link, then open it in Safari or Chrome to sign up.",
            inAppBrowserCopyLink: "Copy link",
            inAppBrowserLinkCopied: "Link copied. Paste it into Safari or Chrome.",
            passkeyDismissed: "Passkey setup was cancelled. Press Confirm code to try again.",
            workingOn: "Working on it",
            validationPhone: "Your phone number must be 10 digits.",
            requestCodeError: "Could not send confirmation code. Please try again.",
            signInError: "Sign in failed. Please try again.",
            verifyError: "Verification failed. Please try again.",
        },
        hero: {
            headline: "Remember in November.",
            paragraph:
                "Vote along with your representatives on the issues that matter, and make your vote clear to them when it counts.",
        },
        deviceUnsupported: {
            title: "This device can't use Sway",
            body1: "Sway uses passkeys for secure sign-in. Your device doesn't support passkeys, so we can't sign you in here.",
            body2: "To use Sway, update your device to the latest iOS or Android version, or sign in from a phone or tablet that supports passkeys.",
            cta: "Back to sign in",
        },
    },

    profile: {
        title: "Profile",
        rows: {
            address: "Address",
            memberships: "My Memberships",
            notificationPrefs: "Notification Preferences",
            passkeyManagement: "Passkey Management",
            theme: "Theme",
            signOut: "Sign Out",
            signOutAll: "Sign Out All Devices",
            deleteAccount: "Delete Account",
        },
        account: {
            signOutAllTitle: "Sign out all devices",
            signOutAllBody: "You'll be signed out on every device. Sign back in with your passkey.",
            signOutAllAction: "Sign Out All Devices",
        },
    },

    notifications: {
        title: "Notifications",
        lead: "Choose how Sway reaches you. Bill of the Month is on by default; the others are opt-in.",
        botmAnnouncement: {
            label: "Bill of the Month announcements",
            description: "We'll let you know when a new Bill of the Month is published.",
        },
        legislatorVoted: {
            label: "Legislator voted on a bill you voted on",
            description: "Hear when one of your legislators casts a vote on a bill in your history.",
        },
        voteWindowClosing: {
            label: "Vote window closing soon",
            description: "A reminder before voting closes on a bill you haven't voted on yet.",
        },
        orgPositionTaken: {
            label: "Organization you follow took a position",
            description: "When an org you follow publishes a position on a new bill.",
        },
        push: {
            title: "Push Notifications",
            enableCta: "Enable push notifications",
            settingsCta: "Go to Settings",
            testCta: "Send test notification",
            testSentCopy: "Test notification sent.",
            testSendErrorCopy: "Could not send test notification.",
            deniedCopy: "Push notifications are disabled. Enable them in your device Settings.",
            subscribedCopy: "Push notifications are enabled on this device.",
            registeringCopy: "Registering this device…",
        },
        errorSave: "Could not update preference.",
        saved: "Notification preferences updated.",
        saving: "Saving…",
        saveError: "Couldn't save preferences. Try again.",
    },

    // @lat: [[theme-tokens#Why a token in the contract has to have a consumer]]
    theme: {
        auto: {
            label: "Auto",
        },
        light: {
            label: "Light",
        },
        dark: {
            label: "Dark",
        },
    },

    passkey: {
        title: "Passkey Management",
        lead: "Passkeys let you sign in without typing a code.",
        lastUsedPrefix: "Last used",
        neverUsed: "Never used",
        createdOnPrefix: "Created",
        devicePrefix: "Device",
        deviceUnknown: "Unknown device",
        empty: "No passkeys on this account.",
        errorLoad: "Could not load passkeys.",
        addCta: "Add a passkey",
        addLead: "Add this device so you can sign in on it without your phone. We'll text a code to confirm it's you.",
        addPhonePrompt: "Confirm the phone number on your account. We'll text you a code.",
        sendCodeCta: "Send code",
        deviceNameLabel: "Device name",
        deviceNamePlaceholder: "e.g. My laptop",
        codeLabel: "Confirmation code",
        codePlaceholder: "123456",
        codeSentHint: "Enter the code we texted you, name this device, and confirm.",
        addConfirmCta: "Add this device",
        addingLabel: "Adding…",
        cancelCta: "Cancel",
        addSuccess: "Passkey added.",
        addError: "Couldn't add the passkey. Please try again.",
        codeError: "That code didn't work. Please try again.",
    },

    address: {
        requestFailed: "Something went wrong sending your address. Please try again.",
        search: {
            noResults: "No matching addresses found. You can still submit the address as you typed it.",
            failed: "Address search is unavailable right now. You can still submit the address as you typed it.",
        },
        complete: {
            heading: "Complete your registration",
            lead: "Sway needs a little more information to match you with your representatives.",
            cta: "Find My Representatives",
            cancelCta: "Log Out",
        },
        edit: {
            saveCta: "Save address",
            cancelCta: "Cancel",
        },
        switchConfirm: {
            editLead:
                "Updating your address re-checks your district and legislators. Switching to a new address deactivates your current representative links, updates district scores, and records the change for audit.",
            title: "Confirm address change",
            body: "Switching your address will deactivate your current representative links, match you with the representatives for your new address, and record this switch so accounts cannot vote across multiple districts or locales.",
            confirmCta: "Confirm address change",
            cancelCta: "Keep current address",
        },
        processing: {
            title: "Finding your representatives",
            message: "Finding your representatives. This may take a moment...",
        },
        failed: {
            title: "Registration failed",
            message: "Registration failed. Please try again or contact support.",
            retryCta: "Try a different address",
        },
        sessionExpired: {
            title: "Session expired",
            message: "We couldn't find your session. Please sign in again to continue.",
            cta: "Sign in",
        },
        helper: {
            registeredVoterAdvisory:
                "If you are registered to vote, please complete each field to match — as closely as possible — what is on your voter registration.",
            registeredVoterConfirmation: {
                label: "This is the address where I'm registered to vote.",
                description: "Legislators want to hear from the people registered to vote in their district.",
            },
            registerToVote: "Register to vote",
            registerToVoteUrl: "https://www.vote.org/register-to-vote/",
            checkRegistration: "Check your voter registration",
            checkRegistrationUrl: "https://www.vote.org/am-i-registered-to-vote/",
            viewOnGitHubIntro: "Sway is open source.",
            viewOnGitHub: "View on GitHub",
            viewOnGitHubUrl: "https://github.com/Plebeian-Technology/sway",
        },
    },

    reassignment: {
        districtChanged: (districtName: string, repName: string) =>
            `Your voting district has changed to ${districtName}. Your new representative is ${repName}.`,
        successorSeeded: (newName: string, oldName: string, districtName: string) =>
            `${newName} has succeeded ${oldName} as your representative for ${districtName}.`,
        vacantSeat: (oldName: string, districtName: string) =>
            `${oldName} no longer represents ${districtName} and the seat is currently vacant.`,
        vacancyFilled: (newName: string, districtName: string) =>
            `${newName} has been seated as your new representative for ${districtName}.`,
        viewProfile: "View profile",
        dismiss: "Dismiss",
        ariaLabel: "Representative reassignment notice",
    },

    publicTestimony: {
        modal: {
            title: "Public Testimony",
            subtitle: (count: number) => (count === 1 ? "1 constituent letter" : `${count} constituent letters`),
            allTab: "All",
            supportTab: "Support",
            opposeTab: "Oppose",
            neutralTab: "Neutral",
            supportBadge: "Support",
            opposeBadge: "Oppose",
            neutralBadge: "Neutral",
            stancePrefix: "Position",
            empty: "No constituent testimony found.",
            loading: "Loading testimony…",
            loadError: "Couldn't load public testimony.",
            close: "Close",
            previousPage: "Previous",
            nextPage: "Next",
            pageIndicator: (page: number, totalPages: number) => `Page ${page} of ${totalPages}`,
        },
        section: {
            heading: "Public Testimony",
            subtitle: (count: number) =>
                count === 1 ? "1 constituent letter submitted" : `${count} constituent letters submitted`,
            browseButton: "Browse Public Letters",
            supportPill: "Support",
            opposePill: "Oppose",
            neutralPill: "Neutral",
        },
    },

    feed: {
        title: "Feed",
        emptyState: "Nothing here yet. New Bills of the Month and your representatives' votes will show up here.",
        dateHeadings: {
            today: "Today",
            yesterday: "Yesterday",
            earlierThisMonth: "Earlier this month",
        },
        voteLabels: {
            for: "For",
            against: "Against",
            abstain: "Abstain",
            you: "You",
            agree: "You agree",
            differ: "You differ",
            goVote: "Go vote",
            youVotedPrefix: "You voted ",
            youAbstained: "You abstained",
        },
        billOfTheMonthReleasedSuffix: (monthName: string) => `released the ${monthName} Bill of the Month`,
        legislatorVotedWithUser: "voted on a bill you voted on",
        legislatorVotedVerb: "voted ",
        aLocaleBill: (localeName: string) => `a ${localeName} bill`,
        legislatorAbstainedOnLocaleBill: (localeName: string) => `abstained on a ${localeName} bill`,
        organizationPositionTaken: (positionVerb: string, localeName: string) => `${positionVerb} a ${localeName} bill`,
        organizationPositionVerbs: {
            Support: "supports",
            Oppose: "opposes",
            Neutral: "is neutral on",
        },
        userJoinedActor: "You",
        userJoinedAction: "joined Sway",
        userJoinedSummary:
            "New Bills of the Month, your representatives' votes and positions from organizations you follow will show up here, newest first.",
        representativesFoundActor: "Sway",
        representativesFoundAction: "found your representatives",
        seeYourRepresentatives: "See your representatives",
        legislativeTermBegan: (localeName: string) => `New legislative term for ${localeName}!`,
        loadingMore: "Loading more...",
        offlineBody: "Reconnect to load your feed.",
        retry: "Retry",
        searchLabel: "Search your feed",
        searchPlaceholder: "Search bills, places and legislators",
        clearSearch: "Clear search",
        searchError: "Could not search your feed.",
        searchMatchCount: (count: number, query: string) =>
            `${count} ${count === 1 ? "item" : "items"} in your feed ${count === 1 ? "matches" : "match"} "${query}"`,
        searchNoMatches: (query: string) => `Nothing in your feed matches "${query}".`,
        searchBrowsePrefix: "Search covers your feed only. To find any bill, browse ",
        searchBrowseLink: "all bills",
        showNewItems: (count: number, isCapped: boolean) => (isCapped ? `Show ${count}+ new` : `Show ${count} new`),
        votedCount: (count: number) => `${count} voted`,
        viewedCount: (count: number) => `${count} viewed`,
        sharedCount: (count: number) => `${count} shared`,
    },
} as const;
