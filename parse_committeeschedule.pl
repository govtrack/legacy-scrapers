#!/usr/bin/perl

use LWP::UserAgent;
use Time::Local;

require "general.pl";
require "update_by_digest.pl";

my $months = join("|", keys(%Months));

if ($ARGV[0] eq "COMMITTEESCHEDULE") {
	GovDBOpen();
	FetchCommitteeSchedule();
	DBClose();
}

1;

sub FetchCommitteeSchedule {
	my $SESSION = SessionFromDate(time);
	
	my $committeedata = $XMLPARSER->parse_file("../data/us/$SESSION/committees.xml");
	foreach my $n ($committeedata->findnodes("committees/committee/thomas-names/name[\@session=$SESSION]")) {
		$CommitteeId{$n->textContent} = $n->parentNode->parentNode->getAttribute('code');
	}
	$CommitteeId{'Joint Economic Committee'} = 'JSEC';

	my $sfile = "../data/us/$SESSION/committeeschedule.xml";

	my $xml;
	if (!-e $sfile) {
		$xml = $XMLPARSER->parse_string('<committee-schedule/>');
	} else {
		my $parser = XML::LibXML->new();
		$parser->keep_blanks(0);
		$xml = $parser->parse_file($sfile);
	}

	FetchSenateCommitteeSchedule($xml);
	FetchHouseCommitteeSchedule($xml);

	$xml->toFile($sfile, 1);
}

sub ClearChamberCommitteeMeetings {
	my $xml = shift;
	my $where = shift;
	foreach my $node ($xml->findnodes('committee-schedule/meeting[@where="' . $where . '"]')) {
		$node->parentNode->removeChild($node);
	}
}

sub FetchHouseCommitteeSchedule {
	my $xml = shift;

	my ($content, $mtime) = Download("http://thomas.loc.gov/cgi-bin/dailydigest", nocache => 1);
	if (!$content) { return; }

	$content =~ s/:\n/: /g;

	my @lines = split(/[\n\r]+/, $content);
	my $mode = 0;
	my $cmte;
	my $year;
	foreach my $line (@lines) {
		if ($line =~ /Week of [\w\W]+ (\d\d\d\d)</) { $year = $1; }
	
		if ($line =~ /CONGRESSIONAL PROGRAM AHEAD/) {
			ClearChamberCommitteeMeetings($xml, 'h');
			$mode = 1;
			next;
		}
		if ($mode == 0) { next; }
		
		if ($line =~ /<strong>House/) { $mode = 2; next; }
		if ($mode == 1) { next; }
		
		#if ($line =~ /<center><strong>/) { last; }
		if ($line =~ /Next Meeting/) { last; }
		
		if ($line =~ /<em>Committee on (the )?([\w\W]+?)(,|:)?<\/em>/) {
			$cmte = $2;
		}
		
		$line =~ s/, \s+ Rayburn.$//;
		$line =~ s/, \w-\s+ Capitol.$//;
		
		if ($cmte ne "" && $line =~ s/^(, |<br><p>)($months) (\d+), //i) {
			my $month = $Months{uc($2)};
			my $day = $3;
			while ($line =~ /(, |, and )?([\w\W]*?), (\d+(:\d+)? (a|p)\.m\.)/g) {
				my $desc = $2;
				my $tme = $3;
				my $hour = 9;
				my $min = 0;
				if ($tme =~ /^(\d+)(:(\d+))?/) {
					$hour = $1;
					$min = $3;
					if ($hour != 12 && $tme =~ /p\.m\./) { $hour += 12; }
				}
				my $date = timelocal(0,$min,$hour, $day, $month-1, $year);
				$desc =~ s/<[\w\W]+?>//g;
				$desc =~ s/^(\w)/uc($1)/e;
				AddCommittee($date, $tme, "House $cmte", undef, $desc, "h", $xml);
			}
		}
	}
}

sub FetchSenateCommitteeSchedule_Old {
	# This uses the HTML meeting listing. It was used
	# before an XML feed appeared.

	my $xml = shift;

	ClearChamberCommitteeMeetings($xml, 's');

	my $URL = "http://www.senate.gov/pagelayout/committees/b_three_sections_with_teasers/committee_hearings.htm";
	my ($content, $mtime) = Download($URL);
	if (!$content) { return; }
	
	my $mode = 0;
	my ($mon, $day, $year);
	foreach my $line (split(/[\n\r]+/, $content)) {
		if ($line =~ /<b>(Monday|Tuesday|Wednesday|Thursday|Friday), (\w+)\.? (\d+), (\d+)<\/b>/i) {
			($mon, $day, $year) = ($2, $3, $4);
			$mon = uc($mon);
			if (!defined($Months{$mon})) { die "Unknown month: $mon"; }
			$mode = 1;
			next;
		}
		
		if ($mode == 1 && $line =~ /(\d+)(:(\d+))? (a\.m\.|p\.m\.)/) {
			my $h = $1;
			my $m = $3;
			my $ap = $4;
			if ($ap eq "p.m." && $h != 12) { $h += 12; }
			$date = timelocal(0,$m,$h, $day, $Months{$mon}-1, $year);
			$time = $line;
			$mode = 2;
			next;
		}
		
		if ($mode == 2) {
			$committee = $line;
			$committee =~ s/<\/?B>//g;
			$committee =~ s/^\s+//g;
			$committee =~ s/\s*,?\s*$//g;
			if ($committee !~ /^Joint /) {
				$committee = "Senate $committee";
			}
			$subcommittee = "";
			$topic = "";
			$mode = 3;
			next;
		}
		
		if ($mode == 3 && $line =~ /^    \w/) {
			$subcommittee .= $line . " ";
		} elsif ($mode == 3 && $line =~ /^         \w/) {
			$topic .= $line . " ";
		} elsif ($mode == 3 && $line =~ /^              \s+(\w\S+)$/) {
			$topic .= " [$1]";
		} elsif ($mode == 3 && $line =~ /^\s+$/) {
			$subcommittee =~ s/^\s+|\s+$//g;
			$subcommittee =~ s/  / /g;
			$subcommittee =~ s/ Subcommittee$//g;

			$topic =~ s/^\s+|\s+$//g;
			$topic =~ s/\s{2,}/ /g;

			AddCommittee($date, $time, $committee, $subcommittee, $topic, "s", $xml);
			$mode = 1;
		}
	}
}

sub FetchSenateCommitteeSchedule {
	my $xml = shift;

	ClearChamberCommitteeMeetings($xml, 's');

	my $URL = "http://www.senate.gov/general/committee_schedules/hearings.xml";
	my ($content, $mtime) = Download($URL);
	if (!$content) { return; }
	
	my $doc = $XMLPARSER->parse_string($content);
	for my $n ($doc->findnodes('css_meetings_scheduled/meeting[not(cmte_code="")]')) {
		my $committee = $n->findvalue('committee[position()=1]');
		my $subcommittee = $n->findvalue('sub_cmte[position()=1]');
		my $date = $n->findvalue('date');
		my $time = $n->findvalue('time');
		my $room = $n->findvalue('room');
		my $topic = $n->findvalue('matter');
		my @topics;
		for my $m ($n->findnodes('document')) {
			push @topics, $m->textContent;
		}
		
		if ($date !~ /(\d\d?)-($months)-(\d\d\d\d) (\d\d?):(\d\d) (AM|PM)/) {
			die "Invalid date: $date";
		}
		my ($day, $mon, $year, $hour, $him, $ap) = ($1, $2, $3, $4, $5, $6);
		if (!defined($Months{$mon})) { die "Unknown month: $mon"; }
		if ($ap eq "p.m." && $h != 12) { $h += 12; }
		elsif ($ap eq "a.m." && $h == 12) { $h = 0; }
		$date = timelocal(0,$min,$hour, $day, $Months{$mon}-1, $year);
	
		$committee =~ s/^\s+//g;
		$committee =~ s/\s*,?\s*$//g;
		if ($committee !~ /^Joint /) {
			$committee = "Senate $committee";
		}
		
		$topic =~ s/^\s+|\s+$//g;
		$topic =~ s/\s{2,}/ /g;

		AddCommittee($date, $time, $committee, $subcommittee, $topic, "s", $xml, join("|", @topics));
	}
}

sub AddCommittee {
	my ($date, $time, $comm, $sub, $topic, $where, $xml, $docstring) = @_;

	$comm =~ s/^Senate Intelligence/Senate Intelligence (Select)/;
	$comm =~ s/ \s+/ /g;
	$sub =~ s/ \s+/ /g;
	
	my $cid = $CommitteeId{$comm};
	if (!defined($cid)) {
		$cid = $CommitteeId{"$comm (Special)"};
	}
	
	if (!defined($cid)) {
		print " parse_committeeschedule: unknown committee $comm\n";
	} elsif ($sub ne "") {
		my ($scid) = DBSelectFirst(committees, [id], [DBSpecEQ(parent, $cid), DBSpecEQ(thomasname, $sub)]);
		print " parse_committeeschedule: unknown subcommittee $comm: $sub\n";
	}
	
	if ($sub ne "") { $comm .= " -- $sub"; }
	$comm = ToUTF8($comm);
	$datestring = ToUTF8($datestring);
	$time = ToUTF8($time);
	$where = ToUTF8($where);
	$topic = ToUTF8($topic);

	my $datestring = DateToString($date);

	my $SESSION = SessionFromDate(time);

	my $node = $xml->createElement('meeting');
	$xml->documentElement->appendChild($node);

	$node->setAttribute("date_string", $datestring);
	$node->setAttribute("time_string", $time);
	$node->setAttribute("datetime", DateToISOString($date));
	$node->setAttribute("where", $where);
	$node->setAttribute("committee", $comm);

	$subj = $xml->createElement('subject');
	$node->appendChild($subj);
	$subj->appendText($topic);
	
	if (!defined($docstring)) { $docstring = $topic; }
	while ($docstring =~ m/($BillPattern)/g) {
		my ($b, $t, $n) = ($1, $2, $3);
		my $s = SessionFromDate($date);
		$t =~ s/ //g;
		$t = $BillTypeMap{lc($t)};
		if (!defined($t)) { die "Unknown bill type: $b"; }

		my $bx = $xml->createElement('bill');
		$node->appendChild($bx);
		$bx->setAttribute('session', $s);
		$bx->setAttribute('type', $t);
		$bx->setAttribute('number', $n);
	}
}
