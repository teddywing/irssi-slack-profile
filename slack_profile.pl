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

sub fetch_users_list {
	my $token = Irssi::settings_get_str('slack_profile_token');
	die 'Requires a Slack API token. Generate one from ' .
		'https://api.slack.com/docs/oauth-test-tokens. ' .
		'Set it with `/set slack_profile_token TOKEN`.' if !$token;

	Irssi::print('Fetching users list from Slack. This could take a while...');

	my $url = URI->new('https://slack.com/api/users.list');
	$url->query_form(token => $token);

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
			@users_list = @{$payload->{'members'}};
			store \@users_list, users_list_cache;
		}
		else {
			Irssi::print("Error from the Slack API: $payload->{'error'}");
			die 'Unable to retrieve users from the Slack API';
		}
	}
	else {
		Irssi::print("Error calling the Slack API: ($resp->{'status'}) $resp->{'reason'} | $resp->{'content'}");
		die 'Unable to communicate with the Slack API';
	}
}

sub find_user {
	my ($username) = @_;

	if (!@users_list) {
		if (!-s users_list_cache) {
			fetch_users_list();
		}

		@users_list = retrieve(users_list_cache);
	}

	for my $user (@{@users_list[0]}) {
		if ($user->{'name'} eq $username) {
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

	Irssi::print('End of SWHOIS');
}

sub swhois {
	my ($username, $server, $window_item) = @_;

	if ($username) {
		# If $username starts with @, strip it
		$username =~ s/^@//;

		if (my $user = find_user($username)) {
			print_whois($user);
		}
	}
	else {
		if (!$server || !$server->{connected}) {
			Irssi::print("Not connected to server");
			return;
		}

		my $user = find_user($server->{'nick'});
		print_whois($user);
	}
}

Irssi::command_bind('swhois', 'swhois');
Irssi::command_bind('help', 'help');

Irssi::settings_add_str('slack_profile', 'slack_profile_token', '');
