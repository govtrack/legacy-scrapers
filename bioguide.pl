#!/usr/bin/perl

# This script gets an index of all people in bioguide.congress.gov,
# putting a table of people in bioguide1.csv and a table of
# roles in bioguide2.csv.  Then, for each person, the biography
# page of that person is fetched and put into bioguide3.csv.

use HTML::Entities;
use LWP::UserAgent;
use Text::CSV_XS;
use Encode;

$UA = LWP::UserAgent->new(keep_alive => 2, timeout => 30, agent => "GovTrack.us", from => "errors@govtrack.us");

$csv = Text::CSV_XS->new({ binary => 1 });

open B1, ">../data/us/bioguide1.csv";
open B2, ">../data/us/bioguide2.csv";

print B1 "#ID,NAME,BIRTHYEAR,DEATHYEAR\n";
print B2 "#ID,ROLE,PARTY,STATE,CONGRESS\n";

for my $C ('A' .. 'Z') {
	if ($ARGV[0] ne '') { last; }
	sleep(1);
	print "Getting index: $C\n";
    my $response = $UA->post(
    	"http://bioguide.congress.gov/biosearch/biosearch1.asp",
    	{ lastname => $C } );
	if (!$response->is_success) { die $response->message; }

	my $name;
	my $id;
	for my $line (split(/[\n\r]+/, $response->content)) {
		if ($line =~ /bioguide.congress.gov\/scripts\/biodisplay.pl/) {
			if ($line !~ /bioguide.congress.gov\/scripts\/biodisplay.pl\?index=(\w+)">([^<]+)<\/A><\/td><td>(c? ?[\d\/\?]+c?|\&nbsp;|unknown)-(c? ?[\d\/\?]+c?|\&nbsp;|)\s*<\/td>$/) {
				die $line;
			}
			my $birth;
			my $death;
			($name, $id, $birth, $death) = ($2, $1, $3, $4);
			if ($birth eq '&nbsp;' || $birth eq "unknown") { $birth = ''; }
			if ($death eq '&nbsp;' || $death eq "unknown") { $death = ''; }
			foreach my $bd ($birth, $death) {
				$bd =~ s/\/.*//;
				$bd =~ s/c| |\?//g;
			}
			decode_entities($name);
			$csv->combine($id, decode("iso-8859-1", $name), $birth, $death) or die $csv->error_input();
			if (!$seen{$id}) {
				print B1 $csv->string() . "\n";
				push @IDs, $id;
				$seen{$id} = 1;
			} else {
				print "(Duplicate listing of $id $name.)\n";
			}
		}
		elsif (defined($name) && $line =~ /<td>([^<]+)<\/td><td>([^<]+|&nbsp;)<\/td><td align="center">(\w\w)<\/td><td align="center">(\d+)(<\/td><\/tr>|<br>)/) {
			my ($role, $party, $state, $congress) = ($1, $2, $3, $4);
			if ($party eq "&nbsp;") { $party = ""; }
			decode_entities($party);
			if ($party =~ /,/) { warn $party; }
			$csv->combine($id, $role, $party, $state, $congress) or die $csv->error_input();
			print B2 $csv->string() . "\n";
		}
		elsif ($line =~ /<tr><td>/) {
			die $line;
		}
	}
}

close B1;
close B2;

open B3, ">../data/us/bioguide3.csv";
print B3 "#ID,BIOGRAPHY\n";

if ($ARGV[0] ne '') { push @IDs, $ARGV[0]; }

foreach my $id (@IDs) {
	sleep(1);
	print "Getting bio: $id\n";

    my $url = "http://bioguide.congress.gov/scripts/biodisplay.pl?index=$id";
    my $response = $UA->get($url);
	if (!$response->is_success) { die $response->message; }

	if ($response->content !~ /<P><FONT SIZE=4 COLOR="#800040">([\w\W]*?)<\/(P|TD)>/) {
		die "Couldn't find bio in $url";
	}

	my $bio = $1;
	$bio =~ s/<\/FONT>//;
	$bio =~ s/<\/?i>//;
	$bio =~ s/<\/?dh>//;
	$bio =~ s/\n//g;

	decode_entities($bio);

	while ($bio =~ /<(.*?)>/g) {
		print "Found tag: $1 in $id.\n";
	}
	$bio =~ s/<(.*?)>//g; # remove any stray tags

	$csv->combine($id, decode("iso-8859-1", $bio)) or die $csv->error_input();
	print B3 $csv->string() . "\n";
}

close B3;
