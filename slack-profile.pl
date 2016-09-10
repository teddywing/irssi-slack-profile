use strict;

use JSON;
use LWP::UserAgent;
use HTTP::Request::Common;
use Mozilla::CA;

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


open(my $fh, '<', 'users.list.json');
{
	local $/;
	my $json_text = <$fh>;
	my $users_list = decode_json($json_text);
}
close $fh;
