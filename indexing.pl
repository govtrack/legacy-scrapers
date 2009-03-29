#!/usr/bin/perl

require "general.pl";
require "db.pl";

my $billSummaryFile;
my $holdBillSummaryFileWrite;

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
	
	$holdBillSummaryFileWrite = $session;

	my @bills = GetBillList($session);
	foreach my $b (@bills) {
		eval {
			IndexBill(@{ $b });
		};
		if ($@) { print "$$b[0]$$b[1]$$b[2]: $@\n"; }
	}
	DBClose();

	if ($billSummaryFile) {
		my $bsfn = "../data/us/$session/bills.index.xml";
		$billSummaryFile->toFile($bsfn, 1);
	}
}

sub IndexBill {
	my ($session, $type, $number) = @_;
	
	if ($ENV{REMOTE_DB}) { return; }

	my $w = "session = $session and type = '$type' and number = $number";
	DBDelete(billstatus, [$w]);
	DBDelete(billindex, [$w]);
	DBDelete(billevents, [$w]);
	DBDelete(billtitles, [$w]);

	# Index the Main Bill XML File

	my $bill = $XMLPARSER->parse_file("../data/us/$session/bills/$type$number.xml")->documentElement;

	my $officialtitle_as = $bill->findvalue('titles/title[@type="official"][position()=last()]/@as');
	my $officialtitle = $bill->findvalue("titles/title[\@type='official' and \@as='$officialtitle_as'][position()=1]");
	my $shorttitle_as = $bill->findvalue('titles/title[@type="short"][position()=last()]/@as');

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
	foreach my $title ($bill->findnodes('titles/title[@type="official" and @as="' . $officialtitle_as . '"]')) {
		DBInsert(DELAYED, billtitles,
			session => $session,
			type => $type,
			number => $number,
			titletype => $title->getAttribute('type'),
			title => $title->textContent);
	}
	foreach my $title ($bill->findnodes('titles/title[@type="short" and @as="' . $shorttitle_as . '"]')) {
		DBInsert(DELAYED, billtitles,
			session => $session,
			type => $type,
			number => $number,
			titletype => $title->getAttribute('type'),
			title => $title->textContent);
	}

	if ($status->getAttribute('roll') ne "") {
		my $rid = $status->getAttribute('where') . YearFromDateTime($status->getAttribute('datetime')) . "-" . $status->getAttribute('roll');
		if (-e "../data/us/$session/rolls/$rid.xml") {
	
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
	IndexBill2($session, $type, $number, $bill, 'actions/enacted[@type="public"]/@number', "publiclawnumber");

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
	my $bsf;
	if ($holdBillSummaryFileWrite == $session) {
		if (!$billSummaryFile) {
			if (-e $bsfn) {
				$billSummaryFile = $XMLPARSER->parse_file($bsfn);
			} else {
				$billSummaryFile = $XMLPARSER->parse_string("<bills session=\"$session\"/>");
			}
		}
		$bsf = $billSummaryFile;
	} else {
		if (-e $bsfn) {
			$bsf = $XMLPARSER->parse_file($bsfn);
		} else {
			$bsf = $XMLPARSER->parse_string("<bills session=\"$session\"/>");
		}
	}
	my ($node) = $bsf->findnodes("bills/bill[\@type='$type' and \@number='$number']");
	if (!$node) {
		$node = $bsf->createElement("bill");
		$bsf->documentElement->appendChild($node);
		$node->setAttribute('type', $type);
		$node->setAttribute('number', $number);
	}
	$node->setAttribute('title', $title);
	$node->setAttribute('official-title', $officialtitle);
	$node->setAttribute('last-action', $lastactiondate);
	$node->setAttribute('status', $status->nodeName);
	$bsf->toFile($bsfn, 1) if ($holdBillSummaryFileWrite != $session);
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

	if ($ENV{REMOTE_DB}) { return; }

	my $xml = $XMLPARSER->parse_file("../data/us/$session/rolls/$id.xml")->documentElement;

	# Compose a description of the result.
	
	my $result;
	if ($xml->findvalue('count(voter[not(@vote="+" or @vote="-" or @vote="0" or @vote="P")])') == 0) {
		$result = $xml->findvalue('result') . " ";
		if ($xml->findvalue('@aye') + $xml->findvalue('@nay') > 0) {
			$result .= $xml->findvalue('@aye') . '-' . $xml->findvalue('@nay');
			if ($xml->findvalue('@nv') + $xml->findvalue('@present') > 0) {
				$result .= ', ' . ($xml->findvalue('@nv') + $xml->findvalue('@present')) . ' not voting';
			}
			if ($xml->findvalue('required') ne '1/2') {
				$result .= ' (' . $xml->findvalue('required') . ' required)';
			}
		} else {
			$result .= $xml->findvalue('@present') . ' present, '
				. $xml->findvalue('@nv') . ' absent';
		}
	} else {
		for my $n ($xml->findnodes('option')) {
			my $c = $xml->findvalue('count(voter[@vote="' . $n->getAttribute('key') . '"])');
			if ($c == 0){ next; }
			if ($result ne "") { $result .= ', '; }
			$result .= $n->textContent . " " . $c;
		}
	}
	
	# Basic information to put into the record.
	
	my %values = (
		id => $id,
		date => DateTimeToDBString($xml->findvalue('@datetime')),
		result => $result);
	
	# Make a nicer description.
	
	my $chamber;
	if ($id =~ /^h/) { $chamber = 'House'; } else { $chamber = 'Senate'; }
	
	my $description = $xml->findvalue('question');
	
	$description =~ s/^(On Passage|On Passage of the Bill|On the Concurrent Resolution|On the Joint Resolution): (.*)/On Passage - $chamber - $2/;
	$description =~ s/^On Passage of the Bill \((.*?)\s*\)$/On Passage - $chamber - $1/;
	$description =~ s/^(On the Resolution|On Agreeing to the Resolution): (.*)/On Passage - $2/;
	$description =~ s/^(On the Conference Report|On Agreeing to the Conference Report): (.*)/On the Conference Report - $chamber - $2/;
	$description =~ s/^(On the Conference Report|On Agreeing to the Conference Report) \((.*?)\s*\)/On the Conference Report - $chamber - $2/;
	$description =~ s/^(Passage, Objections of the President Notwithstanding|Passage, Objections of the President Not Withstanding): (.*)/Veto Override - $chamber - $2/;
	$description =~ s/^(On Motion to Suspend the Rules and (Pass|Agree)(, as Amended)?): (.*)/On Passage - $chamber - $4 - Under Suspension of the Rules/;
	$description =~ s/^On Overriding the Veto \(.*Shall (the bill )?(.*) Pass, the objections of the President of the United States to the contrary not ?withstanding\?\s*\)/Veto Override - $chamber - $2/i;
	$description =~ s/^On the Amendment \((.*?)\s*\)$/$1/;
	$description =~ s/^On Agreeing to the Amendment: (.*)$/$1/;
	$description =~ s/^On the (Cloture )?Motion \((.*?)\s*\)$/$2/;
	$description =~ s/^On the Nomination \(Confirmation (.*?)\s*\)$/Confirmation of $1/;
	$description =~ s/^Call of the House: QUORUM$/Call of the House - Quorum Call/;
	$description =~ s/^Call in Committee: QUORUM$/Call in Committee - Quorum Call/;
	$description =~ s/^On Motion to Adjourn: ADJOURN$/On Motion to Adjourn/;
	$description =~ s/^On Approving the Journal: JOURNAL$/On Approving the Journal/;
	
	my $bn = $xml->findvalue('bill/@number');
	if ($bn) {
		$description =~ s/H R $bn/H.R. $bn/;
		$description =~ s/H RES $bn/H.Res. $bn/;
		$description =~ s/H CON RES $bn/H.Con.Res. $bn/;
	}
	
	#binmode(STDOUT, ":utf8");
	#print "$id $description\n";
	
	$values{description} = $description;
	
	# Identify related bill and amendment.

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
		my $v = $n->getAttribute('vote');
		if ($v ne "+" && $v ne "-" && $v ne "0" && $v ne "P") { $v = "X"; }
		DBInsert(DELAYED, people_votes, 
			personid => $n->getAttribute('id'),
			voteid => $id,
			vote => $v,
			displayas => $n->getAttribute('value')
			);
	}
}
