#!/usr/bin/perl

use LWP::UserAgent;
use Time::Local;

require "util.pl";
require "db.pl";

my $months = join("|", keys(%Months));

if ($ARGV[0] eq "COMMITTEESCHEDULE") {
	GovDBOpen();
	FetchCommitteeSchedule();
	DBClose();
}

1;

sub FetchCommitteeSchedule {
	my $SESSION = SessionFromDateTime(Now());
	
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

		# Scan current entries so if we detect one we already have
		# we can preserve its post date.
		foreach my $node ($xml->findnodes('committee-schedule/meeting')) {
			if ($node->getAttribute('postdate') eq '') {
				$node->setAttribute('postdate', Now());
			} else {
				my $key = $node->getAttribute('datetime') . "|" . $node->getAttribute('where') . "|" . $node->getAttribute('committee') . "|" . $node->findvalue('subject');
				$CommitteeMeetingPostDate{$key} = $node->getAttribute('postdate');
			}
		}
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
		if ($line =~ /Week of [\w\W]+ (\d\d\d\d)\s*</) { $year = $1; }
	
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
		
		if ($line =~ /<em>((Permanent )?Select )?Committee on (the )?([\w\W]+?)(,|:)?<\/em>/) {
			my $typ = $1;
			$typ =~ s/ $//;
			
			$cmte = $4;
			
			if ($typ) { $cmte .= " ($typ)"; }
		}
		
		$line =~ s/, \s+ Rayburn.$//;
		$line =~ s/, \w-\s+ Capitol.$//;
		
		if ($cmte ne "" && $line =~ s/^(, |<br><p>)($months) (\d+), //i) {
			my $month = $2;
			my $day = $3;
			while ($line =~ /(, |, and )?([\w\W]*?), (\d+(:\d+)? (a|p)\.m\.)/g) {
				my $desc = $2;
				my $tme = $3;
				my $date = ParseDateTime("$month $day, $year $tme");
				$desc =~ s/<[\w\W]+?>//g;
				$desc =~ s/^(\w)/uc($1)/e;
				AddCommittee($date, "House $cmte", undef, $desc, "h", $xml);
			}
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
		my $date = ParseDateTime($n->findvalue('date'));
		my $room = $n->findvalue('room');
		my $topic = $n->findvalue('matter');
		my @topics;
		for my $m ($n->findnodes('document')) {
			push @topics, $m->textContent;
		}
	
		$committee =~ s/^\s+//g;
		$committee =~ s/\s*,?\s*$//g;
		if ($committee !~ /^Joint /) {
			$committee = "Senate $committee";
		}
		
		$topic =~ s/^\s+|\s+$//g;
		$topic =~ s/\s{2,}/ /g;
		$topic =~ s/\&quot;/"/g;

		AddCommittee($date, $committee, $subcommittee, $topic, "s", $xml, join("|", @topics));
	}
}

sub AddCommittee {
	my ($date, $comm, $sub, $topic, $where, $xml, $docstring) = @_;

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
	$where = ToUTF8($where);
	$topic = ToUTF8($topic);

	my $node = $xml->createElement('meeting');
	$xml->documentElement->appendChild($node);

	$node->setAttribute("datetime", $date);
	$node->setAttribute("where", $where);
	$node->setAttribute("committee", $comm);

	$subj = $xml->createElement('subject');
	$node->appendChild($subj);
	$subj->appendText($topic);

	my $key = $node->getAttribute('datetime') . "|" . $node->getAttribute('where') . "|" . $node->getAttribute('committee') . "|" . $node->findvalue('subject');
	if ($CommitteeMeetingPostDate{$key}) {
		$node->setAttribute('postdate', $CommitteeMeetingPostDate{$key});
	} else {
		$node->setAttribute('postdate', Now());
	}
	
	if (!defined($docstring)) { $docstring = $topic; }
	while ($docstring =~ m/($BillPattern)/g) {
		my ($b, $t, $n) = ($1, $2, $3);
		my $s = SessionFromDateTime($date);
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
