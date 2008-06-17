#!/usr/bin/perl

# This script scrapes the approval ratings for senators from SurveyUSA.
# Note that GovTrack acquired permission to scrape and display the
# information from SurveyUSA. Please don't use this script without
# requesting permission from them.

use LWP::UserAgent;

require "util.pl";
require "persondb.pl";
require "db.pl";

$doc = $XMLPARSER->parse_string("<approval-ratings/>");

$doc->documentElement->setAttribute('retrieved', Now());

GovDBOpen();

my $ctr = 0;
my $mean = 0;

my $URL = 'http://www.surveyusa.com/50StateTracking.html';

my $response = $UA->get($URL);
if (!$response->is_success) {
	die "Could not fetch SurveyURL page $URL: " .
         $response->code . " " .
         $response->message; }
$HTTP_BYTES_FETCHED += length($response->content);
$content = $response->content;

while ($content =~ /(\d\d)(\d\d)(\d\d)[ \n\r]+-\&nbsp;<a href="http:..www.surveyusa.com.client.PollReport.aspx\?g=([a-z0-9\-]+)">([^<]+?)[ \n\r]+Senate Approval Rating/g) {
	my ($month, $date, $year, $gid, $state) = ($1, $2, $3, $4, $5);
	
	$state =~ s/\s+ / /g;
	
	if ($didstate{$state}) { next; }
	$didstate{$state} = 1;
	
	if (!defined($StatePrefix{uc($state)})) {
		warn "Invalid state: $state";
		next;
	}
	$state = $StatePrefix{uc($state)};
	
	my $surveydate = "20$year-$month-$date";

	$url = "http://www.surveyusa.com/client/PollReport_main.aspx?g=$gid";
	$response2 = $UA->get($url);
	if (!$response2->is_success) {
		die "Could not fetch SurveyURL page $url: " .
	         $response2->code . " " .
	         $response2->message; }
	$HTTP_BYTES_FETCHED += length($response2->content);
	$content2 = $response2->content;
	
	my $ctrstart = $ctr;
	
	my $name;
	for my $line (split(/[\n\r]/, $content2)) {
		if ($line =~ /Do you approve or disapprove of the job (.*) is doing/) {
			$name = $1;
		}
		if ($line =~ />Approve<\/td><td class="qtableCenterTQ">(\d+)\%/) {
			$val = $1;
			if (!defined($name)) {
				warn "Failed to find name before rating on $url";
				next;
			}

			$ctr++;

			my $id = PersonDBGetID(name => $name, state => $state, type => 'sen', nameformat => 'firstlast');
			if ($id == 0) {
				warn "Could not get ID of '$name' in $state";
				next;
			}
			
			print "$id $name $val $state\n";
			
			my $node = $doc->createElement('person');
			$doc->documentElement->appendChild($node);

			$node->setAttribute('id', $id);
			$node->setAttribute('name', $name);
			$node->setAttribute('approval', $val);
			$node->setAttribute('link-survey', "http://www.surveyusa.com/client/PollReport.aspx?g=$gid");
			#$node->setAttribute('link-tracking', '');
			$node->setAttribute('date', $surveydate);
	
			$mean += $val;
		}
	}
	
	if ($ctr != $ctrstart+2) {
		warn "From $state, only got " . ($ctr-$ctrstart) . " values";
	}
}

if ($ctr != 100) { warn "Only got $ctr records of SurveyUSA data."; }

$mean /= $ctr;
$doc->documentElement->setAttribute('mean-approval', $mean);

$doc->toFile('../../extdata/misc/surveyusa.xml', 2);

DBClose();
