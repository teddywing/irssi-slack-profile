irssi-slack-profile
===================

An Irssi plugin that provides WHOIS-style profile information about Slack
users and allows you to update your own Slack profile.


## Configuration
In order to use this script, a Slack API token _must_ be configured to request
user profile information. A token can be obtained from
https://api.slack.com/docs/oauth-test-tokens. Add it with:

	/set slack_profile_token TOKEN


## Usage
To query a user's profile, run the `/swhois` command with their nick:

	/swhois nick
	/swhois @nick

The resulting output will appear as:

	00:00 -!- Irssi: nibbler
	00:00 -!- Irssi:   name  : Lord Nibbler
	00:00 -!- Irssi:   email : nibbler@example.com
	00:00 -!- Irssi:   phone : 2125553455
	00:00 -!- Irssi:   tz    : Eastern Daylight Time
	00:00 -!- Irssi: End of SWHOIS

You can update your own profile as well:

	/slack_profile_set last_name Farnsworth

If the cached profile information gets out of date, it can be refreshed:

	/slack_profile_sync


## License
Copyright © 2016 Teddy Wing. Licensed under the GNU GPLv3+ (see the included
COPYING file).
