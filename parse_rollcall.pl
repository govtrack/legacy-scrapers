# for y in {2011..1989}; do CACHED=1 NOMAP=1 perl parse_rollcall.pl GET_ROLLS $y 0 no; done

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
	require "../gis/loaddistricts_111.pl";
	require "../gis/loaddistricts_112.pl";
} else {
	print STDERR "Not loading GIS module...\n";
	$SkipMaps = 1;
}

my $debug = 1;

my @referencedbills;

if ($ENV{OUTPUT_ERRORS_ONLY}) { $OUTPUT_ERRORS_ONLY = 1; }

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
	if (!defined($skipifexists) && !$ENV{CACHED}) { $skipifexists = 1; }
	
	if ($YEAR eq "") { $YEAR = YearFromDate(time); }
	
	GovDBOpen() if !$noopendb;

	my $SESSION = SessionFromYear($YEAR, 1);
	my $SUBSESSION = SubSessionFromYear($YEAR, 1);

	my $votesfetched = 0;

	# Download house roll call votes
	my $URL = "http://clerk.house.gov/evs/$YEAR/index.asp";
	my ($content, $mtime) = Download($URL);
	if ($content && $content =~ /vote.asp\?year=$YEAR\&rollnumber=(\d+)/) {
		my $maxHRoll = $1;
		for (my $i = 1; $i <= $maxHRoll; $i++) {
			# This vote was vacated. There is no record. Don't bother downloading.
			if ("$YEAR-$i" eq "2011-484") { next; }
		
			if (GetHouseVote($YEAR, $i, $skipifexists)) {
				$votesfetched++;
			}
		}
	}
	
	# Download all of the senate roll call votes
	$URL = "http://www.senate.gov/legislative/LIS/roll_call_lists/vote_menu_$SESSION" . "_" . "$SUBSESSION.xml";
	my ($content, $mtime) = Download($URL);
	while ($content =~ /<vote_number>(\d+)<\/vote_number>/g) {
		my $i = int($1);
		if ($skipifexists==1 && -e "../data/us/$SESSION/rolls/s$YEAR-$i.xml") { next; }
		if (GetSenateVote($SESSION, $SUBSESSION, $YEAR, $i, $skipifexists)) {
			$votesfetched++;
		}
	}

	DBClose() if !$noopendb;
	
	# If we found votes, touch the website to force the cache to clear.
	if ($votesfetched != 0) {
		system("touch ../../website/style/master.xsl");
	}

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
		$node->setAttribute('id', firstchar($xml->findvalue('roll/@where')) . YearFromDateTime($xml->findvalue('roll/@datetime')) . '-' . $xml->findvalue('roll/@roll'));
		$node->setAttribute('datetime', $xml->findvalue('roll/@datetime'));
		$node->setAttribute('where', $xml->findvalue('roll/@where'));
		$node->setAttribute('roll', $xml->findvalue('roll/@roll'));
		$node->setAttribute('title', $xml->findvalue('roll/question'));
		
		if ($xml->findvalue('roll/result') =~ /Passed|Agreed|Confirmed|Amendment Germane|Decision of Chair Sustained|Veto Overridden|Point of Order Sustained/i) { $node->setAttribute('result', 'pass'); }
		elsif ($xml->findvalue('roll/result') =~ /Fail|Defeated|Rejected|Not Sustained|Amendment Not Germane|Point of Order Not Well Taken|Not Guilty|Veto Sustained/i) { $node->setAttribute('result', 'fail'); }
		elsif ($xml->findvalue('roll/result') =~ /Guilty/i) { $node->setAttribute('result', 'pass'); }
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
		$votenodes{$node} = $xml->findvalue('roll/@datetime');

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
	@nodes = sort({ $votenodes{$a} cmp $votenodes{$b}} @nodes);
	foreach my $node (@nodes) {
		$indexxml->documentElement->appendChild($node);
	}
	
	$indexxml->toFile("../data/us/$SESSION/votes.all.index.xml", 2);
}

sub DownloadRollCallVotesForBills {
	my $year = $ARGV[1];
	my $skipexists = $ARGV[2];

	my $session = SessionFromYear($year, 1);
	my @bills = GetBillList($session);
	
	&GovDBOpen;

	foreach my $billref (@bills) {
		my $bill = GetBill(@{ $billref });
		foreach my $votenode ($bill->findnodes("actions/vote[\@how='roll']")) {
			my $y = YearFromDate($votenode->getAttribute("date"));
			if ($y ne $year) { next; }

			my $roll = $votenode->getAttribute("roll");
			my $where = $votenode->getAttribute("where");
			my $session = SessionFromYear($year, 1);
			my $subsession = SubSessionFromYear($year, 1);
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
	my $session = SessionFromYear($year, 1);

	&GovDBOpen;

	my $a;
	my $b;
	if ($rolls =~ /^(\d*)-(\d*)$/) { $a = $1; $b = $2; }
	else { $a = $rolls; $b = $rolls; }

	for ($i = $a; $i <= $b; $i++) {
		if ($type eq "h") {
			GetHouseVote($year, $i, $skipexists);
		} elsif ($type eq "s") {
			GetSenateVote($session, SubSessionFromYear($year, 1), $year, $i, $skipexists);
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

		if ($vote->documentElement->getAttribute("datetime") !~ /T/) {
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
				GetSenateVote($session, SubSessionFromYear($year, 1), $year, $roll, 0);
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
	my $URL = "http://www.senate.gov/legislative/LIS/roll_call_votes/vote$SESSION$SUBSESSION/vote_${SESSION}_${SUBSESSION}_${ROLL2}.xml";
	my ($content, $mtime) = Download($URL);
	if (!$content) { warn "Vote not found on senate website: $URL"; return; }
	my $doc = $XMLPARSER->parse_string($content)->documentElement;

	my $TYPE = $doc->findvalue('question');
	my $QUESTION = $TYPE . ' (' . $doc->findvalue('vote_title') . ')';
	my $REQUIRED = $doc->findvalue('majority_requirement');
	my $RESULT = $doc->findvalue('vote_result');
	my %votes = ();

	# Ensure the options are noted, even if no one votes that way.
	if ($TYPE eq "Guilty or Not Guilty") {
		$votes{'Guilty'} = [];
		$votes{'Not Guilty'} = [];
	} else {
		$votes{'Yea'} = [];
		$votes{'Nay'} = [];
	}
	$votes{'Present'} = [];
	$votes{'Not Voting'} = [];

	my $DATETIME = ParseDateTime($doc->findvalue('vote_date'));
	my $WHEN = DateTimeToDate($DATETIME);

	my $BILL;
	if ($doc->findvalue('document/document_type')) {
		my $t = $BillTypeMap{lc($doc->findvalue('document/document_type'))};
		my $n = $doc->findvalue('document/document_number');
		if (defined($t)) { $BILL = [$SESSION, $t, $n]; }
		# TODO: 106-1-18 references a bill in the previous congress?
	}

	my $AMENDMENT;
	if ($doc->findvalue('amendment/amendment_number')) {
		if ($doc->findvalue('amendment/amendment_number') =~ /^S.Amdt. (\d+)$/i) {
			$AMENDMENT = ['regular', $SESSION, 's' . $1];
		} else {
			warn "Unrecognized amendment number type: " . $doc->findvalue('amendment/amendment_number') . " in $URL";
		}
		if ($doc->findvalue('amendment/amendment_to_document_number') =~ /^$BillPattern$/i) {
			my ($t, $n) = ($1, $2);
			$t = $BillTypeMap{lc($t)};
			if (defined($t)) { $BILL = [$SESSION, $t, $n]; }
		} else {
			warn "Amendment without bill in $URL";
		}
	}

	if ($doc->findvalue('tie_breaker/by_whom')) {
		if ($doc->findvalue('tie_breaker/by_whom') ne 'Vice President') { die "Non-VP tie breaker not implemented yet in $URL"; }
		push @{$votes{$doc->findvalue('tie_breaker/tie_breaker_vote')}}, "VP";
	}
	
	for my $m ($doc->findnodes('members/member')) {
		my $name = $m->findvalue('last_name') . ', ' . $m->findvalue('first_name');
		my $state = $m->findvalue('state');
		my $vote = $m->findvalue('vote_cast');
		
		my $lmi = $m->findvalue('lis_member_id');
		my $id;
		if ($lmi) {
			($id) = DBSelectFirst(people, [id], [DBSpecEQ(lismemberid, $lmi)]);
		}
		if (!$id) { 
			$name =~ s/Burdick, Quentin S/Burdick, Quentin N/;
			$id = PersonDBGetID(
				title => "sen",
				name => $name,
				state => $state,
				when => $WHEN);
			if (!defined($id)) { print "parsing Senate vote $SESSION-$SUBSESSION $ROLL: Unrecognized person: $name ($state)\n"; $id = 0; }
			elsif ($lmi) {
				DBUpdate(people, ["id=$id"], lismemberid => $lmi);
			}
		}

		if ($vote eq "Present, Giving Live Pair") { $vote = "Present"; }
				
		$vote = htmlify($vote);
		push @{$votes{$vote}}, $id;
	}

	WriteRoll($fn, $mtime, "senate", $ROLL, $DATETIME, \%votes, $TYPE, $QUESTION, $REQUIRED, $RESULT, $BILL, $AMENDMENT, "senate.gov");

	return 1;
}

sub GetHouseVote {
	my $YEAR = shift;
	my $ROLL = shift;
	my $SKIPIFEXISTS = shift;
	
	my $SESSION = SessionFromYear($YEAR, 1);

	my $fn = "../data/us/$SESSION/rolls/h$YEAR-$ROLL.xml";
	if ($SKIPIFEXISTS && -e $fn) { return 0; }
	if ($SKIPIFEXISTS =~ /^(\d)D/i && -M $fn < $1) { return 0; }

	my $roll2 = sprintf("%03d", $ROLL);
	my $URL = "http://clerk.house.gov/evs/$YEAR/roll$roll2.xml";
	print "Fetching House roll $SESSION-$YEAR $ROLL at $URL\n" if (!$OUTPUT_ERRORS_ONLY);
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
           }
           my @nnode = $votexml->findnodes('vote-metadata/vote-totals/totals-by-candidate[candidate="Not Voting"]');
           if (@nnode>0) {
              $nvs = $nnode[0]->findvalue('candidate-total');
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
	if ($result ne "Passed" && $result ne "Failed" && $result ne "Agreed to" && $votexml->findvalue('vote-metadata/vote-question') ne "Election of the Speaker") { 
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
		
		if ($name eq "Smith (OR)" && $YEAR == 1990) { $name = "Smith, Robert (OR)"; }

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

	WriteRoll($fn, $mtime, "house", $ROLL, $datetime, \%votes, $type, $question, $required, $result, $bill, $amendment, "house.gov");
	return 1;
}

sub WriteRoll {
	my $fn = shift;
	my $mtime = shift;
	my $where = shift;
	my $ROLL = shift;
	my $datetime = shift;
	my $rvotes = shift;
	my $TYPE = shift;
	my $QUESTION = shift;
	my $REQUIRED = shift;
	my $RESULT = shift;
	my $BILL = shift;
	my $AMENDMENT = shift;
	my $source = shift;

	if ($ENV{NO_WRITE}) { return; }

	my $SESSION = SessionFromDateTime($datetime);
	my $YEAR = YearFromDateTime($datetime);

	my %votes = %{ $rvotes };

	my $aye = scalar(@{$votes{Aye}}) + scalar(@{$votes{Yea}});
	my $nay = scalar(@{$votes{Nay}}) + scalar(@{$votes{No}});
	my $nv = scalar(@{$votes{'Not Voting'}});
	my $pr = scalar(@{$votes{Present}});
	
	$TYPE =~ s/^\s+//;
	$TYPE =~ s/\s+$//;
	$QUESTION =~ s/^\s+//;
	$QUESTION =~ s/\s+$//;
	($TYPE, $TYPE_CAT) = normalize_vote_type($TYPE, $QUESTION);
	
	$TYPE = htmlify($TYPE);
	$QUESTION = htmlify($QUESTION);
	$REQUIRED = htmlify($REQUIRED);
	$RESULT = htmlify($RESULT);

	$QUESTION =~ s/ +$//;

	`mkdir -p ../data/us/$SESSION/rolls`;

	$mtime = DateToISOString($mtime);

	open ROLL, ">$fn" || die "Couldn't open roll file";
	binmode(ROLL, ":utf8");
	print ROLL "<roll where=\"$where\" session=\"$SESSION\" year=\"$YEAR\" roll=\"$ROLL\" source=\"$source\"\n";
	print ROLL "\tdatetime=\"$datetime\" updated=\"$mtime\"\n";
	print ROLL "\taye=\"$aye\" nay=\"$nay\" nv=\"$nv\" present=\"$pr\">\n";
	print ROLL "\t<category>$TYPE_CAT</category>\n";
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
					my ($state, $dist) = DBSelectFirst(people_roles, [state, district], [DBSpecEQ('personid', $id), DBSpecEQ('type', $where eq 'house' ? 'rep' : 'sen'), PERSON_ROLE_THEN(DateTimeToDBString($datetime))]);
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
	
	my $id;
	if ($fn =~ /\/([hs][\dA-Z]+-\d+)\.xml$/) {
		$id = $1;
	} else {
		die $fn;
	}
	if (!$ENV{NOMAP} && !$SkipMaps) { MakeVoteMap($SESSION, $id); }

	if (defined($BILL)) {
		if (!$ENV{NOBILLS}) {
			push @referencedbills, $BILL;
		}
	} elsif (defined($AMENDMENT)) {
		warn "Amendment without bill reference in $fn";
	}

	IndexVote($SESSION, $id);
	WriteStatus("Vote:$where", "Last fetched: $id");
}

################################

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
			MakeVoteMap($session, $f);
		}
	}
	closedir D;
	
	DBClose();
}

sub MakeVoteMap {
	my $session = shift;
	my $votefile = shift;

	if ($session < 109) { return; }

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

	my $when = DateTimeToDBString($votexml->getAttribute("datetime"));
	my $PERSON_ROLE_NOW = "(startdate <= '$when' and enddate >= '$when')";
	
	# CORRELATION WITH PARTY
	
	my %votebreakdown;
	
	if (!defined($PersonPoliticalParties{LOADED})) {
		$PersonPoliticalParties{LOADED} = 1;
		my @parties = DBSelect(people_roles, [personid, party], [$PERSON_ROLE_NOW]);
		foreach my $p (@parties) {
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
	
	eval("LoadDistricts${session}()");
	if ($@) { die $@; }

	for my $size ('large', 'small') {
	for my $imgmode ('geo', 'carto') {
	
	my $scale = 2;

	my $im = new GD::Image($size eq 'large' ? 400*$scale : 220*$scale, $size eq 'large' ? 210*$scale : 118*$scale, 1);
	my $white = $im->colorAllocate(255,255,255);
	my $black = $im->colorAllocate(0,0,0);
	my $grey = $im->colorAllocate(150,150,150);
	my $grey2 = $im->colorAllocate(230,230,230);
	$im->useFontConfig(1);
	$im->filledRectangle(0, 0, $im->width, $im->height, $white);

	my @votecolor = (
		'-' => $im->colorAllocate(200,0,0),
		'+' => $im->colorAllocate(0,0,220),
		'0' => $im->colorAllocate(0,230,230),
		'P' => $im->colorAllocate(0,200,200),
		);
	my %votecolor = @votecolor;
	my @opts = $votexml->findnodes('option');
	for (my $i = 0; $i < scalar(@opts); $i++) {
		my $vk = $opts[$i]->getAttribute('key');
		if (!$votecolor{$vk}) { $votecolor{$vk} = $votecolor[($i % 4) * 2 + 1]; }
	}

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
	foreach my $r (DBSelect(people_roles, [personid, state, district], [DBSpecIn(personid, @voterids), $PERSON_ROLE_NOW, "type = '$reptype'"])) {
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
			if (scalar(@$polys) == 0) { warn "No polygons for $state $dist"; }
			foreach my $poly (@$polys) {
			foreach my $poly2 (@{ SplitPoly(ReducePoly($poly, $imgmode), $sennum) }) {
				push @gdpolys, CreateGDPoly($poly2, $im, $imgmode);
			}
			}
			$DistrictPolys{"$size$imgmode$state$dist$sennum"} = [@gdpolys];
		}
		foreach my $gdpoly (@{ $DistrictPolys{"$size$imgmode$state$dist$sennum"} }) {
			$im->filledPolygon($gdpoly, $votecolor{$vote});
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
				$im->setAntiAliased($grey2);
				$im->openPolygon($gdpoly, GD::gdAntiAliased);
			}
		}
	}

	# scale it back down
	my $im2 = new GD::Image($im->width/$scale, $im->height/$scale, 1);
	$im2->copyResampled($im, 0,0, 0,0, $im2->width, $im2->height, $im->width, $im->height);
	$im = $im2;

	my $fs = 6;
	my $keyx = 10;
	if ($size eq 'small') { $fs = 5; }
	my @bounds2 = GD::Image->stringFT($white, $ttFontName, $fs, 0, 0, $im->height-$fs, "Wp", $ttFontOpts); # ascender, descender
	foreach my $vkn ($votexml->findnodes('option')) {
		my $vk = $vkn->getAttribute('key');
		my $vkt = $vkn->textContent;
		if (!$hadvote{$vk}) { next; }
		my @bounds = GD::Image->stringFT($white, $ttFontName, $fs, 0, $keyx, $im->height-$fs, $vkt, $ttFontOpts);
		$im->filledRectangle($bounds[0]-2, $bounds[5] + $bounds2[1]-$bounds2[5], $bounds[4]+2, $bounds[5]-2, $votecolor{$vk});
		$im->stringFT(($vk ne "0" && $vk ne "P") ? $white : $black, $ttFontName, $fs, 0, $keyx, $im->height-$fs, $vkt, $ttFontOpts);
		$keyx = $bounds[4] + 6;
	}

	if ($size eq 'large' && $imgmode eq 'carto') {
		$im->stringFT($grey, $ttFontName, $fs, 0, 3, $fs+3,
			$reptype eq 'sen' ? "This cartogram shows each state with equal area."
							  : "This cartogram shows congressional districts with equal area.",
			$ttFontOpts);
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

sub normalize_vote_type {
	my ($type, $question) = @_;

	if ($type eq "Call of the House") {
		if ($question eq "Call of the House: QUORUM") {
			return ("Quorum Call", "procedural");
		} else {
			warn "Unhandled vote type: $type: $question";
			return ($type, "procedural");
		}
		
	} elsif ($type eq "On Passage" || $type eq "On Passage of the Bill") {
		return ("On Passage of the Bill", "passage");
	} elsif ($type =~ s/^On (Agreeing to )?(Article \S+ of )?the (Concurrent |Joint )?Resolution(, As Amended)?$/On the $3Resolution/i) {
		if ($2) {
			$type .= " (Part)";
			return ($type, "passage-part");
		}
		return ($type, "passage");
	} elsif ($type =~ /^(On Motion to )?(Concur in|Agree to|On Agreeing to) (the )?Senate (Amendment|amdt|Adt)s?( with an Amendment|with Amendment.*|to House (Amendment|Adt).*)?$|^Concurring|^On Concurring|Concur in (the )?Senate (Amdt|Amendment)|Concur In /i) {
		return ("On the Senate Amendment", "passage");
	} elsif ($type =~ /^(On Motion to )?Suspend ((the )?Rules )?and (Agree|Pass|Concur in the Senate Amendment|Agree to Senate Amendments?|Agree to S Adt to House Adts)(, As Amended)?$/i) {
		return ("On Motion to Suspend the Rules and $4$5", "passage-suspension");
	} elsif ($type =~ s/^(On )?(Agree to |Agreeing to |Motion to Suspend the Rules and Agree to )?the Senate Amendment( with Amendment .*)?$/On the Senate Amendment/) {
		return ($type, "passage");
	} elsif ($type =~ s/^On (Agreeing to |Motion to Suspend the Rules and Agree to )?the Conference Report$/On the Conference Report/) {
		return ($type, "passage");
	} elsif ($type =~ s/^On (Agreeing to )?the Amendments?(, as Modified)?$/On the Amendment/) {
		return ($type, "amendment");
	} elsif ($type =~ s/^On (Agreeing to )?the En Bloc Amendments(, as Modified)?$/On the En Bloc Amendments/) {
		return ($type, "amendment");
	} elsif ($type eq "On the Nomination") {
		return ($type, "nomination");
	} elsif ($type =~ /(On )?Passage( of the Bill)?, (the )?Objections of the President Not ?[Ww]ithstanding/) {
		return ("On Overriding the Veto", "veto-override");
	} elsif ($type =~ /On Overriding the Veto/) {
		return ("On Overriding the Veto", "veto-override");

	# keep these
	} elsif ($type eq "Election of the Speaker") {
		return ($type, "procedural");
	} elsif ($type =~ s/^(On )?Ordering (the )?Previous Question.*/On Ordering the Previous Question/) {
		return ($type, "procedural");
	} elsif ($type =~ s/^((On )?(the )?Motion to )?Table( (the )?(Motion to Reconsider|Appeal|Appeal of the Ruling of the Chair|Amendment|Resolution|Motion to Recommit))?$/On Motion to Table/i) {
		return ($type, "procedural");
	} elsif ($type =~ /^(On )?Motion to Refer( the Resolution)?$/) {
		return ("On Motion to Refer", "procedural");
	} elsif ($type =~ s/^(On Motion to Commit)( with Instructions)?$/$1/ || $type =~ s/(On (the )?Motion to )?Recommit( Conference Report)?( with Instructions)?/On the Motion to Recommit/) {
		return ($type, "procedural");
	} elsif ($type =~ /On (.*)Motion to Instruct Conferees/) {
		return ("On Motion to Instruct Conferees", "procedural");
	} elsif ($type eq "On Approving the Journal") {
		return ($type, "procedural");
	} elsif ($type eq "On the Motion") {
		return ($type, "procedural");
	} elsif ($type eq "Will the House Now Consider the Resolution"
		|| $type =~ /On (Question of )?Consideration of (the )?(Bill|Resolution|Joint Resolution|Conference Report)/) {
		return ("On Question of Consideration", "procedural");
	} elsif ($type eq "On Motion to Adjourn" || $type eq "On the Motion to Adjourn") {
		return ("On the Motion to Adjourn", "procedural");
	} elsif ($type eq "On the Cloture Motion" || $type eq "On Cloture on the Motion to Proceed") {
		return ("On the Cloture Motion", "cloture");
	} elsif ($type eq "On the Motion to Proceed") {
		return ($type, "procedural");
	} elsif ($type =~ /On (the )?Motion to Reconsider/) {
		return ("On the Motion to Reconsider", "procedural");
	} elsif ($type eq "Authorizing Conferees to Close Meetings" || $type eq "On Motion to Authorize Conferees to Close Conference") {
		return ("On Motion to Authorize Conferees to Close Conference", "procedural");
	} elsif ($type =~ /On Motion that the Committee Rise/i) {
		return ($type, "procedural");
	} elsif ($type eq "On the Point of Order") {
		return ($type, "procedural");
	} elsif ($type eq "Sustaining the Ruling of the Chair") {
		return ($type, "procedural");

	} elsif ($type eq "Guilty or Not Guilty") {
		return ($type, "conviction");
	} elsif ($type eq "On the Resolution of Ratification") {
		return ($type, "ratification");
		
	# not sure
	} elsif ($type =~ /^(On Adoption of the )?\S+ (portion of the divided question)(( \[|, ).*)?$/i) {
		return ("On Part of the Divided Question", "other");
		
	} elsif ($type eq "Amendment to Title") {
		return ($type, "other");
	} elsif ($type =~ /^Article \S+$/) {
		return ("Article ___", "other");

	} else {
		warn "Unhandled vote type: $type" if ($type ne "unknown");
		return ($type, "unknown");
	}
}
