#!/usr/bin/perl

# This imports roll call records for congresses earlier than
# the Senate and House themselves put online from data files
# provided by Keith Poole (and others) here:
# http://pooleandrosenthal.com/dwnl.htm
#
# See http://voteview.ucsd.edu/icpsr.htm for notes that their
# ICPSR numbers are not necessarily really ICPSR numbers
# which have some problems, and the differences start especially
# in the 100th Congress onward, and also because they
# assigned two ICPSR numbers of Members who switched parties.
# Also note that party affiliations come from Ken Martis's
# The Historical Atlas of Political Parties in the United States Congress.

require "util.pl";
require "db.pl";
require "parse_rollcall.pl";

%statecodes = (41 => 'AL', 81 => 'AK', 61 => 'AZ', 42 => 'AR', 71 => 'CA',
62 => 'CO', 01 => 'CT', 11 => 'DE', 43 => 'FL', 44 => 'GA', 82 => 'HI',
63 => 'ID', 21 => 'IL', 22 => 'IN', 31 => 'IA', 32 => 'KS', 51 => 'KY',
45 => 'LA', 02 => 'ME', 52 => 'MD', 03 => 'MA', 23 => 'MI', 33 => 'MN',
46 => 'MS', 34 => 'MO', 64 => 'MT', 35 => 'NE', 65 => 'NV', 04 => 'NH',
12 => 'NJ', 66 => 'NM', 13 => 'NY', 47 => 'NC', 36 => 'ND', 24 => 'OH',
53 => 'OK', 72 => 'OR', 14 => 'PA', 05 => 'RI', 48 => 'SC', 37 => 'SD',
54 => 'TN', 49 => 'TX', 67 => 'UT', 06 => 'VT', 40 => 'VA', 73 => 'WA',
56 => 'WV', 25 => 'WI', 68 => 'WY', 55 => 'DC');

%partycodes = (1 => 'Federalist', 9 => 'Jefferson Republican', 10 => 'Anti-Federalist', 11 => 'Jefferson Democrat', 13 => 'Democrat-Republican', 22 => 'Adams', 25 => 'National Republican', 26 => 'Anti Masonic', 29 => 'Whig', 34 => 'Whig and Democrat', 37 => 'Constitutional Unionist', 40 => 'Anti-Democrat and States Rights', 41 => 'Anti-Jackson Democrat', 43 => 'Calhoun Nullifier', 44 => 'Nullifier', 46 => 'States Rights', 48 => 'States Rights Whig', 100 => 'Democrat', 101 => 'Jackson Democrat', 103 => 'Democrat and Anti-Mason', 104 => 'Van Buren Democrat', 105 => 'Conservative Democrat', 108 => 'Anti-Lecompton Democrat', 110 => 'Popular Sovereignty Democrat', 112 => 'Conservative', 114 => 'Readjuster', 117 => 'Readjuster Democrat', 118 => 'Tariff for Revenue Democrat', 119 => 'United Democrat', 200 => 'Republican', 202 => 'Union Conservative', 203 => 'Unconditional Unionist', 206 => 'Unionist', 208 => 'Liberal Republican', 212 => 'United Republican', 213 => 'Progressive Republican', 214 => 'Non-Partisanand  Republican', 215 => 'War Democrat', 300 => 'Free Soil', 301 => 'Free Soil Democrat', 302 => 'Free Soil Whig', 304 => 'Anti-Slavery', 308 => 'Free Soil American and Democrat', 310 => 'American', 326 => 'National Greenbacker', 328 => 'Independent', 329 => 'Ind. Democrat', 331 => 'Ind. Republican', 333 => 'Ind. Republican-Democrat', 336 => 'Anti-Monopolist', 337 => 'Anti-Monopoly Democrat', 340 => 'Populist', 341 => 'People\'s', 347 => 'Prohibitionist', 353 => 'Ind. Silver Republican', 354 => 'Silver Republican', 355 => 'Union', 356 => 'Union Labor', 370 => 'Progressive', 380 => 'Socialist', 401 => 'Fusionist', 402 => 'Liberal', 403 => 'Law and Order', 522 => 'American Labor',  537 => 'Farmer-Labor', 555 => 'Jackson', 603 => 'Ind. Whig', 1060 => 'Silver', 1061 => 'Emancipationist', 1111 => 'Liberty', 1116 => 'Conservative Republican', 1275 => 'Anti-Jackson', 1346 => 'Jackson Republican', 3333 => 'Opposition', 4000 => 'Anti-Administration', 4444 => 'Union', 5000 => 'Pro-Administration', 6000 => 'Crawford Federalist',  6666 => 'Crawford Republican', 7000 => 'Jackson Federalist',  7777 => 'Crawford Republican', 8000 => 'Adams-Clay Federalist',  8888 => 'Adams-Clay Republican');
  
$Months{OCTOBERS} = $Months{OCTOBER};

# This maps second ICPSRs to the first ICPSR in cases where a single
# individual has two IDs because he changed party.
%dualmap = (94602 => 14602, 1449 => 91449, 92484 => 2484, 94891 => 4891, 6738 => 96738, 13033 => 93033, 90618 => 10618, 11043 => 91043, 95122 => 15122, 8500 => 98500, 14454 => 94454, 9369 => 99369, 10634 => 90634, 3769=>15101, 10733=>4035, 94428=>14428, 94628=>14628, 14832=>15126, 95415=>15415, 4804=>94804);

GovDBOpen();

@sessions = (1..101);
if ($ARGV[0] ne "") { @sessions = ($ARGV[0]); }

for $session (@sessions) {
	my $s_start = StartOfSessionYMD($session);
	my $s_end = EndOfSessionYMD($session);

	for $chamber ('sen', 'hou') {
		my %votedb;
	
		my $session2 = $session;
		if ($session2 < 10) { $session2 = "0" . $session; }
	
		# Load in the votes of the individuals.
		my ($content, $mtime) = Download("ftp://voteview.com/dtaord/$chamber${session2}kh.ord");
		if (!$content) { die; }
		for my $repline (split(/[\r\n]+/, $content)) {
			my $icpsr = substr($repline, 3, 5);
			my $statecode = substr($repline, 8, 2);
			my $district = int(substr($repline, 10, 2));
			my $party = int(substr($repline, 20, 3));
			my $name = substr($repline, 25, 11);
			my $votes = substr($repline, 36);
			
			if ($dualmap{int($icpsr)}) { $icpsr = $dualmap{int($icpsr)}; }
			
			if ($statecode == 99) { next; } # president
			my $state = $statecodes{int($statecode)}; if (!$state) { die $statecode; }

			# Correct name mismatches against my database, which in the historical
			# period came mostly from bioguide.
			if ($icpsr == 311) { $name = "Babbitt"; }
			if ($icpsr == 10708) { $name = "Callan"; }
			if ($icpsr == 2036) { $name = "Coombs"; }
			if ($icpsr == 3090) { $name = "Feazel"; }
			if ($icpsr == 14014) { $name = "Froehlich"; }
			if ($icpsr == 4448) { $name = "Hinrichsen"; }
			if ($icpsr == 4906) { $name = "Jeffries"; }
			if ($icpsr == 5596) { $name = "Leidy"; }
			if ($icpsr == 6083) { $name = "Matthews"; }
			if ($icpsr == 6138) { $name = "McCarty"; }
			if ($icpsr == 6201) { $name = "McCulloch"; }
			if ($icpsr == 10811) { $name = "Mechem"; }
			if ($icpsr == 10537) { $name = "Moorehead"; }
			if ($icpsr == 10815) { $name = "Murphy"; }
			if ($icpsr == 7666) { $name = "Quarles"; }
			if ($icpsr == 7918) { $name = "Ritchie"; }
			if ($icpsr == 8386) { $name = "Seymour"; }
			if ($icpsr == 8952) { $name = "Stilwell"; }
			if ($icpsr == 9389) { $name = "Tillman"; }
			if ($icpsr == 6667) { $name = "Morehead"; }
			if ($icpsr == 6899) { $name = "Newnan"; }
			if ($icpsr == 7230) { $name = "Paterson"; }
			if ($icpsr == 7308) { $name = "Peirce"; }
			if ($icpsr == 8467) { $name = "Shields"; }
			if ($icpsr == 8449) { $name = "Sheredine"; }
			if ($icpsr == 9268) { $name = "Thatcher"; }
			if ($icpsr == 9376) { $name = "Tibbits"; }
			if ($icpsr == 10409) { $name = "Yancey"; }
			
			# Chop off everything after the first space or comma in the
			# name to get just the last name. Then escape it from MySQL.
			$lastname = $name;
			$lastname =~ s/[, ].*//;
			$lastname =~ s/\\/\\\\/g;
			$lastname =~ s/'/\\'/g;
			
			my $type;
			if ($district >= 98) { $district = -1; }
			my $district_db;
			if ($chamber eq 'hou') {
				$type = 'rep';
				if ($district == 1) { # district might be unknown by us, so allow -1 into the database
					$district_db = "IN(-1, 0, 1)"; # at-large coded as 1
				} else {
					$district_db = "IN(-1 , " . int($district) . ")";
				}
			} else {
				$type = 'sen';
				$district_db = "IS NULL";
			}
			
			#print "$statecode-$district-$votes\n";

			my @pids = DBSelectVector("people", ["id"], ["icpsrid = $icpsr"]);
			
			if (scalar(@pids) == 0) {
				# We add a false premise here that individuals have a
				# single ICPSR whereas in fact if they changed parties
				# they may get two. That could mess up how we assign
				# ICPSRs in case of ambiguity like father/son cases.
				@pids = DBSelectVector(
					"people_roles LEFT JOIN people ON personid=id",
					["personid"],
					["replace(lastname, ' ', '') LIKE '$lastname%' and type='$type' and state='$state' and district $district_db and startdate <= '$s_end' and enddate >= '$s_start' and icpsrid IS NULL"]);
			}
				
			if ($chamber eq 'hou' && scalar(@pids) == 0) {
				# Try relaxing by not including district filter
				# and hoping the last name and state alone are enough.
				@pids = DBSelectVector(
					"people_roles LEFT JOIN people ON personid=id",
					["personid"],
					["lastname LIKE '$lastname%' and type='$type' and state='$state' and startdate <= '$s_end' and enddate >= '$s_start' and icpsrid IS NULL"]);
			}
				
			if (scalar(@pids) != 1) {
				print "$name " . scalar(@pids) . " $state $district $icpsr $s_start\n";
				$votedb{"XXX$icpsr"} = $votes;
			} else {
				# Update person's ICPSR code.
				my $pid = $pids[0];
				DBUpdate(people, ["id=$pid"], icpsrid => $icpsr);
				$votedb{$pid} = $votes;
				
				# Update role party and district number.
				if ($chamber eq 'hou') {
					DBUpdate("people_roles",
						["personid=$pid and type='$type' and state='$state' and district=-1 and startdate <= '$s_end' and enddate >= '$s_start'"],
						district => $district);
				}
				if ($partycodes{$party}) {
					DBUpdate("people_roles",
						["personid=$pid and type='$type' and state='$state' and startdate <= '$s_end' and enddate >= '$s_start'"],
						party => $partycodes{$party});
				}
			}
		}
		
		# Go vote by vote...
		my $chamber2 = substr($chamber, 0, 1);
		my $chamber3 = $chamber2;
		if ($chamber3 eq 'h') { $chamber3 = ''; }
		($content, $mtime) = Download("ftp://voteview.com/dtl/$session$chamber3.dtl");
		if (!$content) { die; }
		my $voteno;
		my $votedate;
		my $votedescr;
		my $lastvotedate;
		my $relatedbill;
		for my $voteline (split(/[\r\n]+/, $content)) {
			my ($roll, $lineno, $descr) = ($1, $2, $3);
			if ($chamber eq 'hou') {
				if ($voteline !~ /^([ \d]...)(..) (.*?)\s*$/) { die $voteline; }
				($roll, $lineno, $descr) = (int($1), int($2), $3);
			} else {
				# not sure what the second column is. it's another ordering.
				if ($voteline !~ /^(....) (....)(..)\s(.*?)\s*$/) { die $voteline; }
				($roll, $lineno, $descr, $altno) = (int($1), int($3), $4, int($2));
			}
			if ($lineno == 1) {
				if (defined($votedate)) { WriteOldRoll($session, $chamber2, $voteno, $votedate, $votedescr, $relatedbill, \%votedb, $mtime); }
				$lastvotedate = $votedate;
				undef $votedate;
				undef $relatedbill;
				
				# CORRECT APPARENT DATA ERRORS
				if ($descr eq "A-3- -651     J 2-2-490      HR        DEC. 19, 1793") { $descr = "A-3- -651     J 2-2-490      HR        FEB. 19, 1793"; }
				if ($descr eq "DCR 113-192-H1               S1003     NOV. 27, 1963") { $descr = "DCR 113-192-H1               S1003     NOV. 27, 1967"; }
				if ($descr eq "DCR 115-100-S6705            HR11400   JUNE 18, 1967") { $descr = "DCR 115-100-S6705            HR11400   JUNE 18, 1969"; }
				if ($descr eq "DCR 115-100-S6711            HR11400   JUNE 18, 1967") { $descr = "DCR 115-100-S6711            HR11400   JUNE 18, 1969"; }
				if ($descr eq "DCR-113-8334                           JULY 24, 1980") { $descr = "DCR-113-8334                           JULY 24, 1981"; }
				if ($descr eq "DCR-1-20                     HRES5     JAN. 5, 1980") { $descr = "DCR-1-20                     HRES5     JAN. 5, 1981"; }
				if ($descr eq "DCR-158-16187                          NOVEMBER 25, 1983") { $descr = "DCR-158-16187                          NOVEMBER 15, 1983"; }
				if ($descr eq "DCR-135-14581                          OCTOBER 12, 1981") { $descr = "DCR-135-14581                          OCTOBER 12, 1984"; }
				if ($descr =~ "              DCR-132-50(21|34|47|51|57|68)             JULY 30, 1987") { $descr = "              DCR-132-5021             JULY 30, 1986"; }
				if ($descr eq "DCR 123-139-14510            43e       SEPTEMBER 9,1 977") { $descr = "DCR 123-139-14510            43e       SEPTEMBER 9, 1977"; }
				if ($descr eq "A-2- -2024    J 1-3-391      HR110     FEB. 29, 1791") { $descr = "A-2- -2024    J 1-3-391      HR110     FEB. 28, 1791"; }
				if ($descr eq "CR-8-3-2091   J 45-3-429A    HR6471    FEB. 29, 1879") { $descr = "CR-8-3-2091   J 45-3-429A    HR6471    FEB. 28, 1879"; }
				if ($descr eq "CR-27-4-2944  J 53-3-169     HR4658    FEB. 29, 1895") { $descr = "CR-27-4-2944  J 53-3-169     HR4658    FEB. 28, 1895"; }
				if ($descr eq "A-5- -1496    J -1-594       HR        MAY 31, 1797") { $descr = "A-5- -1496    J -1-594       HR        MAY 31, 1796"; }
				if ($descr eq "A-15- -1066   J 9-1-394      HR134     APR. 17, 1809") { $descr = "A-15- -1066   J 9-1-394      HR134     APR. 17, 1806"; }
				if ($descr eq "A-12- -366    J 7-2-280      HRE       JAN9 11, 1803        134") { $descr = "A-12- -366    J 7-2-280      HRE       JAN 11, 1803        134"; }
				if ($descr eq "A-17- -1219B  J 10-1-317     S1A       DEC. 21, 1907") { $descr = "A-17- -1219B  J 10-1-317     S1A       DEC. 21, 1807"; }
				if ($descr eq "A-19- -1595A  J 10-SUPP-59   HRE       NOV. 23, 1808") { $descr = "A-19- -1595A  J 10-SUPP-59   HRE       NOV. 23, 1809"; }
				if ($descr eq "A-19- -1595B  J 10-SUPP-59   HRE       NOV. 23, 1808") { $descr = "A-19- -1595B  J 10-SUPP-59   HRE       NOV. 23, 1809"; }
				if ($descr eq "A-19- -1597A  J 10-SUPP-60   HRE       NOV. 24, 1808") { $descr = "A-19- -1597A  J 10-SUPP-60   HRE       NOV. 24, 1809"; }
				if ($descr eq "A-19- -1597B  J 10-SUPP-60   HRE       NOV. 24, 1808") { $descr = "A-19- -1597B  J 10-SUPP-60   HRE       NOV. 24, 1809"; }
				
				if ($descr !~ /\s+([A-Z]+)\.?\s+(\d+) ?,?\s*(\d\d\d\d)(\s+\d{1,3})?\s*$/) { warn "$session $chamber: \"$descr\""; next; }
				my ($m, $d, $y) = ($1, $2, $3); # not sure what that last digit field is in 7hou
				if ($Months{$m} == 0 || $d == 0 || $y == 0 || $d > 31) { warn $descr; next; }
				$voteno = $roll;
				if ($d == 210) { $d = 10; } # data bug, invalid value, best guess
				$votedate = sprintf("%04d-%02d-%02d", $y, $Months{$m}, $d);
				$votedescr = '';
				
				$relatedbill = substr($descr, 29, 8);
				if ($relatedbill eq "        ") {
					undef $relatedbill;
				} elsif ($relatedbill =~ /^(HR|HRES?|HJR(ES)?|HCR(ES)?|S|SRES?|SJR(ES)?|SCR(ES)?)(\d+)\s*$/) {
					my %typcode = (HR=>h, HRE=>hr, HJR=>hj, HCR=>hc, S=>'s', SRE=>sr, SJR=>sj, SCR=>sc);
					$relatedbill = [$session, $typcode{$1}, $6]
				} else {
					print "$relatedbill\n";
					undef $relatedbill;
				}
	
				eval {
					if (SessionFromDateTime($votedate) != $session) { die "Session mismatch: $descr"; }
				};
				if ($@) {
					warn "Vote date did not occur during a session: $descr. Last vote was $lastvotedate. In $session $chamber.";
					undef $votedate;
					next;
				}
			} elsif ($descr =~ /Y=\d+ N=\d+/) {
			} else {
				$votedescr .= "$descr ";
			}
		}
		if (defined($votedate)) { WriteOldRoll($session, $chamber2, $voteno, $votedate, $votedescr, $relatedbill, \%votedb, $mtime); }
	}

}

DBClose();

sub WriteOldRoll {
	my ($session, $chamber, $roll, $date, $descr, $relatedbill, $db, $mtime) = @_;

	$descr =~ s/\s+$//;
	$descr =~ s/ \s/ /g;
	$descr =~ s/A 'YEA' VOTE IS CODED '1' AND A 'NAY' VOTE IS CODED '6'\.//;
	
	my $year = YearFromDateTime($date);
	my $subsession = SubSessionFromDateTime($date);
	if (!$subsession) { warn "No subsession for $date"; return; }
	
	my %votes;
	for my $pid (keys(%{$db})) {
		my $v = substr($$db{$pid}, $roll-1, 1);
		if ($v == 1) { $v = 'Aye'; }
		elsif ($v == 6) { $v = 'Nay'; }
		elsif ($v == 7 || $v == 8) { $v = 'Present'; }
		elsif ($v == 9) { $v = 'Not Voting'; }
		elsif ($v == 0) { next; } # person not a member for this vote
		elsif ($v == 3 || $v == 4) { $v = 'Not Voting'; } # announced doesn't count??
		elsif ($v == 2 || $v == 5) { next; } # paired aye/nay doesn't count
		else { die "Invalid vote type $v in roll $roll session $session pid $pid $descr"; }
		if (substr($pid, 0, 3) eq 'XXX') { $pid = 0; }
		push @{$votes{$v}}, $pid;
	}
	
	# Don't overwrite files we get from Senate.gov/House.gov.
	if ($year >= 1989 && $chamber eq 's') { return; }
	if ($year >= 1990) { return; }
	
	my $fn = "../data/us/$session/rolls/$chamber$subsession-$roll.xml";
	#if (-e $fn ) { return; }
	
	print "$fn\n";
	
	#print "$session $chamber $roll $date\n";
	
	my $votetype = 'unknown';
	my $required = 'unknown';
	my $result = 'unknown';
	
	if ($descr =~ s/\s*\(MOTION (PASSED|FAILED)(;3\/5 REQUIRED)?\)//) {
		if ($1 eq "PASSED") { $result = "Passed"; }
		if ($1 eq "FAILED") { $result = "Failed"; }
		$required = "1/2";
		if ($2) { $required = "3/5"; }
	}
	
	WriteRoll($fn, $mtime, $chamber eq 's' ? "senate" : "house", $roll, $date, \%votes, $votetype, $descr, $required, $result, $relatedbill, undef, "keithpoole")
}
