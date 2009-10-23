#!/usr/bin/perl

# to regenerate all stats:
# for x in {101..111}; do echo $x; perl repstat.pl REPSTATS $x; done

require "general.pl";
require "db.pl";

my %Person;
my $session;
my $outdir;

if ($ARGV[0] eq "REPSTATS" || $ARGV[0] eq "PEOPLEXML") {
	if ($ARGV[1] eq "") { die "Specify session!"; }
	$session = $ARGV[1];
	$outdir = "../data/us/$session/repstats";
	mkdir $outdir;
	GovDBOpen();
	GetPeopleList($session);
	LoadOldData($session);
	GenStats($session) if ($ARGV[0] eq "REPSTATS");
	DBClose();
}

1;

sub DoRepStats {
	$session = shift;
	$outdir = "../data/us/$session/repstats";
	mkdir $outdir;
	GetPeopleList($session);
	LoadOldData($session);
	GenStats($session);
}

sub GetPeopleList {
	my $session = shift;

	# WRITE OUT PERSON DATABASE GENERAL INFO
	my @reps = DBSelect(HASH, people, [id, firstname, middlename, lastnameenc, namemod, nickname, birthday, gender, religion, osid, bioguideid, metavidid, youtubeid], []);

	open PEOPLE_ALL, ">../data/us/people.xml";
	binmode(PEOPLE_ALL, ":utf8");
	print PEOPLE_ALL '<?xml version="1.0" ?>' . "\n";
	print PEOPLE_ALL "<people>\n";

	open PEOPLE_CURRENT, ">../data/us/$session/people.xml";
	binmode(PEOPLE_CURRENT, ":utf8");
	print PEOPLE_CURRENT '<?xml version="1.0" ?>' . "\n";
	print PEOPLE_CURRENT "<people session=\"$session\">\n";
	
	foreach my $rep (@reps) {
		my %rep = %{ $rep };
		foreach my $a (keys(%rep)) {
			my @b = split(/\|/, $rep{$a});
			$rep{$a} = $b[0];
			$rep{$a} = htmlify($rep{$a}, 1);
		}
		if ($rep{firstname} =~ /\.$/ && $rep{middlename} ne "") {
			$rep{firstname} .= " $rep[2]";
			$rep{middlename} = "";
		}

		my @currole = DBSelectFirst(people_roles, [type, state, district, party],
			["personid=$rep{id}",
			 "(type='rep' or type='sen')",
			 "startdate<='" . DateToDBString(EndOfSession($session)) . "'",
			 "enddate>='" . DateToDBString(StartOfSession($session)) . "'",
				 ], "ORDER BY startdate DESC");

		$Person{$rep{id}}{NAME} = "$rep{firstname} $rep{lastnameenc}";

		if (defined($currole[0])) {
			if ($currole[3] =~ /^(.)/) { $currole[3] = $1; } # party first letter
			if ($currole[0] eq "sen") {
				$Person{$rep{id}}{CUR_INFO} = " title='Sen.' state='$currole[1]'";
				$Person{$rep{id}}{NAME} = "Sen. $Person{$rep{id}}{NAME} [$currole[3], $currole[1]]";
			} elsif ($currole[0] eq "rep") {
				$Person{$rep{id}}{CUR_INFO} = " title='Rep.' state='$currole[1]' district='$currole[2]'";
				$Person{$rep{id}}{NAME} = "Rep. $Person{$rep{id}}{NAME} [$currole[3], $currole[1]-$currole[2]]";
			}
		}

		for my $PEOPLE ('PEOPLE_ALL', 'PEOPLE_CURRENT') {
			# If there's no role for this person in this session don't put
			# into current file.
			if ($PEOPLE eq 'PEOPLE_CURRENT' && !defined($currole[0])) { next; }
			
			print $PEOPLE "\t<person id='$rep{id}'";
			print $PEOPLE " lastname='$rep{lastnameenc}'";
			print $PEOPLE " firstname='$rep{firstname}'";
			print $PEOPLE " middlename='$rep{middlename}'" if $rep{middlename} ne "";
			print $PEOPLE " namemod='$rep{namemod}'" if $rep{namemod} ne "";
			print $PEOPLE " nickname='$rep{nickname}'" if $rep{nickname} ne "";
			print $PEOPLE " birthday='$rep{birthday}'" if $rep{birthday} ne "";
			print $PEOPLE " gender='$rep{gender}'" if $rep{gender} ne "";
			print $PEOPLE " religion='$rep{religion}'" if $rep{religion} ne "";
			print $PEOPLE " osid='$rep{osid}'" if $rep{osid} ne "";
			print $PEOPLE " bioguideid='$rep{bioguideid}'" if $rep{bioguideid} ne "";
			print $PEOPLE " metavidid='$rep{metavidid}'" if $rep{metavidid} ne "";
			print $PEOPLE " youtubeid='$rep{youtubeid}'" if $rep{youtubeid} ne "";
			print $PEOPLE " name='$Person{$rep{id}}{NAME}'";
			print $PEOPLE $Person{$rep{id}}{CUR_INFO};
			print $PEOPLE " >\n";

			# For the ALL file put in all roles in ascending order.
			# For the CURRENT file just put in roles this session (could be more than one).
			my @roles = DBSelect(people_roles, [type, startdate, enddate, party, state, district, class, url],
				["personid=$rep{id}",
					($PEOPLE eq 'PEOPLE_CURRENT' ? "startdate<='" . DateToDBString(EndOfSession($session)) . "'" : 1),
					($PEOPLE eq 'PEOPLE_CURRENT' ? "enddate>='" . DateToDBString(StartOfSession($session)) . "'" : 1),
				],
				"ORDER BY startdate");

			foreach my $role (@roles) {
				my @role = @{ $role };
				$role[3] = htmlify($role[3], 1);
				print $PEOPLE "\t\t<role";
				print $PEOPLE " type='$role[0]'";
				print $PEOPLE " startdate='$role[1]'";
				print $PEOPLE " enddate='$role[2]'";
				print $PEOPLE " party='$role[3]'";
				print $PEOPLE " state='$role[4]'";
				print $PEOPLE " district='$role[5]'";
				print $PEOPLE " url='$role[7]'" if $role[7] ne "";
				print $PEOPLE " current='1'" if ($role[1] le DateToDBString(time) && $role[2] ge DateToDBString(time));
				print $PEOPLE " />\n";
			}
		
			# Put current committee assignments into the CURRENT file only.
			if ($PEOPLE eq 'PEOPLE_CURRENT') {
			my @comms = DBSelect(people_committees, [committeeid, role], ["personid=$rep{id}"]);
			foreach my $comm (@comms) {
				my ($cid, $role) = @{ $comm };
				my ($cname, $cparent) = DBSelectFirst(committees, [thomasname, parent], ["id='$cid'"]);
				my $csname = "";
				if ($cparent ne "") {
					$csname = $cname;
					($cname) = DBSelectFirst(committees, [thomasname], ["id='$cparent'"]);
				}
				foreach my $x ($cname, $csname) { $x = htmlify($x, 1); }
				print $PEOPLE "\t\t<committee-assignment";
				print $PEOPLE " committee='$cname'";
				print $PEOPLE " subcommittee='$csname'" if ($csname ne "");
				print $PEOPLE " role='$role'" if ($role ne "");
				print $PEOPLE " />\n";
			}
			}
			
			print $PEOPLE "\t</person>\n";
		}
	}
	print PEOPLE_ALL "</people>\n";
	print PEOPLE_CURRENT "</people>\n";
	close PEOPLE_ALL;
	close PEOPLE_CURRENT;
}

sub GenStats {
	my $session = shift;

	`mkdir -p $outdir`;
	`mkdir -p $outdir.person`;
	
	ScanSpectrum($session);

	# SCAN DATA
	#ScanSpeeches($session);
	ScanVotes($session);
	ScanBills($session);

	# RUN POST PROCESSING
	PostProc();

	# CLEAR THE REPSTAT.PERSON FILES
	my $now = time;
	foreach my $p (keys(%Person)) {
		unlink "$outdir.person/$p.xml";
	}

	# OUTPUT DATA FILES

	%ColumnDescription = (
	NumVote => 'Number of roll call votes this representative cast a ballot, including "no vote," indicating an absense.',
	NoVote => 'Number of roll call votes this representative voted "no vote," indicating an absense.',
	NoVotePct => 'Percent of votes missed by this representative.',
	FirstVoteDate => 'The date of the first vote this representative participated in.',
	NumSponsor => 'Number of bills sponsored by this representative.',
	SponsorIntroduced => 'Number of bills (excluding resolutions) sponsored by this representative that have neither been scheduled for debate nor voted on.',
	SponsorIntroducedPct => 'Percent of bills (excluding resolutions) sponsored by this representative of Congress that have neither been scheduled for debate nor voted on.',
	SponsorEnacted => 'Number of bills (excluding resolutions) sponsored by this representative that have been enacted.',
	NumCosponsor => 'Number of bills (excluding resolutions) cosponsored by this representative.',
	FirstSponsoredDate => 'Introduced date of the first bill (excluding resolutions) sponsored by this representative.',
	LastSponsoredDate => 'Introduced date of the last bill (excluding resolutions) sponsored by this representative.',
	LeaderFollower => 'A leader-follower score.',
	#Speeches => 'Number of debates this representative has risen to say something.',
	#SpeechesWordsCount => 'Number of words total spoken by the representative in counted debates.',
	#WordsPerSpeech => 'Average number of words per debate made by the representative.',
	Spectrum => 'Position on GovTrack\'s Political Spectrum.',
	);

	WriteStat(NoVotePct, 0, novote, NumVote, NoVote, NoVotePct, FirstVoteDate, LastVoteDate);
	WriteStat(SponsorIntroduced, 0, introduced, NumSponsor, SponsorIntroduced, SponsorIntroducedPct, FirstSponsoredDate, LastSponsoredDate);
	WriteStat(SponsorEnacted, 0, enacted, NumSponsor, SponsorEnacted, FirstSponsoredDate, LastSponsoredDate);
	WriteStat(NumCosponsor, 0, cosponsor, NumCosponsor, FirstSponsoredDate, LastSponsoredDate);
	WriteStat(LeaderFollower, 0, leaderfollower, LeaderFollower);
	#WriteStat(Speeches, 0, speeches, Speeches, WordsPerSpeech, SpeechesWordsCount);
	#WriteStat(WordsPerSpeech, 0, verbosity, Speeches, WordsPerSpeech);
	WriteStat(Spectrum, 0, spectrum, Spectrum);

	# COMPLETE THE REPSTAT.PERSON FILES
	foreach my $p (keys(%Person)) {
		if (!-e "$outdir.person/$p.xml") { next; }
		open P, ">>$outdir.person/$p.xml";
		binmode(P, ":utf8");
		print P "</statistics>\n";
		close P;
	}
}

sub Year {
	my $date = shift;
	if ($date !~ /^(\d\d\d\d)-(\d\d)-/) { die $date; }
	my ($year, $mon) = ($1, $2);
	return "$year";
}

sub Quarter {
	my $date = shift;
	if ($date !~ /^(\d\d\d\d)-(\d\d)-/) { die $date; }
	my ($year, $mon) = ($1, $2);
	my $q = int(($mon-1) / 3) + 1;
	return "$year-Q$q";
}

sub IncStat {
	my ($id, $st, $date) = @_;
	$Person{$id}{$st}++;

	if ($date) {
		my $q = Quarter($date);
		$Person{$id}{hist}{$q}{$st}++;
	}
}

sub ScanVotes {
	my $session = shift;
	my $chamber = shift;

	my $datadir = "../data/us/$session/rolls";
	@D = ScanDir($datadir);
	foreach $d (@D) {
		if ($chamber ne "" && $d !~ /^$chamber/) { next; }

		$x = $XMLPARSER->parse_file("$datadir/$d")->documentElement;

		my $votedate = $x->findvalue('@datetime');

		my @voters = $x->findnodes('voter');
		my @votes;

		foreach my $v (@voters) {
			my $id = $v->getAttribute("id");
			my $vote = $v->getAttribute("vote");
			push @votes, [$id, $vote];
		}

		foreach $v (@votes) {
			my $id = $$v[0];
			my $vote = $$v[1];
			if ($id eq "0") { next; }

			$Person{$id}{CURRENT} = 1;

			IncStat($id, NumVote, $votedate);
			if ($vote eq '0') { IncStat($id, NoVote, $votedate); }

			CheckFirstDate($id, $votedate, FirstVoteDate, "$datadir/$d");
			CheckLastDate($id, $votedate, LastVoteDate, "$datadir/$d");
		}
	}
}

sub ScanBills {
	my $session = shift;
	
	# Make a hashtable that counts for each bill sponsor,
	# how many times another rep was a cosponsor, plus
	# a special entry to count total sponsored bills.
	my %FriendTable;
	
	my $datadir = "../data/us/$session/bills";
	@D = ScanDir($datadir);
	foreach $d (@D) {
		my $x = $XMLPARSER->parse_file("$datadir/$d")->documentElement;
		
		# Only look at bills because we can't easily identify resolutions
		# that have reached the end of their life cycle.
		if ($x->findvalue('@type') !~ /^[hs]$/) { next; }
		
		my $sponsor = $x->findvalue('sponsor/@id');
		my $status = $x->findvalue('name(status/*)');
		if ($sponsor eq '' || $status eq "") { next; }
		
		$introdate = $x->findvalue('introduced/@datetime');
		IncStat($sponsor, NumSponsor, $introdate);
		CheckFirstDate($sponsor, $introdate, FirstSponsoredDate, "$datadir/$d");
		CheckLastDate($sponsor, $introdate, LastSponsoredDate, "$datadir/$d");
		$FriendTable{SESSION}{$sponsor}{TOTAL}++;
		$FriendTable{Year($introdate)}{$sponsor}{TOTAL}++;
		
		foreach my $cosp ($x->findnodes('cosponsors/cosponsor')) {
			$cosp = $cosp->getAttribute('id');
			IncStat($cosp, NumCosponsor, $introdate);
			CheckFirstDate($cosp, $introdate, FirstSponsoredDate, "$datadir/$d");
			CheckLastDate($cosp, $introdate, LastSponsoredDate, "$datadir/$d");
			$FriendTable{SESSION}{$sponsor}{$cosp}++;
			$FriendTable{Year($introdate)}{$sponsor}{$cosp}++;
		}

		# If this bill was not enacted, for any identical bills that were
		# enacted, count the sponsor has having gotten the bill enacted.
		# If this bill is in the introduced status but an identical bill
		# is not, then don't count this bill as introduced.
		foreach my $rb ($x->findnodes('relatedbills/bill[@relation="identical"]')) {
			my $rbf = $datadir . "/" . $rb->getAttribute('type') . $rb->getAttribute('number') . ".xml";
			if (!-e $rbf) { next; }
			my $x2 = $XMLPARSER->parse_file($rbf)->documentElement;
			my $status2 = $x2->findvalue('name(status/*)');
			if ($status2 eq "enacted") { $status = 'enacted'; }
			if ($status eq 'introduced' && $status2 ne "introduced") { $status = 'unknown'; }
		}

		if ($status eq "introduced") { IncStat($sponsor, SponsorIntroduced, $introdate); }
		if ($status eq "enacted") { IncStat($sponsor, SponsorEnacted, $introdate); }
	}
	
	# Use the FriendTable to compute some interesting statistics
	# inspired by Joe Barillari.
	for my $period (keys(%FriendTable)) {
		for my $pa (keys(%{ $FriendTable{$period} })) {
			my $avgasym = 0;
			my $avgasym_mass = 0;
			
			my $friends = 0;
			my $friends_mass = 0;
			
			for my $pb (keys(%{ $FriendTable{$period} })) {
				# Note that this loops over only those that sponsored
				# at least one bill.
				
				my $asymmetry = log(($FriendTable{$period}{$pa}{$pb}+1) / ($FriendTable{$period}{$pb}{$pa}+1));
				#print "$FriendTable{$period}{$pa}{$pb} $FriendTable{$period}{$pb}{$pa} $asymmetry\n" if ($pa == 412276);
				
				# Factor by the amount of data we have so we don't
				# place much emphasis on bad data.
				my $w = 1.0;
				if ($FriendTable{$period}{$pb}{TOTAL} < 10) { $w = $FriendTable{$period}{$pb}{TOTAL}/10; }
	
				$avgasym += $asymmetry * $w;
				$avgasym_mass += $w;
				
				$friends += $FriendTable{$period}{$pa}{$pb};
				$friends_mass += 1;
			}
			
			$avgasym /= $avgasym_mass;
			$friends /= $friends_mass;
			
			if ($period eq 'SESSION') {
				$Person{$pa}{LeaderFollower} = $avgasym;
			} else {
				$Person{$pa}{hist}{$period}{LeaderFollower} = $avgasym;
			}
		}
	}
}

sub CheckFirstDate {
	my ($person, $date, $field, $file) = @_;
	if ($date eq "") { warn "Empty date in $file"; }
	if (defined($Person{$person}{$field})
		&& ($Person{$person}{$field} cmp $date) <= 0) { return; }
	$Person{$person}{$field} = $date;
}
sub CheckLastDate {
	my ($person, $date, $field, $file) = @_;
	if ($date eq "") { warn "Empty date in $file"; }
	if (defined($Person{$person}{$field})
		&& ($Person{$person}{$field} cmp $date) >= 0) { return; }
	$Person{$person}{$field} = $date;
}

sub ScanSpeeches {
	my $session = shift;
	my $datadir = "../data/us/$session/index.cr.person";
	@D = ScanDir($datadir);
	foreach $d (@D) {
		my $x = $XMLPARSER->parse_file("$datadir/$d")->documentElement;
		my $ctr = 0;
		my $words = 0;
		foreach my $s ($x->findnodes("*")) {
			$ctr++;
			$words += $s->getAttribute('words');
		}

		$d =~ s/\.xml$//;
		$Person{$d}{Speeches} = $ctr;
		$Person{$d}{SpeechesWordsCount} = $words;
	}
}

sub ScanSpectrum {
	my $session = shift;
	foreach my $hs ('h', 's') {
		open S, "<../data/us/$session/repstats/svd.$hs.txt";
		while (!eof(S)) {
			my $s = <S>; chop $s;
			my ($id, $d1, $d2) = split(/\t/, $s);
			$Person{$id}{Spectrum} = $d2;
		}
		close S;
	}
}

sub LoadOldData {
	my $session = shift;
	my $psession = $session-1;
	foreach my $id (keys(%Person)) {
		my $odf = "../data/us/$psession/repstats.person/$id.xml";
		if (!-e $odf) { next; }
		my $od = $XMLPARSER->parse_file($odf);
		foreach my $st ($od->findnodes('*/*')) {
			foreach my $at ($st->findnodes('@*')) {
				if ($at->nodeName =~ /^stat-/) { next; }
				if ($at->nodeName =~ /Pct$/) { next; }
				if ($at->nodeName =~ /^WordsPerSpeech$/) { next; }
				$Person{$id}{$at->nodeName} = $at->nodeValue;
			}
			foreach my $hs ($st->findnodes('hist-stat')) {
				foreach my $at ($hs->findnodes('@*')) {
					if ($at->nodeName eq 'time') { next; }
					if ($at->nodeName =~ /^stat-/) { next; }
					if ($at->nodeName =~ /Pct$/) { next; }
					if ($at->nodeName =~ /^WordsPerSpeech$/) { next; }
					$Person{$id}{hist}{$hs->getAttribute('time')}{$at->nodeName} = $at->nodeValue;
				}
			}
		}
	}
}

sub PostProc {
	foreach $id (keys(%Person)) {
		# Let's take voting as an indication the person was
		# around in this session. Don't initialize people's stats
		# who weren't even in Congress.
		if (!$Person{$id}{CURRENT}) { next; }

		PostProc2($Person{$id});

		foreach my $q (keys(%{ $Person{$id}{hist} })) {
			PostProc2($Person{$id}{hist}{$q});
		}
	}
}

sub PostProc2 {
	my $P = shift;

	if ($$P{NumVote} > 0) {
		$$P{NoVotePct} = $$P{NoVote} / $$P{NumVote};
	}

	if ($$P{NumSponsor} > 0) {
		$$P{SponsorIntroducedPct} = $$P{SponsorIntroduced} / $$P{NumSponsor};
	}
}

sub WriteStat {
	my $sortkey = shift;
	my $sortorder = shift;
	my $file = shift;
	my @keys = @_;

	# get the ids sorted by the sortkey
	my @ids = sort { $Person{$b}{$sortkey} <=> $Person{$a}{$sortkey} } keys(%Person);
	if ($sortorder) { @ids = reverse(@ids); }
	
	# extract the values, sorted
	my @values;
	foreach my $id (@ids) {
		if (!$Person{$id}{CURRENT} || !defined($Person{$id}{$sortkey})) { next; }
		push @values, $Person{$id}{$sortkey};
	}
	@values = sort({ $a <=> $b } @values);
	
	# record percentiles for each value
	my %pctiles;
	for (my $i = 0; $i < scalar(@values); $i++) {
		# Record the percentile for the first time we see it
		# so that the percentile is for those less-than, but
		# not less-than-or-equal-to, the value.
		if (defined($pctiles{$values[$i]})) { next; }
		$pctiles{$values[$i]} = int($i / scalar(@values) * 1000) / 1000;
	}
	
	# compute the quartiles, roughly
	my $q1 = $values[int(scalar(@values) / 4)];
	my $q3 = $values[int(3 * scalar(@values) / 4)];
	
	# conservatively take out outliers
	while ($values[0] < $q1-($q3-$q1)*2) { shift @values; }
	while ($values[scalar(@values)-1] > $q3+($q3-$q1)*2) { pop @values; }

	# calculate mean, with outliers removed
	my $n = 0;
	my $mean = 0;
	foreach my $v (@values) {
		$mean += $v;
		$n++;
	}
	if ($n == 0) { $n = 1; }
	$mean /= $n;

	# calculate standard deviation, with outliers removed
	my $stddev = 0;
	foreach my $v (@values) {
		$stddev += ($v - $mean) * ($v - $mean);
	}
	$stddev /= $n;
	$stddev = sqrt($stddev);
	
	# When there's no data for a session, don't write any values.
	# If we do, we write e.g. FirstSponsorDate="" and that messes
	# things up later.
	if ($stddev == 0) { return; }
	
	print "$sortkey mean=$mean stddev=$stddev IQR=[$q1, $q3]\n";

	# write out to disk
	my $now = time;
	open STAT, ">$outdir/$file.xml";
	binmode(STAT, ":utf8");
	print STAT "<?xml version=\"1.0\" ?>\n";
	print STAT '<?xml-stylesheet href="stylesheet.xml" type="text/xsl" ?>' . "\n";
	print STAT "<$file key='$sortkey' mean='$mean' stddev='$stddev' generated='$now'";
	foreach my $c (@keys) {
		my $d = $ColumnDescription{$c};
		$d =~ s/\"/\&amp;/g;
		print STAT " $c-Desc=\"$d\"";
	}
	print STAT ">\n";

	my $ctr = 0;
	foreach my $id (@ids) {
		if (!$Person{$id}{CURRENT} || !defined($Person{$id}{$sortkey})) { next; }

		my $zscore;

		if ($stddev == 0) { $zscore = 0; }
		else { $zscore = int( ($Person{$id}{$sortkey} - $mean) / $stddev * 100) / 100; }

		print STAT "<representative id='$id' ";
		print STAT "Name='$Person{$id}{NAME}' ";
		foreach my $key (@keys) {
			my $v = $Person{$id}{$key};
			if (!defined($v)) { $v = 0; }
			print STAT "$key='$v' ";
		}
		print STAT "stat-z='$zscore' ";
		print STAT "stat-pctile='$pctiles{$Person{$id}{$sortkey}}' ";
		print STAT "/>\n";

		if (!-e "$outdir.person/$id.xml") {
			open P, ">$outdir.person/$id.xml";
			binmode(P, ":utf8");
			print P "<statistics session='$session' id='$id' generated='$now'>\n";
			close P;
		}

		open P, ">>$outdir.person/$id.xml";
		binmode(P, ":utf8");
		print P "<$file ";
		foreach my $key (@keys) {
			print P "$key='$Person{$id}{$key}' ";
		}
		print P "stat-mean='$mean' stat-dev='$stddev' stat-z='$zscore'>\n";
		foreach my $q (sort(keys(%{ $Person{$id}{hist} }))) {
			if (!defined($Person{$id}{hist}{$q}{$sortkey})) { next; }
			print P "\t<hist-stat time='$q' ";
			foreach my $key (@keys) {
				if ($key =~ /^(First|Last).*Date$/) { next; }
				my $v = $Person{$id}{hist}{$q}{$key};
				if (!defined($v)) { $v = 0; }
				print P "$key='$v' ";
			}
			print P "/>\n";
		}
		print P "</$file>\n";
		close P;

	}
	print STAT "</$file>\n";
	close STAT;
}


