#!/usr/bin/perl

require "general.pl";
require "db.pl";

my $billSummaryFile;

if ($ARGV[0] eq "MAKE_INDEX" || $ARGV[0] eq "INDEX_BILLS") { IndexBills(); }
if ($ARGV[0] eq "MAKE_INDEX" || $ARGV[0] eq "INDEX_VOTES") { IndexVotes(); }


1;

sub IndexBills {
	my $session = $ARGV[1];
	if ($session eq "") { die "Give a session!"; }

	GovDBOpen();

	#my $w = "session = $session";
	#DBDelete(billstatus, [$w]);
	#DBDelete(billindex, [$w]);

	my @bills = GetBillList($session);
	foreach my $b (@bills) {
		eval {
			IndexBill(@{ $b });
		};
		if ($@) { print "$$b[0]$$b[1]$$b[2]: $@\n"; }
	}
	DBClose();
}

sub IndexBill {
	my ($session, $type, $number) = @_;

	my $w = "session = $session and type = '$type' and number = $number";
	DBDelete(billstatus, [$w]);
	DBDelete(billindex, [$w]);
	DBDelete(billevents, [$w]);
	DBDelete(billtitles, [$w]);

	# Index the Main Bill XML File

	my $bill = $XMLPARSER->parse_file("../data/us/$session/bills/$type$number.xml")->documentElement;

	my $officialtitle_as = $bill->findvalue('titles/title[@type="official"][position()=last()]/@as');
	my $officialtitle = $bill->findvalue("titles/title[\@type='official' and \@as='$officialtitle_as'][position()=1]");

	my ($status) = $bill->findnodes('status/*');
	$status->setAttribute('sponsor', $bill->findvalue('sponsor/@id')) if ($bill->findvalue('sponsor/@id') ne '');

	foreach my $title ($bill->findnodes('titles/title[@type="popular"]')) {
		DBInsert(DELAYED, billtitles,
			session => $session,
			type => $type,
			number => $number,
			titletype => 'popular',
			title => $title->textContent);
	}
	foreach my $title ($bill->findnodes('titles/title[not(@type="popular") and @as="' . $officialtitle_as . '"]')) {
		DBInsert(DELAYED, billtitles,
			session => $session,
			type => $type,
			number => $number,
			titletype => $title->getAttribute('type'),
			title => $title->textContent);
	}

	if ($status->getAttribute('roll') ne "") {
		my $rid = $status->getAttribute('where') . YearFromDateTime($status->getAttribute('datetime')) . "-" . $status->getAttribute('roll');

		my $roll = $XMLPARSER->parse_file("../data/us/$session/rolls/$rid.xml")->documentElement;
		$info = $roll->getAttribute("aye") . "-" . $roll->getAttribute("nay");
		if ($roll->getAttribute("nv") + $roll->getAttribute("present") > 0) {
			$info .= ", " . ($roll->getAttribute("nv") + $roll->getAttribute("present")) . " not voting";
		}

		open INFO, "<../data/us/$session/gen.rolls-pca/$rid.txt";
		$info .= " with " . join("", <INFO>);
		close INFO;

		$status->setAttribute("roll-info", $info);
	}

	my $title = GetBillDisplayTitle($bill, 0, 1);
	my $statusdate = $status->getAttribute('datetime');

	my $lastactiondate = $bill->findvalue('actions/*[position()=last()]/@datetime');

	DBInsert(DELAYED, billstatus,
			session => $session,
			type => $type,
			number => $number,
			title => $title,
			fulltitle => $officialtitle,
			statusdate => DateTimeToDBString($statusdate),
			statusxml => $status->toString
		);

	IndexBill2($session, $type, $number, $bill, "subjects/term/\@name", "crs");
	IndexBill2($session, $type, $number, $bill, "committees/committee", "committee", sub { $_[0]->getAttribute('subcommittee') eq "" ? $_[0]->getAttribute('name') : $_[0]->getAttribute('name') . ' -- ' . $_[0]->getAttribute('subcommittee') });
	IndexBill2($session, $type, $number, $bill, 'sponsor/@id', "sponsor");
	IndexBill2($session, $type, $number, $bill, 'cosponsors/cosponsor/@id', "cosponsor");

	# Add any miscelleneous events

	foreach my $rt ('cbo', 'ombsap') {
		my $rf = "../data/us/$session/bills.$rt/$type$number.xml";
		if (!-e $rf) { next; }
		my $r = $XMLPARSER->parse_file($rf);
		my $date = $r->findvalue('report/@date');

		DBInsert(DELAYED, billevents,
				session => $session,
				type => $type,
				number => $number,
				date => DateToDBTimestamp($date),
				eventxml => $r->documentElement->toString);
	}

	# Update the bill summary XML file.

	my $bsfn = "../data/us/$session/bills.index.xml";
	if (!$billSummaryFile) {
		if (-e $bsfn) {
			$billSummaryFile = $XMLPARSER->parse_file($bsfn);
		} else {
			$billSummaryFile = $XMLPARSER->parse_string("<bills session=\"$session\"/>");
		}
	}
	my ($node) = $billSummaryFile->findnodes("bills/bill[\@type='$type' and \@number='$number']");
	if (!$node) {
		$node = $billSummaryFile->createElement("bill");
		$billSummaryFile->documentElement->appendChild($node);
		$node->setAttribute('type', $type);
		$node->setAttribute('number', $number);
	}
	$node->setAttribute('title', $title);
	$node->setAttribute('official-title', $officialtitle);
	$node->setAttribute('last-action', $lastactiondate);
	$node->setAttribute('status', $status->nodeName);
	$billSummaryFile->toFile($bsfn, 1);
}

sub IndexBill2 {
	my ($session, $type, $number, $bill, $search, $indexname, $func) = @_;
	foreach my $node ($bill->findnodes($search)) {
		DBInsert(DELAYED, billindex,
				session => $session,
				type => $type,
				number => $number,
				idx => $indexname,
				value => (!$func ? $node->nodeValue : &$func($node))
			);
	}
}

sub IndexVotes {
	my $session = $ARGV[1];
	my $update = $ARGV[2];
	my $maintableonly = $ARGV[3];
	if ($session eq "") { die "Give a session!"; }

	GovDBOpen();

	my @votes = ScanDir("../data/us/$session/rolls");
	foreach my $vote (@votes) {
		my $id;
		($id = $vote) =~ s/\.xml$//;
		IndexVote($session, $id, $update, $maintableonly);
	}

	DBClose();
}

sub IndexVote {
	my $session = shift;
	my $id = shift;
	my $update = shift;
	my $maintableonly = shift;

	my $xml = $XMLPARSER->parse_file("../data/us/$session/rolls/$id.xml")->documentElement;

	my $result = $xml->findvalue('result') . " ";
	if ($xml->findvalue('@aye') + $xml->findvalue('@nay') > 0) {
		$result .= $xml->findvalue('@aye') . '-' . $xml->findvalue('@nay');
		if ($xml->findvalue('@nv') + $xml->findvalue('@present') > 0) {
			$result .= ', ' . ($xml->findvalue('@nv') + $xml->findvalue('@present')) . ' not voting';
		}
	} else {
		$result .= $xml->findvalue('@present') . ' present, '
			. $xml->findvalue('@nv') . ' absent';
	}
	
	my %values = (
		id => $id,
		date => DateTimeToDBString($xml->findvalue('@datetime')),
		description => $xml->findvalue('question'),
		result => $result);

	if ($xml->findvalue('bill/@session')) {
		$values{'billsession'} = $xml->findvalue('bill/@session');
		$values{'billtype'} = $xml->findvalue('bill/@type');
		$values{'billnumber'} = $xml->findvalue('bill/@number');
	}
	if ($xml->findvalue('amendment/@number')) {
		if ($xml->findvalue('amendment/@ref') eq 'bill-serial') {
			$values{'amdtype'} = 'N';
			$values{'amdnumber'} = $xml->findvalue('amendment/@number');
		} else {
			$xml->findvalue('amendment/@number') =~ /(hs)(\d+)/;
			$values{'amdtype'} = $1;
			$values{'amdnumber'} = $2;
		}
	}

	if (!$update) {
		DBDelete(votes, [DBSpecEQ(id, $id)]);
		DBInsert(DELAYED, votes, %values);
	} else {
		DBUpdate(votes, [DBSpecEQ(id, $id)], %values);
	}

	if ($maintableonly) { return; }

	DBDelete(people_votes, [DBSpecEQ(voteid, $id)]);

	foreach my $n ($xml->findnodes('voter')) {
		if ($n->getAttribute('id') == 0) { next; }
		DBInsert(DELAYED, people_votes, 
			personid => $n->getAttribute('id'),
			voteid => $id,
			vote => $n->getAttribute('vote')
			);
	}
}
