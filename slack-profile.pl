use strict;

use 5.010;

use Data::Dumper;

use JSON;
use LWP::UserAgent;
use HTTP::Request::Common;
use Mozilla::CA;
use POSIX;

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


sub binary_search {
	my ($array, $match_func) = @_;
	my $left = 0;
	my $right = scalar @{$array} - 1;

	while ($left <= $right) {
		my $middle = floor(($left + $right) / 2);

		my $equality = $match_func->($array->[$middle]);

		if ($equality == 0) {
			return $array->[$middle];
		}
		elsif ($equality == -1) {
			$left = $middle + 1;
		}
		elsif ($equality == 1) {
			$right = $middle - 1;
		}
	}

	return -1;
}

open(my $fh, '<', 'users.list.json');
{
	local $/;
	my $json_text = <$fh>;
	my $users_list = decode_json($json_text);
	my @members = @{$users_list->{'members'}};

	my $username = 'teddy';
	my $user = binary_search($users_list->{'members'}, (sub {
		my ($user) = @_;

		# say Dumper($user);
		say $user->{'name'};
		if ($username eq $user->{'name'}) { return 0; }
		elsif ($username gt $user->{'name'}) { return -1; }
		else { return 1; }
	}));

	say Dumper($user);
	say $user->{'name'};


	# for my $user (@members) {
	# 	if ($user->{'name'} eq 'slackbot') {
	# 		say Dumper($user);
	# 		last;
	# 	}
	# }
}
close $fh;
