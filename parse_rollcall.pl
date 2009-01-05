use Time::Local;
use LWP::UserAgent;
use GD;

require "general.pl";
require "persondb.pl";
require "db.pl";
require "indexing.pl";

if (-e '../gis/loaddistricts_109.pl') {
	require "../gis/loaddistricts_109.pl";
	require "../gis/loaddistricts_110.pl";
} else {
	print STDERR "Not loading GIS module...\n";
	$SkipMaps = 1;
}

my $debug = 1;

my @referencedbills;

if ($ARGV[0] eq "PARSE_ROLL") { &DoCommandLine; }
if ($ARGV[0] eq "GET_ROLLS") { &DownloadRollCallVotesAll($ARGV[1], 0, $ARGV[2], $ARGV[3]); }
if ($ARGV[0] eq "REMAP_VOTES") { &RemapVotes }
if ($ARGV[0] eq "REMAP_VOTE") { &RemapVote; }
if ($ARGV[0] eq "REFRESHBADVOTES") { &RefreshBadVotes; }

1;

######################

sub DownloadRollCallVotesAll {
	my $YEAR = shift;
	my $noopendb = shift;
	my $skipifexists = shift;
	my $forceindex = shift;
	if (!defined($skipifexists)) { $skipifexists = 1; }
	
	if ($YEAR eq "") { $YEAR = YearFromDate(time); }
	
	GovDBOpen() if !$noopendb;

	my $SESSION = SessionFromYear($YEAR);
	my $SUBSESSION = SubSessionFromYear($YEAR);

	my $votesfetched = 0;

	# Download house roll call votes
	my $URL = "http://clerk.house.gov/evs/$YEAR/index.asp";
	my ($content, $mtime) = Download($URL);
	if (!$content) { return; }
	if ($content =~ /vote.asp\?year=$YEAR\&rollnumber=(\d+)/) {
		my $maxHRoll = $1;
		for (my $i = 1; $i <= $maxHRoll; $i++) {
			if (GetHouseVote($YEAR, $i, $skipifexists)) {
				$votesfetched++;
			}
		}
	}
	
	# Download all of the senate roll call votes
	$URL = "http://www.senate.gov/legislative/LIS/roll_call_lists/vote_menu_$SESSION" . "_" . "$SUBSESSION.htm";
	my ($content, $mtime) = Download($URL);
	if (!$content) { return; }
	if ($content =~ /Unspecified/) { die "Senate vote list has an 'Unspecified' vote."; }
	if ($content =~ /roll_call_vote_cfm\.cfm\?congress=$SESSION\&session=$SUBSESSION\&vote=(\d+)/) {
		my $maxSRoll = $1;
		for (my $i = int($maxSRoll); $i >= 1; $i--) {
			if ($skipifexists==1 && -e "../data/us/$SESSION/rolls/s$YEAR-$i.xml") { next; }
			if (GetSenateVote($SESSION, $SUBSESSION, $YEAR, $i, $skipifexists)) {
				$votesfetched++;
			}
		}
	}

	DBClose() if !$noopendb;

	if (($votesfetched == 0 && !$forceindex) || $forceindex eq 'no') { return; }
	
	# Update the bill status files of any referenced bills (and thus amendments too)
	foreach my $bill (@referencedbills) {
		system("perl parse_status.pl PARSE_STATUS " . join(' ', @{ $bill }));
	}

	# Index all of the votes.
	my $indexxml = $XMLPARSER->parse_string('<votes/>');
	my %votenodes;
	my @votes = ScanDir("../data/us/$SESSION/rolls");
	my @nodes;
	foreach my $vote (@votes) {
		my $xml = $XMLPARSER->parse_file("../data/us/$SESSION/rolls/$vote");
		
		my $node = $indexxml->createElement('vote');
		$node->setAttribute('id', firstchar($xml->findvalue('roll/@where')) . YearFromDate($xml->findvalue('roll/@when')) . '-' . $xml->findvalue('roll/@roll'));
		$node->setAttribute('date', $xml->findvalue('roll/@when'));
		$node->setAttribute('where', $xml->findvalue('roll/@where'));
		$node->setAttribute('roll', $xml->findvalue('roll/@roll'));
		$node->setAttribute('title', $xml->findvalue('roll/question'));
		
		if ($xml->findvalue('roll/result') =~ /Passed|Agreed|Confirmed|Amendment Germane|Decision of Chair Sustained|Veto Overridden|Point of Order Sustained/i) { $node->setAttribute('result', 'pass'); }
		elsif ($xml->findvalue('roll/result') =~ /Fail|Defeated|Rejected|Not Sustained|Amendment Not Germane/i) { $node->setAttribute('result', 'fail'); }
		else { warn "$vote: Unparsed result: " . $xml->findvalue('roll/result'); }

		my $counts = $xml->findvalue('roll/@aye') . "-" . $xml->findvalue('roll/@nay');
		if ($xml->findvalue('roll/@nv') + $xml->findvalue('roll/@present') > 0) {
			$counts .= ', ' . ($xml->findvalue('roll/@nv') + $xml->findvalue('roll/@present')) . ' not voting';
		}
		if ($xml->findvalue('roll/@aye') + $xml->findvalue('roll/@nay') == 0) {
			$counts = $xml->findvalue('roll/@present') . " present, " . $xml->findvalue('roll/@nv') . ' not voting';
		}
		$node->setAttribute('counts', $counts);

		push @nodes, $node;
		$votenodes{$node} = $xml->findvalue('roll/@when');

		my ($bill) = $xml->findnodes('roll/bill');
		if ($bill) {
			$node->setAttribute('bill', $bill->getAttribute('type') . $bill->getAttribute('session') . '-' . $bill->getAttribute('number'));
			eval { # if file not found
				my $billxml = GetBill($bill->getAttribute('session'), $bill->getAttribute('type'), $bill->getAttribute('number'));
				$node->setAttribute('bill_title', GetBillDisplayTitle($billxml, 1, 1));

				my ($amd) = $xml->findnodes('roll/amendment');
				if ($amd) {
					my $num;
					if ($amd->getAttribute('ref') eq "regular") {
						$num = $amd->getAttribute('number');
					} else {
						my @nums = $billxml->findnodes('amendments/amendment/@number');
						$num = $nums[$amd->getAttribute('number')]->nodeValue;
					}
					$node->setAttribute('amendment', $num);
					eval {
						my $amdxml = $XMLPARSER->parse_file("../data/us/$SESSION/bills.amdt/$num.xml");
						$node->setAttribute('amendment_title', $amdxml->findvalue('amendment/description'));
					};
				}
			};
		}
	}
	@nodes = sort({ $votenodes{$b} <=> $votenodes{$a}} @nodes);
	foreach my $node (@nodes) {
		$indexxml->documentElement->appendChild($node);
	}
	
	$indexxml->toFile("../data/us/$SESSION/votes.all.index.xml", 2);
}

sub DownloadRollCallVotesForBills {
	my $year = $ARGV[1];
	my $skipexists = $ARGV[2];

	my $session = SessionFromYear($year);
	my @bills = GetBillList($session);
	
	&GovDBOpen;

	foreach my $billref (@bills) {
		my $bill = GetBill(@{ $billref });
		foreach my $votenode ($bill->findnodes("actions/vote[\@how='roll']")) {
			my $y = YearFromDate($votenode->getAttribute("date"));
			if ($y ne $year) { next; }

			my $roll = $votenode->getAttribute("roll");
			my $where = $votenode->getAttribute("where");
			my $session = SessionFromYear($year);
			my $subsession = SubSessionFromYear($year);
			if ($where eq "h") {
				GetHouseVote($year, $roll, $skipexists);
			} elsif ($where eq "s") {
				GetSenateVote($session, $subsession, $year, $roll, $skipexists);
			}
			#print $votenode->toString . "\n";
		}
	}
	
	&DBClose;
}

sub DoCommandLine {
	my $year = $ARGV[1];
	my $type = $ARGV[2];
	my $rolls = $ARGV[3];
	my $skipexists = $ARGV[4];
	my $session = SessionFromYear($year);

	&GovDBOpen;

	my $a;
	my $b;
	if ($rolls =~ /^(\d*)-(\d*)$/) { $a = $1; $b = $2; }
	else { $a = $rolls; $b = $rolls; }

	for ($i = $a; $i <= $b; $i++) {
		if ($type eq "h") {
			GetHouseVote($year, $i, $skipexists);
		} elsif ($type eq "s") {
			GetSenateVote($session, SubSessionFromYear($year), $year, $i, $skipexists);
		}
	}
	
	&DBClose;
}

sub RefreshBadVotes {
	my $session = $ARGV[1];

	&GovDBOpen;
	my %ids;

	my $dir = "../data/us/$session/rolls";
	my @votes = sort(ScanDir($dir));
	foreach my $vote (@votes) {
		my $votefile = $vote;
		$vote = $XMLPARSER->parse_file("$dir/$vote");
		my $year = $vote->documentElement->getAttribute("year");
		my $where = $vote->documentElement->getAttribute("where");
		my $roll = int($vote->documentElement->getAttribute("roll"));

		$where =~ s/(.).*/$1/;

		if ($votefile ne "$where$year-$roll.xml") {
			print "Bad data in $votefile.\n";
			next;
		}

		my $bad = 0;

		if ($vote->documentElement->getAttribute("datetime") eq "") {
			$bad = 1;
		}

		#if ($where eq 's' && $vote->documentElement->findvalue('@aye+@nay+@nv+@present') != 100) {
		#	$bad = 1; # all senate votes where count != 100
		#}

		my $hadAnyId = 0;
		foreach my $id ($vote->findnodes('roll/voter[not(@VP=1)]/@id')) {
			$id = $id->nodeValue;
			$hadAnyId = 1;
			if ($id == 0) { $bad = 1; last; }
			if (!defined($ids{$id})) {
				my ($id2) = DBSelectFirst('people', [id], ["id = $id"]);
				$ids{$id} = defined($id2);
			}
			if (!$ids{$id}) { print "$id\n";  $bad = 1; last; }
		}
		if (!$hadAnyId) { $bad = 1; }
	
		if ($bad) {
			if ($where eq "h") {
				GetHouseVote($year, $roll, 0);
			} elsif ($where eq "s") {
				GetSenateVote($session, SubSessionFromYear($year), $year, $roll, 0);
			}
		}
	}

	&DBClose;
}

sub GetSenateVote {
	my $SESSION = shift;
	my $SUBSESSION = shift;
	my $YEAR = shift;
	my $ROLL = shift;
	my $SKIPIFEXISTS = shift;

	my $fn = "../data/us/$SESSION/rolls/s$YEAR-$ROLL.xml";
	if ($SKIPIFEXISTS && -e $fn) { return 0; }
	if ($SKIPIFEXISTS =~ /^(\d)D/i && -M $fn < $1) { return 0; }

	my $ROLL2 = sprintf("%05d", $ROLL);

	print "Fetching Senate roll $SESSION-$SUBSESSION $ROLL\n" if (!$OUTPUT_ERRORS_ONLY);
	my $URL = "http://www.senate.gov/legislative/LIS/roll_call_lists/roll_call_vote_cfm.cfm?congress=$SESSION&session=$SUBSESSION&vote=$ROLL2";
	my ($content, $mtime) = Download($URL);
	if (!$content) { return; }
	if ($content !~ /Question/) { warn "Vote not found on senate website: $URL"; return; }
	my @contentlines = split(/[\n\r]+/, $content);

	my $TYPE = "";
	my $QUESTION = "";
	my $REQUIRED = "";
	my $RESULT = "";
	my $WHEN = undef;
	my $DATETIME = undef;
	my @aaye = ();
	my @anay = ();
	my @anv = ();
	my @apres = ();
	my %votes = ();
	my $BILL;
	my $AMENDMENT;
	
	my $mode = 0;
	
	if ($content =~ /<b>Question: <\/b>\s+<question>([\w ]+)<\/question>\s+([^<]+)/) {
		$TYPE = $1;
		$QUESTION = $TYPE;
		my $EXTRA = $2;
		$EXTRA =~ s/\s*[\n\r]+\s*/ /g;
		if ($EXTRA ne "") { $QUESTION = "$TYPE $EXTRA"; }
		
		# Ensure the options are noted.
		if ($TYPE eq "Guilty or Not Guilty") {
			$votes{'Guilty'} = [];
			$votes{'Not Guilty'} = [];
		} else {
			$votes{'Yea'} = [];
			$votes{'Nay'} = [];
		}
		$votes{'Present'} = [];
		$votes{'Not Voting'} = [];
	}

	foreach my $line (@contentlines) {
		if ($mode == 0) {
			if ($line =~ /Required For Majority: <\/b><td class="contenttext">([\w\W]+?)<\/td>/i) {
				$REQUIRED = $1;
			}

			#if ($line =~ /Vote Result: (Bill|Resolution) (Passed|Failed|Agreed|Rejected)/) {
			if ($line =~ /Vote Result: <\/b><td valign="top" class="contenttext">([\w\W]+?)<\/td>/i) {
				$RESULT = $1;
			}

			if ($line =~ /Vote Date: <\/b><td valign="top" class="contenttext">((\w+) (\d+), (\d\d\d\d)(,?\s+(\d\d):(\d\d) (AM|PM))?)/i) {
				my $dt = $1;
				my $month = $Months{uc($2)}-1;
				my $date = $3;
				my $year = $4;
				my $hour = $6;
				my $minute = $7;
				my $ampm = $8;
				if ($ampm =~ /p/i && $hour != 12) { $hour += 12; }
				if ($ampm =~ /a/i && $hour == 12) { $hour -= 12; }
				$WHEN = timelocal(0,$minute,$hour,$date,$month,$year);
				$DATETIME = ParseDateTime($dt);
			}

			if ($line =~ /Alphabetical by Senator Name/) { $mode = 1; }

			if ($line =~ /Measure Number: [\w\W]+>$BillPattern</i) {
				my ($t, $n) = ($1, $2);
				$t = $BillTypeMap{lc($t)};
				if (defined($t)) { $BILL = [$SESSION, $t, $n]; }
				
				# TODO: 106-1-18 references a bill in the previous congress
			}

			if ($line =~ /Amendment Number: [\w\W]+>S.Amdt. (\d+)</i) {
				$AMENDMENT = ['regular', $SESSION, 's' . $1];
			}
			if (!defined($BILL) && defined($AMENDMENT) && $line =~ /to [\w\W]+>$BillPattern</i) {
				my ($t, $n) = ($1, $2);
				$t = $BillTypeMap{lc($t)};
				if (defined($t)) { $BILL = [$SESSION, $t, $n]; }
			}

			if ($line =~ /Vice President/ && $line !~ /Statement of Purpose/) {
				$mode = 2;
			}
		} elsif ($mode == 1) {
			if ($line =~ />([\w\'\-,\. ]+) \(\w\w?\-(\w\w)\), <b>([^<\n\r]+)<\/b>/i) {
				my $name = $1;
				my $state = $2;
				my $vote = $3;
				
				my $id = PersonDBGetID(
					title => "sen",
					name => $name,
					state => $state,
					when => $WHEN);
				if (!defined($id)) { print "parsing Senate vote $SESSION-$SUBSESSION $ROLL: Unrecognized person: $name ($state)\n"; $id = 0; }

				if ($vote eq "Present, Giving Live Pair") { $vote = "Present"; }
				
				$vote = htmlify($vote);
				push @{$votes{$vote}}, $id;
			}
			if ($line =~ /<\/table>/i) { last; }
		} elsif ($mode == 2) { # VP
			my $vote;
			$vote = htmlify($vote);
			push @{$votes{$vote}}, "VP";
			$mode = 0;
		}
	}

	if (!defined($BILL) && $QUESTION =~ /$BillPattern/i) {
		my ($t, $n) = ($1, $2);
		$t =~ s/ //g;
		$t = $BillTypeMap{lc($t)};
		if (defined($t)) { $BILL = [$SESSION, $t, $n]; }
	}

	#print join(" ", scalar(@aaye), scalar(@anay), scalar(@anv)) . "\n";

	WriteRoll($fn, $mtime, "senate", $ROLL, $WHEN, $DATETIME, \%votes, $TYPE, $QUESTION, $REQUIRED, $RESULT, $BILL, $AMENDMENT);

	return 1;
}

sub GetHouseVote {
	my $YEAR = shift;
	my $ROLL = shift;
	my $SKIPIFEXISTS = shift;
	
	my $SESSION = SessionFromYear($YEAR);

	my $fn = "../data/us/$SESSION/rolls/h$YEAR-$ROLL.xml";
	if ($SKIPIFEXISTS && -e $fn) { return 0; }
	if ($SKIPIFEXISTS =~ /^(\d)D/i && -M $fn < $1) { return 0; }

	print "Fetching House roll $SESSION-$YEAR $ROLL\n" if (!$OUTPUT_ERRORS_ONLY);
	my $roll2 = sprintf("%03d", $ROLL);
	my $URL = "http://clerk.house.gov/evs/$YEAR/roll$roll2.xml";
	my ($content, $mtime) = Download($URL);
	if (!$content) { return; }

	$content =~ s/<!DOCTYPE .*?>//;

	if ($content eq "") {
		warn "House rollcall at $URL is empty.";
		return 0;
	}

	my $votexml = $XMLPARSER->parse_string($content)->documentElement;

	my $when_date = $votexml->findvalue('vote-metadata/action-date');
	if ($when_date !~ /(\d\d?)-(\w\w\w)-(\d\d\d\d)/) { die "Invalid date: $when_date"; }
	my ($d, $m, $y) = ($1, $2, $3);

	my $when_time = $votexml->findvalue('vote-metadata/action-time/@time-etz');
	if ($when_time !~ /(\d\d?):(\d\d)/) { die "Invalid time: $when_time"; }
	my ($h, $mm) = ($1, $2);

	my $when = timelocal(0, $mm, $h, $d, $Months{uc($m)}-1, $y);
	my $datetime = FormDateTime($y, $Months{uc($m)}, $d, $h, $mm);

	my $ayes = 0;
	my $nays = 0;
	my $presents = 0;
	my $nvs = 0;
        my @bycandidate = $votexml->findnodes('vote-metadata/vote-totals/totals-by-candidate');
        if (@bycandidate>=1) {
           my @pnode = $votexml->findnodes('vote-metadata/vote-totals/totals-by-candidate[candidate="Present"]');
           if (@pnode>0) {
              $presents = $pnode[0]->findvalue('candidate-total');
              print "Present: $presents\n";
           }
           my @nnode = $votexml->findnodes('vote-metadata/vote-totals/totals-by-candidate[candidate="Not Voting"]');
           if (@nnode>0) {
              $nvs = $nnode[0]->findvalue('candidate-total');
              print "Not Voting: $nvs\n";
           }
        } else {
	   $ayes = $votexml->findvalue('vote-metadata/vote-totals/totals-by-vote/yea-total');
	   $nays = $votexml->findvalue('vote-metadata/vote-totals/totals-by-vote/nay-total');
	   $presents = $votexml->findvalue('vote-metadata/vote-totals/totals-by-vote/present-total');
	   $nvs = $votexml->findvalue('vote-metadata/vote-totals/totals-by-vote/not-voting-total');
        }
	
	my $type = $votexml->findvalue('vote-metadata/vote-question');
	my $question = "";
	if ($votexml->findvalue('vote-metadata/amendment-num') ne "") {
		$question .= "Amendment " . $votexml->findvalue('vote-metadata/amendment-num') . " to ";
	}
	$question .= $votexml->findvalue('vote-metadata/legis-num');
	$question .= " " . $votexml->findvalue('vote-metadata/vote-desc');
	if ($question !~ /\S/) { $question = $type; }
	else { $question = $type . ": " . $question ; }
	my $required = $votexml->findvalue('vote-metadata/vote-type');	
	if ($required eq "YEA-AND-NAY") {
		$required = "1/2";
	} elsif ($required eq "2/3 YEA-AND-NAY") {
		$required = "2/3";
	} elsif ($required eq "3/5 YEA-AND-NAY") {
		$required = "3/5";
	} elsif ($required eq "1/2" ) {
	} elsif ($required eq "2/3" ) {
	} elsif ($required eq "QUORUM" ) {
	} elsif ($required eq "RECORDED VOTE" ) {
		$required = "1/2";
	} elsif ($required eq "2/3 RECORDED VOTE") {
		$required = "2/3";
	} elsif ($required eq "3/5 RECORDED VOTE") {
		$required = "3/5";
	} else {
		warn "Unknown house vote type '$required' in $URL";
	}

	my $bill = $votexml->findvalue('vote-metadata/legis-num');
	$bill =~ s/ //g;
	if ($bill =~ /^$BillPattern$/i) {
		my ($t, $n) = ($1, $2);
		$t = $BillTypeMap{lc($t)};
		if (defined($t)) { $bill = [$SESSION, $t, $n]; } else { undef $bill; }
	} else { undef $bill; }

	my $amendment = $votexml->findvalue('vote-metadata/amendment-num');
	if ($amendment ne "") { $amendment = ['bill-serial', $SESSION, $amendment]; }
	else { undef $amendment; }

	my $result = $votexml->findvalue('vote-metadata/vote-result');
	if ($result ne "Passed" && $result ne "Failed" && $result ne "Agreed to") { 
		warn "Roll call isn't a pass/fail vote '$result' in $URL";
	}

	# Make sure all options are noted.
	my %votes = ();
	if ($type eq 'Election of the Speaker') {
		for my $n ($votexml->findnodes('vote-metadata/vote-totals/totals-by-candidate/candidate')) {
			$n = htmlify($n->textContent);
			$votes{$n} = [];
		}
	} else {
		if ($votexml->findvalue('vote-metadata/vote-type') =~ /YEA-AND-NAY/) {
			$votes{'Yea'} = [];
			$votes{'Nay'} = [];
		} else {
			$votes{'Aye'} = [];
			$votes{'No'} = [];
		}
		$votes{'Present'} = [];
		$votes{'Not Voting'} = [];
	}

	foreach my $voter ($votexml->findnodes('vote-data/recorded-vote')) {
		my $vote = $voter->findvalue('vote');
		
		my $bioguideid = $voter->findvalue('legislator/@name-id');
		my $name = $voter->findvalue('legislator/@unaccented-name');
		my $state = $voter->findvalue('legislator/@state');
		if ($name eq "") { $name = $voter->findvalue('legislator'); }
		$name =~ s/ \(\w\w\)$//;

		my $id;
		if ($bioguideid eq "" || $bioguideid eq "0000000") {
			if ($state eq 'XX') { undef $state; } # delegates in the 103rd congress and before
			$id = PersonDBGetID(
			title => "rep",
			name => $name,
			state => $state,
			when => $when);
		} else {
			$id = $BioguideIdMap{$bioguideid};
			if (!defined($id)) {
				($id) = DBSelectFirst(people, [id], [DBSpecEQ(bioguideid, $bioguideid)]);
				$BioguideIdMap{$bioguideid} = $id;
			}
		}
		if (!defined($id)) { warn "parsing House vote $SESSION-$YEAR $ROLL: Unrecognized person: $bioguideid: $name ($state) in $URL"; $id = 0; }

		$vote = htmlify($vote);
		push @{$votes{$vote}}, $id;
	}

	#if (scalar(@aaye) != $ayes) { die "Vote totals don't match up: aye $ayes " . scalar(@aaye); }
	#if (scalar(@anay) != $nays) { die "Vote totals don't match up: nay $nays " . scalar(@nay); }
	#if (scalar(@anv) != $nvs) { die "Vote totals don't match up: not voting $nvs " . scalar(@anv); }
	#if (scalar(@apr) != $presents) { die "Vote totals don't match up: present $presents " . scalar(@pr); }

	WriteRoll($fn, $mtime, "house", $ROLL, $when, $datetime, \%votes, $type, $question, $required, $result, $bill, $amendment);
	return 1;
}

sub WriteRoll {
	my $fn = shift;
	my $mtime = shift;
	my $where = shift;
	my $ROLL = shift;
	my $when = shift;
	my $datetime = shift;
	my $rvotes = shift;
	my $TYPE = shift;
	my $QUESTION = shift;
	my $REQUIRED = shift;
	my $RESULT = shift;
	my $BILL = shift;
	my $AMENDMENT = shift;

	my $SESSION = SessionFromDate($when);
	my $YEAR = YearFromDate($when);

	my %votes = %{ $rvotes };

	my $aye = scalar(@{$votes{Aye}}) + scalar(@{$votes{Yea}});
	my $nay = scalar(@{$votes{Nay}}) + scalar(@{$votes{No}});
	my $nv = scalar(@{$votes{'Not Voting'}});
	my $pr = scalar(@{$votes{Present}});
	
	$TYPE = htmlify($TYPE);
	$QUESTION = htmlify($QUESTION);
	$REQUIRED = htmlify($REQUIRED);
	$RESULT = htmlify($RESULT);

	$QUESTION =~ s/ +$//;

	`mkdir -p ../data/us/$SESSION/rolls`;

	$mtime = DateToISOString($mtime);

	open ROLL, ">$fn" || die "Couldn't open roll file";
	print ROLL "<roll where=\"$where\" session=\"$SESSION\" year=\"$YEAR\" roll=\"$ROLL\" when=\"$when\"\n";
	print ROLL "\tdatetime=\"$datetime\" updated=\"$mtime\"\n";
	print ROLL "\taye=\"$aye\" nay=\"$nay\" nv=\"$nv\" present=\"$pr\">\n";
	print ROLL "\t<type>$TYPE</type>\n";
	print ROLL "\t<question>$QUESTION</question>\n";
	print ROLL "\t<required>$REQUIRED</required>\n";
	print ROLL "\t<result>$RESULT</result>\n";
	if (defined($BILL)) { print ROLL "\t<bill session=\"$$BILL[0]\" type=\"$$BILL[1]\" number=\"$$BILL[2]\" />\n"; }
	if (defined($AMENDMENT)) { print ROLL "\t<amendment ref=\"$$AMENDMENT[0]\" session=\"$$AMENDMENT[1]\" number=\"$$AMENDMENT[2]\" />\n"; }
	
	# Get the options is a good order.
	my @options;
	my %doneoptions;
	for my $k ('Aye', 'Yea', 'Guilty', 'No', 'Nay', 'Not Guilty') {
		if ($votes{$k} && !$doneoptions{$k}) {
			push @options, $k;
			$doneoptions{$k} = 1;
		}
	}
	for my $k (sort(keys(%votes))) {
		if ($votes{$k} && !$doneoptions{$k} && $k ne 'Present' && $k ne 'Not Voting') {
			push @options, $k;
			$doneoptions{$k} = 1;
		}
	}
	for my $k ('Present', 'Not Voting') {
		if ($votes{$k} && !$doneoptions{$k}) {
			push @options, $k;
			$doneoptions{$k} = 1;
		}
	}
	
	my %votesymbols;
	foreach my $k (@options) {
		my $sym = $k;
		if ($k eq "Aye" || $k eq "Yea" || $k eq "Guilty") { $sym = "+"; }
		if ($k eq "No" || $k eq "Nay" || $k eq "Not Guilty") { $sym = "-"; }
		if ($k eq "Present") { $sym = "P"; }
		if ($k eq "Not Voting") { $sym = "0"; }
		$votesymbols{$k} = $sym;
		print ROLL "\t<option key=\"$sym\">$k</option>\n";
	}
	
	foreach my $k (@options) {
		foreach $id (@{ $votes{$k} }) {
			my $sdattr = "";
			print ROLL "\t<voter ";
			if ($id eq "VP") {
				print ROLL "VP=\"1\" id=\"0\" "
			} else {
				print ROLL "id=\"$id\" ";
				if (!$PersonSD{$id}) {
					my ($state, $dist) = DBSelectFirst(people_roles, [state, district], [DBSpecEQ('personid', $id), DBSpecEQ('type', $where eq 'house' ? 'rep' : 'sen'), PERSON_ROLE_THEN(DateToDBString($when))]);
					$sdattr = "state=\"$state\"";
					if ($where eq 'house') { $sdattr .= " district=\"$dist\""; }
					$PersonSD{$id} = $sdattr; # fortunately can't really change within a session
				} else {
					$sdattr = $PersonSD{$id};
				}
			}
			print ROLL "vote=\"$votesymbols{$k}\" value=\"$k\" $sdattr/>\n";
        }
	}

	print ROLL "</roll>\n";
	close ROLL;
	
	if ($fn !~ /\/(\w\d\d\d\d\-\d+)\.xml$/) { die $fn; }
	my $id = $1;
	if (!$ENV{NOMAP} && !$SkipMaps) { MakeVoteMap($id); }

	if (defined($BILL)) {
		push @referencedbills, $BILL;
	} elsif (defined($AMENDMENT)) {
		warn "Amendment without bill reference in $fn";
	}

	IndexVote($SESSION, $id);
	WriteStatus("Vote:$where", "Last fetched: $id");
}

################################

sub RemapVote {
	GovDBOpen();
	MakeVoteMap($ARGV[1]);
	DBClose();
}

sub RemapVotes {
	GovDBOpen();
	
	my $session = $ARGV[1];
	my $skipifexists = $ARGV[2];
	opendir D, "../data/us/$session/rolls";
	foreach my $d (readdir(D)) {
		if ($d =~ /([hs]\d\d\d\d-\d+)\.xml$/) {
			my $f = $1;
			my $f2 = "../data/us/$session/gen.rolls-cart/$f.png";
			if ($skipifexists && -e $f2) { next; }
			#if (-e $f2 && fileage($f2) < 1) { next; }
			MakeVoteMap($f);
		}
	}
	closedir D;
	
	DBClose();
}

sub MakeVoteMap {
	my $votefile = shift;

	if ($votefile !~ /^\w(\d\d\d\d)-\d+$/) { die $votefile; }
	my $year = $1;
	my $session = SessionFromYear($year);
	
	if ($session < 109) { return; }

	GD::Image->useFontConfig(1);
	my $ttFontName = 'Arial';
	my $ttFontOpts = { resolution => '150,150' };

	my $votedir = "../data/us/$session/rolls";
	my $votedirgeo = "../data/us/$session/gen.rolls-geo";
	my $votedirpca = "../data/us/$session/gen.rolls-pca";
	my $votedircart = "../data/us/$session/gen.rolls-cart";

	`mkdir -p $votedirgeo`;
	`mkdir -p $votedirpca`;
	`mkdir -p $votedircart`;
	
	print "Making Vote Map for $session/$votefile\n" if (!$OUTPUT_ERRORS_ONLY);

	my $votexml = $XMLPARSER->parse_file("$votedir/$votefile.xml")->documentElement;
	my $where = $votexml->getAttribute("where");
	my $reptype;
	if ($where eq "house") { $reptype = "rep"; } else { $reptype = "sen"; }

	my $when = DateToDBString($votexml->getAttribute("when"));
	my $PERSON_ROLE_NOW = "(startdate <= '$when' and enddate >= '$when')";
	
	# CORRELATION WITH PARTY
	
	my %votebreakdown;
	
	if (!defined(%PersonPoliticalParties)) {
		my $parties = DBSelect(people_roles, [personid, party], [$PERSON_ROLE_NOW]);
		foreach my $p (@$parties) {
			$PersonPoliticalParties{$$p[0]} = $$p[1];
		}
	}
	
	foreach my $n ($votexml->findnodes("voter")) {
		my $id = $n->getAttribute('id');
		my $vote = $n->getAttribute('vote');
		if ($id == 0) { next; }
		
		if ($vote eq "+") { $vote = 1; }
		elsif ($vote eq "-") { $vote = -1; }
		else { next; }
		
		my $party = $PersonPoliticalParties{$id};
		if ($party eq "Democrat") { $party = "D"; }
		elsif ($party eq "Republican") { $party = "R"; }
		else { next; }
		
		$votebreakdown{$party}{$vote}++;
		$votebreakdown{$party}{T}++;
	}
	
	my $correl_str = "";

	if ($votebreakdown{D}{T} > 0 && $votebreakdown{R}{T} > 0) {
		my $d = int(100 * $votebreakdown{D}{1} / $votebreakdown{D}{T});
		my $r = int(100 * $votebreakdown{R}{1} / $votebreakdown{R}{T});
		if ($d > 40 && $d < 60 && $r > 40 && $r < 60) {
			$correl_str = "Parties mixed on issue.";
		} elsif ($d > 50 && $r > 50) {
			$correl_str = "Bipartisan support.";
		} elsif ($d < 50 && $r < 50) {
			$correl_str = "Bipartisan opposition.";
		} elsif ($d > 50) {
			$r = 100 - $r;
			$correl_str = "$d% of Democrats supporting, $r% of Republicans opposing.";
		} elsif ($r > 50) {
			$d = 100 - $d;
			$correl_str = "$r% of Republicans supporting, $d% of Democrats opposing.";
		}
	}

	open CORREL, ">$votedirpca/$votefile.txt";
	print CORREL $correl_str;
	close CORREL;
	
	print "$correl_str\n" if (!$OUTPUT_ERRORS_ONLY);
	
	# GEOGRAPHIC MAP
	
	eval("LoadDistricts$session");

	for my $size ('large', 'small') {
	for my $imgmode ('geo', 'carto') {

	my $im = new GD::Image($size eq 'large' ? 400 : 220, $size eq 'large' ? 210 : 118, 1);
	my $white = $im->colorAllocate(255,255,255);
	my $black = $im->colorAllocate(0,0,0);
	my $grey = $im->colorAllocate(150,150,150);
	$im->filledRectangle(0, 0, $im->width, $im->height, $white);

	my %votecolor = (
		'-' => $im->colorAllocate(200,0,0),
		'0' => $im->colorAllocate(0,255,255),
		'P' => $im->colorAllocate(0,200,200),
		'+' => $im->colorAllocate(0,0,255));
	my %votecolorlt = (
		'-' => $im->colorAllocate(220,80,80),
		'0' => $im->colorAllocate(100,255,255),
		'P' => $im->colorAllocate(100,200,200),
		'+' => $im->colorAllocate(80,80,255));

	my %hadvote;

	my @voters = $votexml->findnodes("voter");

	my @voterids;
	foreach my $n (@voters) {
		if ($n->getAttribute('id') ne '') {
			push @voterids, $n->getAttribute('id');
		}
	}

	my %PersonRoles;
	if (scalar(@voterids) == 0) { warn "Failed to get any IDs of people in $votefile?!?"; return; }
	foreach my $r (@{ DBSelect(people_roles, [personid, state, district], [DBSpecIn(personid, @voterids), $PERSON_ROLE_NOW, "type = '$reptype'"]) }) {
		$PersonRoles{"$$r[0]:$session"} = [$$r[1], $$r[2]];
	}

	my %statelist;
	foreach my $n (@voters) {
		my $id = $n->getAttribute('id');
		my $vote = $n->getAttribute('vote');
		if ($id == 0) { next; }
		
		my ($state, $dist) = @{ $PersonRoles{"$id:$session"} };
		if (!defined($state)) {
			my ($firstname, $lastname) = DBSelectFirst(people, [firstname, lastname], ["id=$id"]);
			warn "Person $firstname $lastname ($id) didn't have a role on $when, or failed to fetch roles, in $votefile.";
		}

		# Draw the first senator for a state we encounter across the whole state.
		# Draw the other one in just half, drawing over the first.  If we just
		# drew two halves, the line where the halves meet would be inexact and spotty.
		my $sennum = 0;
		if ($reptype eq "sen") {
			$sennum = !defined($statelist{$state}) ? 0 : 1;
		}
		
		$statelist{$state} = 1;

		if ($reptype eq "sen") { $dist = ""; }
		if (!defined($DistrictPolys{"$size$imgmode$state$dist$sennum"})) { # cache the polygons when batch-drawing maps
			my @gdpolys;
			my $polys = LoadPolys($imgmode, $reptype, $session, $state, $dist);
			foreach my $poly (@$polys) {
			foreach my $poly2 (@{ SplitPoly(ReducePoly($poly, $imgmode), $sennum) }) {
				push @gdpolys, CreateGDPoly($poly2, $im, $imgmode);
			}
			}
			$DistrictPolys{"$size$imgmode$state$dist$sennum"} = [@gdpolys];
		}
		foreach my $gdpoly (@{ $DistrictPolys{"$size$imgmode$state$dist$sennum"} }) {
			$im->filledPolygon($gdpoly, $votecolor{$vote});
			#if ($imgmode eq 'carto' && $size eq 'large' && $reptype eq 'rep') {
			#	$im->openPolygon($gdpoly, $votecolorlt{$vote});
			#}
		}

		$hadvote{$vote} = 1;
	}
	
	# draw state borders
	foreach my $state (keys(%statelist)) {
		my $polys = LoadPolys($imgmode, $reptype, $session, $state, '');
		foreach my $poly (@$polys) {
			my $gdpoly = CreateGDPoly($poly, $im, $imgmode);
			if ($imgmode eq 'geo') {
				$im->setAntiAliased($black);
				$im->openPolygon($gdpoly, GD::gdAntiAliased);
			} else {
				$im->openPolygon($gdpoly, $black);
			}
		}
	}

	my %votekey = ('Aye' => '+', 'Nay' => '-', 'No Vote' => '0', 
		'Present' => 'P');
	my $keyx = 5;
	my $font = $size eq 'large' ? gdLargeFont : gdSmallFont;
	foreach my $vk ('Aye', 'Nay', 'Present', 'No Vote', 'Split') {
		if (!$hadvote{$votekey{$vk}}) { next; }
		$im->filledRectangle($keyx - $font->width/3,$im->height-1.25*$font->height-1,
			$keyx + $font->width*(length($vk)+1/5), $im->height-.2*$font->height,
			$votecolor{$votekey{$vk}});
		#$im->string($font, $keyx,$im->height-1.2*$font->height, $vk, 
		#	($vk eq "Aye" || $vk eq "Nay") ? $white : $black);
		my $fs = 7;
		if ($size eq 'small') { $fs = 5; }
		$im->stringFT(($vk eq "Aye" || $vk eq "Nay") ? $white : $black, $ttFontName, $fs, 0, $keyx, $im->height-$fs, $vk, $ttFontOpts);
		$keyx += $font->width*(length($vk)+1);
	}

	if ($size eq 'large' && $imgmode eq 'carto') {
		$im->stringFT($grey, $ttFontName, 5, 0, 3, 8,
			$reptype eq 'sen' ? "This cartogram shows each state with equal area."
							  : "This cartogram shows congressional districts with equal area.",
			$ttFontOpts);
		#$im->string(gdTinyFont, 3,2, 
		#	$reptype eq 'sen' ? "This cartogram shows each state with equal area."
		#					  : "This cartogram shows each congressional district with equal area.",
		#	$grey);
	}

	my $small = $size eq 'large' ? '' : '-small';
	my $dir = $imgmode eq 'geo' ? $votedirgeo : $votedircart;
	open IMG, ">$dir/$votefile$small.png";
	#open IMG, ">../website/vote.png";
	print IMG $im->png;
	close IMG;
	#print "$votefile$small\n";

	} # geo/carto
	} # small/large
}

sub LoadPolys {
	my ($imgmode, $reptype, $session, $state, $dist) = @_;
	if ($imgmode eq 'geo') {
		return eval("GetDistrictShapes$session('$state', '$dist')");
	} else {
		if ($state eq 'AK' || $state eq 'HI') {
			return LoadPolys('geo', $reptype, $session, $state, $dist);
		}
		if ($reptype eq 'sen') {
			require "../gis/data/cartogrampoints-$session-state.pl";
			return $CartogramPolygons_state{$session}{"$state"};
		} else {
			require "../gis/data/cartogrampoints-$session-dist.pl";
			if ($dist eq '') { # entire state boundary
				return $CartogramPolygons_dist{$session}{"$state"};
			} else { # just the district
				return $CartogramPolygons_dist{$session}{"$state-$dist"};
			}
		}
	}
}

sub MapProject {
	my ($lat, $long, $imgmode, $reptype) = @_;
	if ($long >= -125) {
		my ($x, $y) = AlbersEqualAreaConicProjection($lat, $long, 39,-96, 35,40);
		if ($imgmode eq 'geo') {
			return ($x*1.13+.07, $y*1.13+.005);
		} elsif ($reptype eq 'sen') {
			return ($x*1.1+.05, $y*1.1+.015);
		} else {
			return ($x*1.05+.05, $y*1.05+.015);
		}
	} elsif ($lat > 45) {
		# alaska
		my ($x, $y) = AlbersEqualAreaConicProjection($lat, $long, 64,-151, 50,70);
		if ($imgmode eq 'geo' || $reptype eq 'sen') {
			return ($x/2.9 - .435, $y/2.8 + .17);
		} else {
			return ($x/4.2 - .42, $y/4.2 + .17);
		}
	} else {
		# hawaii
		my ($x, $y) = AlbersEqualAreaConicProjection($lat, $long, 20,-155, 17,23);
		if ($imgmode eq "geo") {
			return ($x - .375, $y - .05);
		} elsif ($reptype eq 'sen') {
			return ($x*2.5 - .3, $y*2.5 - .105);
		} else {
			return ($x*1.5 - .375, $y*1.5 - .05);
		}
	}
}

sub ReducePoly {
	my $poly = $_[0];
	my $imgmode = $_[1];
	if ($imgmode eq 'carto') { return $poly; }
	my @pt = @{ $poly };
	my @lst;
	my @newpoly;
	for (my $i = 0; $i < scalar(@pt); $i += 2) {
		my $dx1 = $pt[$i]-$lst[0];
		my $dy1 = $pt[$i+1]-$lst[1];
		my $dd1 = $dx1*$dx1+$dy1*$dy1;
		if ($dd1 < .025) { next; } # .1 was good for senate maps
		@lst = ($pt[$i], $pt[$i+1]);
		push @newpoly, $pt[$i], $pt[$i+1];
	}
	return [@newpoly];
}

sub CreateGDPoly {
	my $poly = $_[0];
	my $im = $_[1];
	my $imgmode = $_[2];
	my $gdpoly = new GD::Polygon;
	my @pt = @{ $poly };
	for (my $i = 0; $i < scalar(@pt); $i += 2) {
		($pt[$i], $pt[$i+1]) = MapProject($pt[$i+1], $pt[$i], $imgmode);

		$pt[$i] = $pt[$i]*$im->width + $im->width/2;
		$pt[$i+1] = $im->height - ($pt[$i+1]*$im->width + $im->height/2);

		$gdpoly->addPt($pt[$i], $pt[$i+1]);
	}
	return $gdpoly;
}

sub SplitPoly {
	my $poly = shift;
	my $mode = shift;
	if ($mode == 0) { return [$poly]; }

	my @pt = @{ $poly };
	if (scalar(@pt) < 3) { return [$poly]; }

	# find the bounds
	my ($minx, $maxx, $miny, $maxy);
	for (my $i = 0; $i < scalar(@pt); $i += 2) {
		my ($x, $y) = ($pt[$i], $pt[$i+1]);
		if ($i == 0 || $x < $minx) { $minx = $x; }
		if ($i == 0 || $x > $maxx) { $maxx = $x; }
		if ($i == 0 || $y < $miny) { $miny = $y; }
		if ($i == 0 || $y > $maxy) { $maxy = $y; }
	}

	# equation of the splitting line, the rectangle's diagonal
	my ($m, $b);
	#$m = -($maxy-$miny)/($maxx-$minx);
	#$m = -.5;
	#$b = $miny + $m*(-$minx);
	$m = 0;
	$b = $miny;

	my @newpolys;
	for (my $b2 = $b - ($maxy-$miny)/5/2; $b2 < $b + ($maxy-$miny); $b2 += ($maxy-$miny)/2.5) {
		foreach my $poly2 (@{ SplitPoly2($poly, $m, $b2, 1) }) {
			foreach my $poly3 (@{ SplitPoly2($poly2, $m, $b2+($maxy-$miny)/5, -1) }) {
				if (scalar(@{$poly3}) >= 3) { push @newpolys, $poly3; }
			}
		}
	}
	return [@newpolys];
}

sub SplitPoly2 {
	my $poly = shift;
	my $m = shift;
	my $b = shift;
	my $side = shift;
	my @pt = @{ $poly };
	if (scalar(@pt) < 3) { return [$poly]; }

	# split the polygon
	my @polys;
	my @newpoly;
	my ($px, $py, $pon, $nextxmark);
	for (my $i = 0; $i < scalar(@pt); $i += 2) {
		my ($x, $y) = ($pt[$i], $pt[$i+1]);
		my $pre = $m*$x + $b;
		my $on = ($side > 0 ? ($y >= $pre) : ($y <= $pre));
		if ($on && ($pon || !defined($pon))) {
			# still on the good side
			push @newpoly, $x, $y;
		} elsif (!$pon && !$on) {
			# still on the bad side
		} else {
			# crossing on or off -- include the intersecting point on this segment
			if ($on && ($side*$x > $side*$nextxmark) && defined($nextxmark)) {
				# start a new polygon, assumes poly is CCW or something
				push @newpoly, $newpoly[0], $newpoly[1];
				push @polys, [@newpoly]; undef @newpoly;
			}

			my $k = ($b + $m*$px - $py) / ($y - $py - $m*($x-$px));
			push @newpoly, $px + $k*($x-$px), $py + $k*($y-$py);
			if ($on) {
				push @newpoly, $x, $y; # and take this point
			} else {
				$nextxmark = $x;
			}
		}

		($px, $py, $pon) = ($x, $y, $on);
	}
	push @polys, [@newpoly];

	return [@polys];
}
