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


# open(my $fh, '<', 'users.list.json');
# {
# 	local $/;
# 	my $json_text = <$fh>;
# 	my $users_list = decode_json($json_text);
# 	my @members = @{$users_list->{'members'}};
# 	store \@members, 'users.list.plstore';
#

my @members = retrieve('users.list.plstore');

# say @members[0]->[0]{'name'};
# say Dumper(@members[0]);
	for my $user (@{@members[0]}) {
		if ($user->{'name'} eq 'slackbot') {
			# say Dumper($user);
			last;
		}
	}
# }
# close $fh;
