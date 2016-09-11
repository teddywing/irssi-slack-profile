use strict;

use 5.010;

use Data::Dumper;

use JSON;
use LWP::UserAgent;
use HTTP::Request::Common;
use Mozilla::CA;
use Storable;

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

sub users_list {
	my $ua = LWP::UserAgent->new;
	$ua->agent('Mozilla/5.0');

	my $req = HTTP::Request->new(GET => 'http://ip.jsontest.com/');

	$req->header('content-type' => 'application/json');

	my $resp = $ua->request($req);

	if ($resp->is_success) {
		my $message = $resp->decoded_content;
		print $message;
	}
	else {
		print $resp->code . "\n";
		print $resp->message . "\n";
	}
}

sub find_user {
	my ($username) = @_;

	if (!@users_list) {
		my $file = 'users.list.plstore';
		@users_list = retrieve($file);
	}

	for my $user (@{@users_list[0]}) {
		if ($user->{'name'} eq $username) {
			return $user;
			last;
		}
	}
}

sub swhois {
	my ($data, $server, $window_item) = @_;

	# if (!$server || !$server->{connected}) {
	# 	Irssi::print("Not connected to server");
	# 	return;
	# }

	if ($data) {
		# If $data starts with @, strip it
		$data =~ s/^@//;

		if (my $user = find_user($data)) {
			my $bot = '';

			if ($user->{'is_bot'}) {
				$bot = ' (bot)';
			}

			Irssi::print($user->{'name'} . $bot);
			Irssi::print('  name  : ' . $user->{'real_name'});
			Irssi::print('  title : ' . $user->{'profile'}->{'title'});
			Irssi::print('  email : ' . $user->{'profile'}->{'email'});

			if ($user->{'profile'}->{'phone'}) {
				Irssi::print('  phone : ' . $user->{'profile'}->{'phone'});
			}

			if ($user->{'profile'}->{'skype'}) {
				Irssi::print('  skype : ' . $user->{'profile'}->{'skype'});
			}

			Irssi::print('End of SWHOIS');
		}
	}
	else {
		# find_user(current user nick);
	}
}

Irssi::command_bind('swhois', 'swhois');
