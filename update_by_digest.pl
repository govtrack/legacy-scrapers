#!/usr/bin/perl

use XML::LibXML;
use Time::Local;

require "general.pl";
require "parse_status.pl";

if ($ARGV[0] eq 'UPDATE') {
	require "db.pl";
	GovDBOpen();
	GetModifiedBills();
	DBClose();
}

1;

sub GetDigestURL {
	my $date = shift;
	my ($year, $month, $day) = ParseDateTimeValue($date);
	my $session = SessionFromYear($year);
	$datestr = sprintf("%04d%02d%02d", $year, $month, $day);
	return "http://thomas.loc.gov/cgi-bin/query/B?r$session:\@FIELD(FLD003+d)+\@FIELD(DDATE+$datestr)";
}

sub GetModifiedBills {
	my ($ifneedsupdate, $getnextsession, $dontFetchAgain) = @_;

	my $url = "http://thomas.loc.gov/cgi-bin/dailydigest";
	if ($ENV{DIGEST_DATE} ne "") {
		$url = GetDigestURL($ENV{DIGEST_DATE});
	}

 	my ($content, $mtime) = Download($url, nocache => 1);
 	if (!$content) { return; }

	if ($content !~ /<h3><em>((Sunday|Monday|Tuesday|Wednesday|Thursday|Friday|Saturday), )?(\w+ \d\d?, \d\d\d\d) *<\/em><\/h3>/) {
		die "Could not find date of digest in $url.";
	}
	my $date = ParseDateTime($3);
	if (!$date) { die "Could not find/parse date of digest in $url."; }

	print "Fetching daily digest for $date\n";

	open RETDATE, "<../data/us/last_update";
	my $lastdate = <RETDATE>; chop $lastdate;
	close RETDATE;
	if ($date eq $lastdate) { print "Already fetched this digest.\n"; return; }

	my $session = SessionFromYear(YearFromDateTime($date));

	$content =~ s/<[^>]+>//g;

	my @bills = undef;

	# Update the next-meeting information
	if ($getnextsession) {
		#open T, ">/tmp/d"; print T $content; close T;
		if ($content =~ /Next Meeting of the\s+SENATE\s+[\w\d\s,:\.]+?, (January|February|March|April|May|June|July|August|September|October|November|December) (\d+)(, (\d\d\d\d))?/i) {
			my $nextsenate = timelocal(0,0,0,$2,$Months{uc($1)}-1,$4 eq "" ? YearFromDate(time) : $4);
			open T, ">../data/us/$session/congress.nextsession.senate";
			print T $nextsenate . "\n";
			close T;
		}
		if ($content =~ /Next Meeting of the\s+HOUSE OF REPRESENTATIVES\s+[\w\d\s,:\.]+, (January|February|March|April|May|June|July|August|September|October|November|December) (\d+)(, (\d\d\d\d))?/i) {
			my $nexthouse = timelocal(0,0,0,$2,$Months{uc($1)}-1,$4 eq "" ? YearFromDate(time) : $4);
			open T, ">../data/us/$session/congress.nextsession.house";
			print T $nexthouse . "\n";
			close T;
		}
	}

	my %alreadyfetched;

	while ($content =~ /(H\.|H\.R\.|S\.|H\. ?Con\. ?Res\.|S\. ?Con\. ?Res\.|H\. ?J\. ?Res\.|S\. ?J\. ?Res\.|H\. ?Res\.|S\. ?Res\.) (\d+)(\-(\d+))?((,\s+\d+(-\d+)?)*)/g) {
		my ($type, $first, $last, $seq) = ($1, $2, $4, $5);
		$type =~ s/ //g;
		$type = $BillTypeMap{lc($type)};
		if ($type eq "") { next; }

		if ($last eq "") { $last = $first; }
		
		my @numbers = ($first..$last);
		foreach my $rng (split(/,\s+/, $seq)) {
			if ($rng =~ /^\d+$/) { push @numbers, $rng; }
			if ($rng =~ /(\d+)-(\d+)/) { push @numbers, ($1..$2); }
		}
		
		if (scalar(@numbers) > 400) { next; } # just in case

		foreach my $i (@numbers) {
			my $fk = "$session$type$i";
			if (defined($alreadyfetched{$fk})) { next; }
			$alreadyfetched{$fk} = 1;
		
			# Don't update if bill was updated after this date.
			if ($ifneedsupdate) {
				die "ifneedsupdate is no longer implemented";
				#my $bill = GetBill($session, $type, $i);
				#if (defined($bill)) {
				#	my $billdate = $bill->getAttribute("retreived_date");
				#	if ($billdate >= $dateid) { next; }
				#}
			}

			GovGetBill($session, $type, $i, 0);
		}
	}

	if ($dontFetchAgain) {
		open RETDATE, ">../data/us/last_update";
		print RETDATE "$date\n";
		close RETDATE;
	}
}

sub GetMaybeModifiedBills {
	my $rettime = shift;
	my $session = SessionFromDate($rettime);

	my $parser = XML::LibXML->new();
	my $doc = $parser->parse_file("../data/us/$session/bills.index.xml");

	my @update;

	push @update, $doc->findnodes('bills/bill[@refetch]');

	push @update, $doc->findnodes('bills/bill[vote2/@result="pass" or vote2/@result="passed"]');
	push @update, $doc->findnodes('bills/bill[topresident]');
	push @update, $doc->findnodes('bills/bill[signed]');

	print scalar(@update) . " bills to re-fetch.\n";

	foreach my $b (@update) {
		my @stn = ($b->getAttribute('session'), $b->getAttribute('type'), $b->getAttribute('number'));
		GovGetBill(@stn, 0);
	}
}
