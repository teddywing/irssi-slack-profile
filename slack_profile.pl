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
#     /swhois nick
#     /swhois @nick
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

my @users_list;

sub help {
	my ($args) = @_;
	return unless $args =~ /^swhois\s*$/;

	my $help = <<HELP;
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

	Irssi::print($help, MSGLEVEL_CLIENTCRAP);
	Irssi::signal_stop();
}

sub users_list_cache {
	Irssi::get_irssi_dir() . '/scripts/slack_profile-users.list.plstore';
}

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

sub fetch_user_profile {
	my ($user) = @_;

	my $resp = slack_api('users.profile.get', {
		user => $user->{'id'},
		include_labels => 1
	});

	return $resp->{'profile'};
}

sub fetch_user_presence {
	my ($user) = @_;

	my $resp = slack_api('users.getPresence', {
		user => $user->{'id'}
	});

	return $resp->{'presence'};
}

sub underscorize {
	my ($string) = @_;

	my $result = lc $string;
	$result =~ s/ /_/g;
	$result =~ s/[^a-z_]//g;

	return $result;
}

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

sub update_user_profile {
	my ($nick, $key, $value) = @_;

	my $user = find_user($nick);

	my @profile_fields = qw(first_name last_name email phone skype title);

	# If $key is a custom field, find the custom field's id and use
	# that as the key instead.
	unless ($key ~~ @profile_fields) {
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

sub cmd_set {
	my ($data, $server) = @_;
	my ($key, $value) = split /\s+/, $data, 2;
	my $nick = $server->{'nick'};

	if ($key) {
		update_user_profile($nick, $key, $value);
	}
}

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

sub print_whois {
	my ($user) = @_;

	sub maybe_print_field {
		my ($name, $value) = @_;

		if ($value) {
			Irssi::print("  $name : $value");
		}
	}

	my $bot = '';

	if ($user->{'is_bot'}) {
		$bot = ' (bot)';
	}

	Irssi::print($user->{'name'} . $bot);
	maybe_print_field('name ', $user->{'real_name'});
	maybe_print_field('title', $user->{'profile'}->{'title'});
	maybe_print_field('email', $user->{'profile'}->{'email'});
	maybe_print_field('phone', $user->{'profile'}->{'phone'});
	maybe_print_field('skype', $user->{'profile'}->{'skype'});
	maybe_print_field('tz   ', $user->{'tz_label'});

	foreach my $key (keys %{$user->{'fields'}}) {
		my $label = $user->{'fields'}->{$key}->{'label'};
		my $value = $user->{'fields'}->{$key}->{'value'};

		maybe_print_field($label, $value);
	}

	maybe_print_field('status', $user->{'presence'});

	Irssi::print('End of SWHOIS');
}

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
