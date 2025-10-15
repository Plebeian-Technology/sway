package mailers

// This file contains local placeholder structs to allow the mailers package
// to compile, as the main models package is incomplete.

// User represents a user.
type User struct {
	FullName           string
	IsRegisteredToVote bool
	Address            *Address
}

// Address represents a user's address.
type Address struct {
	FullAddress string
}

// Legislator represents a legislator.
type Legislator struct {
	FullName string
	Title    string
	LastName string
	AtLarge  bool
	Email    string
}

// Bill represents a legislative bill.
type Bill struct {
	Link       string
	ExternalID string
	Title      string
}

// SwayLocale represents a locale.
type SwayLocale struct {
	City string
}

// UserVote represents a user's vote on a bill.
type UserVote struct {
	Support string // "FOR", "AGAINST"
}

// UserLegislatorEmail represents the data for an email to a legislator.
type UserLegislatorEmail struct {
	User       *User
	Legislator *Legislator
	Bill       *Bill
	SwayLocale *SwayLocale
	UserVote   *UserVote
}

// Organization represents an organization.
type Organization struct {
	Name string
}

// UserOrganizationMembershipInvite represents an invitation to an organization.
type UserOrganizationMembershipInvite struct {
	Organization *Organization
	Inviter      *User
	InviteeEmail string
}
