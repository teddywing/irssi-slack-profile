# slack_profile.pl
#
# Get user profile information from the Slack API.
#
# Note:
# Before using this script, a Slack API token must be added:
#
#     /set slack_profile_token TOKEN
#
# Tokens can be created here: https://api.slack.com/docs/oauth-test-tokens
#
# Usage:
#
#   Get profile information for a given nick:
#
#     /swhois nick
#     /swhois @nick
#
#   Get the latest user profile data from Slack:
#
#     /slack_profile_sync
#
#   Update your Slack profile fields:
#
#     /slack_profile_set last_name Farnsworth
#
# 
# Copyright (c) 2016  Teddy Wing
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.

use strict;

use 5.010;

use JSON;
use HTTP::Tiny;
use Mozilla::CA;
use Storable;
use URI;

use vars qw($VERSION %IRSSI);
use Irssi;

$VERSION = '1.00';
%IRSSI = {
	authors     => 'Teddy Wing',
	contact     => 'irssi@teddywing.com',
	name        => 'Slack Profile',
	description => 'Update and retrieve user profile information from Slack.',
	license     => 'GPL',
};

# Keeps an in-memory collection of Slack team members and their profile info
my @users_list;

# Provides help for the commands provided by the script from within Irssi.
#
# Examples:
#   /help swhois
#   /help slack_profile_sync
#   /help slack_profile_set
sub help {
	my ($args) = @_;

	my $is_helping = 0;
	my $help = '';

	if ($args =~ /^swhois\s*$/) {
		$is_helping = 1;

		$help = <<HELP;
%9Syntax:%9

SWHOIS [<nick>]

%9Description:%9

    Displays WHOIS-style profile information from Slack for the given nick. If
    no nick argument is provided, the current nick is used.

%9Examples:%9

    /SWHOIS
    /SWHOIS farnsworth
    /SWHOIS \@farnsworth
HELP
	}
	elsif ($args =~ /^slack_profile_sync\s*$/) {
		$is_helping = 1;

		$help = <<HELP;
%9Syntax:%9

SLACK_PROFILE_SYNC

%9Description:%9

    Re-fetches the users list from Slack and updates the script's internal
    cache with this copy. %9Note: this will block Irssi and take a while.%9

%9Examples:%9

    /SLACK_PROFILE_SYNC
HELP
	}
	elsif ($args =~ /^slack_profile_set\s*$/) {
		$is_helping = 1;

		$help = <<HELP;
%9Syntax:%9

SLACK_PROFILE_SET <key> <value>

%9Description:%9

    Update the given Slack profile field for the current nick.

%9Examples:%9

    /SLACK_PROFILE_SET first_name Lisa
HELP
	}

	if ($is_helping) {
		Irssi::print($help, MSGLEVEL_CLIENTCRAP);
		Irssi::signal_stop();
	}
}

# The location of the on-disk cache where user profile data is stored
sub users_list_cache {
	Irssi::get_irssi_dir() . '/scripts/slack_profile-users.list.plstore';
}

# Call Slack API methods
#
# Requires a Slack API token to be added to the Irssi config. Take a Slack API
# method and an optional hash of API arguments. If the request is successful,
# the API response is returned.
sub slack_api {
	my $token = Irssi::settings_get_str('slack_profile_token');
	die 'Requires a Slack API token. Generate one from ' .
		'https://api.slack.com/docs/oauth-test-tokens. ' .
		'Set it with `/set slack_profile_token TOKEN`.' if !$token;

	my ($method, $args) = @_;
	$args ||= {};
	$args->{'token'} = $token;

	my $url = URI->new("https://slack.com/api/$method");
	$url->query_form($args);

	my $http = HTTP::Tiny->new(
		default_headers => {
			'content-type' => 'application/json',
		},
		verify_SSL => 1,
	);
	my $resp = $http->get($url);

	if ($resp->{'success'}) {
		my $payload = decode_json($resp->{'content'});

		if ($payload->{'ok'}) {
			return $payload;
		}
		else {
			Irssi::print("Error from the Slack API: $payload->{'error'}");
		}
	}
	else {
		Irssi::print("Error calling the Slack API: ($resp->{'status'}) $resp->{'reason'} | $resp->{'content'}");
	}
}

# Requests the entire list of users on the Slack team
#
# Stores this list in memory in `@users_list` and in an on-disk cache file.
sub fetch_users_list {
	Irssi::print('Fetching users list from Slack. This could take a while...');

	my $resp = slack_api('users.list') or
		die 'Unable to retrieve users from the Slack API';

	@users_list = @{$resp->{'members'}};
	store \@users_list, users_list_cache;
}

# Re-fetch the users list for the most up-to-date information
sub sync {
	fetch_users_list();
	Irssi::print('Done.');
}

# Get profile data for a single user
#
# Takes a user object of the kind provided by the Slack 'users.list' API
# method. The user's unique id is extracted from this object and sent to Slack's
# profile API method in order to retrieve custom field values from the user.
sub fetch_user_profile {
	my ($user) = @_;

	my $resp = slack_api('users.profile.get', {
		user => $user->{'id'},
		include_labels => 1
	});

	return $resp->{'profile'};
}

# Get presence information about a user
#
# Given a user, request Slack's presence API method to find out whether that
# user is away or active/online.
sub fetch_user_presence {
	my ($user) = @_;

	my $resp = slack_api('users.getPresence', {
		user => $user->{'id'}
	});

	return $resp->{'presence'};
}

# Convert a given string to a key-friendly format
#
# Takes a string, lowercases it, removes non-alphabetic characters, and converts
# spaces into underscores.
#
# Examples:
#   is(
#       underscorize("This isn't a key"),
#       'this_isnt_a_key'
#   )
sub underscorize {
	my ($string) = @_;

	my $result = lc $string;
	$result =~ s/ /_/g;
	$result =~ s/[^a-z_]//g;

	return $result;
}

# Completion for profile fields names
#
# When using the `slack_profile_set` command, allow the names of profile fields
# to be tab completed. This allows users to browse the possible fields they can
# update, frees them from having to type the full field name, and gives them
# confidence that they're not misspelling a field name.
sub complete_profile_field {
	my ($complist, $window, $word, $linestart, $want_space) = @_;
	my $slash = Irssi::parse_special('$k');

	return unless $linestart =~ /^\Q${slash}\Eslack_profile_set\b/i;

	my @profile_fields = qw(first_name last_name email phone skype title);

	if ($window->{'active_server'}) {
		my $user = find_user($window->{'active_server'}->{'nick'});

		for my $custom_field (keys %{$user->{'fields'}}) {
			push @profile_fields, underscorize($user->{'fields'}->{$custom_field}->{'label'});
		}
	}

	if ($word ne '') {
		for my $field (@profile_fields) {
			if ($field =~ /^\Q${word}\E/i) {
				push @$complist, $field;
			}
		}
	}
	else {
		@$complist = @profile_fields;
	}

	Irssi::signal_stop();
}

# Update a profile field
#
# Given a string nick, a field name, and a value, set the profile field to the
# given value for the specified user.
sub update_user_profile {
	my ($nick, $key, $value) = @_;

	my $user = find_user($nick);

	my @profile_fields = qw(first_name last_name email phone skype title);

	# If $key is a custom field, find the custom field's id and use
	# that as the key instead.
	unless (grep { $_ eq $key } @profile_fields) {
		# Find key in custom field labels
		for my $custom_field (keys %{$user->{'fields'}}) {
			if (underscorize($user->{'fields'}->{$custom_field}->{'label'})
				eq $key) {
				$key = $custom_field;
				last;
			}
		}
	}

	my $resp = slack_api('users.profile.set', {
		user => $user->{'id'},
		name => $key,
		value => $value,
	});
}

# Irssi command handler for updating profile fields
#
# Extracts the field name and value from Irssi command arguments, finds the
# current user's nick, and offloads the actual work onto `update_user_profile`.
sub cmd_set {
	my ($data, $server) = @_;
	my ($key, $value) = split /\s+/, $data, 2;
	my $nick = $server->{'nick'};

	if ($key) {
		update_user_profile($nick, $key, $value);
	}
}

# Given a nick, return a corresponding user object
#
# Looks for the given nick in the Slack users list. If a match is found, the
# associated user object is returned. Additionally, custom profile fields and
# presence information is requested and attached to the user object if not
# already there.
sub find_user {
	my ($username) = @_;

	if (!@users_list) {
		if (!-s users_list_cache) {
			fetch_users_list();
		}
		else {
			@users_list = retrieve(users_list_cache);
			@users_list = @{@users_list[0]};
		}
	}

	for my $user (@users_list) {
		if ($user->{'name'} eq $username) {
			unless (exists $user->{'fields'}) {
				my $profile = fetch_user_profile($user);
				$user->{'fields'} = $profile->{'fields'};
			}

			unless (exists $user->{'presence'}) {
				my $presence = fetch_user_presence($user);
				$user->{'presence'} = $presence;
			}

			return $user;
		}
	}
}

# Prints user profile information to the Irssi console
sub print_whois {
	my ($user) = @_;

	# Append spaces to the end of $label such that the length of the result is
	# equal to $length
	#
	# Examples:
	#   is(
	#       pad_label('name', 7),
	#       'name   '
	#   )
	sub pad_label {
		my ($label, $length) = @_;

		my $padding = $length - length $label;

		$label . ' ' x $padding;
	}

	my $bot = '';

	if ($user->{'is_bot'}) {
		$bot = ' (bot)';
	}

	my @fields = (
		{
			label => 'name',
			value => $user->{'real_name'},
		},
		{
			label => 'title',
			value => $user->{'profile'}->{'title'},
		},
		{
			label => 'email',
			value => $user->{'profile'}->{'email'},
		},
		{
			label => 'phone',
			value => $user->{'profile'}->{'phone'},
		},
		{
			label => 'skype',
			value => $user->{'profile'}->{'skype'},
		},
		{
			label => 'tz',
			value => $user->{'tz_label'},
		},
	);

	foreach my $key (keys %{$user->{'fields'}}) {
		push @fields, {
			label => $user->{'fields'}->{$key}->{'label'},
			value => $user->{'fields'}->{$key}->{'value'},
		};
	}

	push @fields, {
		label => 'status',
		value => $user->{'presence'},
	};

	# Determine the longest label so we can pad others accordingly
	my $max_label_length = 0;
	for my $field (@fields) {
		my $length = length $field->{'label'};
		if ($length > $max_label_length) {
			$max_label_length = $length;
		}
	}

	Irssi::print($user->{'name'} . $bot);

	for my $field (@fields) {
		if ($field->{'value'}) {
			# Pad field labels so that the colons line up vertically
			my $label = pad_label($field->{'label'}, $max_label_length);

			Irssi::print("  $label : $field->{'value'}");
		}
	}

	Irssi::print('End of SWHOIS');
}

# Irssi command handler for getting profile information for a nick
#
# Given a nick, the associated profile information for that nick will be fetched
# and printed to the Irssi console. If no nick is passed, profile information
# for the current user's nick is printed.
sub swhois {
	my ($username, $server, $window_item) = @_;

	if (!$username) {
		if (!$server || !$server->{connected}) {
			Irssi::print("Not connected to server");
			return;
		}

		$username = $server->{'nick'};
	}

	# If $username starts with @, strip it
	$username =~ s/^@//;

	# Trim leading and trailing whitespace
	$username =~ s/^\s+//;
	$username =~ s/\s+$//;

	if (my $user = find_user($username)) {
		print_whois($user);
	}
}

Irssi::command_bind('swhois', 'swhois');

Irssi::command_bind('slack_profile_sync', 'sync');
Irssi::command_bind('slack_profile_set', 'cmd_set');

Irssi::command_bind('help', 'help');

Irssi::signal_add('complete word', 'complete_profile_field');


Irssi::settings_add_str('slack_profile', 'slack_profile_token', '');
