use Time::Local;
use LWP::UserAgent;
use XML::LibXML;

require "general.pl";
require "persondb.pl";
require "db.pl";

my $debug = 1;

if ($ARGV[0] eq "PARSE_RECORD") { &DoCommandLine; }
if ($ARGV[0] eq "PARSE_RECORD2") { &DoCommandLine2; }

1;

######################

sub DoCommandLine {
	GovDBOpen();
	$ONLYGETRECORDORD = $ARGV[3];
	GetCR($ARGV[1], ParseTime($ARGV[2]));
	DBClose();
}
sub DoCommandLine2 {
	GovDBOpen();
	my ($argm, $y, $skipifexists) = ($ARGV[1], $ARGV[2], $ARGV[3]);
	my ($m1, $m2);
	if (defined($y)) { $m1 = $argm; $m2 = $argm; }
	else { $y = $argm; $m1 = 1; $m2 = 12; }
	for (my $m = $m1; $m <= $m2; $m++) {
	for (my $d = 1; $d <= 31; $d++) {
		my $t = 0;
		eval { $t = ParseTime("$m/$d/$y"); };
		if ($t == 0) { next; }
		GetCR('s', $t, $skipifexists);
		GetCR('h', $t, $skipifexists);
	}
	}
	DBClose();
}

sub GetCR {
	my $WHERE = shift; # s, h
	my $DATE = shift;
	my $skipifexists = shift;
	
	my $session = SessionFromYear(YearFromDate($DATE));
	my $digitdate = DateToDigitString($DATE);

	my $url = "http://thomas.loc.gov/cgi-bin/query/B?r$session:\@FIELD(FLD003+$WHERE)+\@FIELD(DDATE+$digitdate)";
	
	my $content = Download($url);
	if (!$content) { return; }

	print "Fetching Record $WHERE $digitdate\n";
	
	my $fcount = 0;
	while ($content =~ /<b>\s*(\d+)\s*\. <\/b>\s*([^\<\>]+?)\s+-- <a href="([\w\W]+?)">\([\w\s]+ - \w+ \d+, \d+\) <\/a><br/ig) {
		my $ordinal = $1;
		my $section = $2;
		my $sectionurl = $3;

		if (($ONLYGETRECORDORD ne "" && $ONLYGETRECORDORD == $ordinal) || ($ONLYGETRECORDORD eq "" && $ordinal eq "1")) { print "Fetching congressional record $WHERE $session $digitdate\n"; }
		if ($ONLYGETRECORDORD ne "" && $ONLYGETRECORDORD != $ordinal) { next; }

		#print "$ordinal - $section - $sectionurl\n";

		#if ($section ne "TEXT OF AMENDMENTS") { next; }

		$fcount++;
		GetCR2($WHERE, $session, $digitdate, $DATE, $ordinal, $section, $sectionurl, $skipifexists);
	}
	
	print "$fcount Pages Fetched\n";
}

sub MapBillType {
	my $x;
	($x = lc($_[0])) =~ s/ //g;
	if (!defined($BillTypeMap{$x})) { warn "Bill type not in map: " . $x; }
	return $BillTypeMap{$x};
}

sub GetCR2 {
	my $WHERE = shift;
	my $SESSION = shift;
	my $DIGITDATE = shift;
	my $DATE = shift;
	my $ORDINAL = shift;
	my $TITLE = shift;
	my $URL = shift;
	my $skipifexists = shift;
	
	my $fn = "../data/us/$SESSION/cr/$WHERE$DIGITDATE-$ORDINAL.xml";
	if ($skipifexists && -e $fn) { return; }
	`mkdir -p ../data/us/$SESSION/cr`;

	# First Page

	my $content = Download("http://thomas.loc.gov$URL");
	if (!$content) { return; }
	
	if ($content !~ /<a href="([^\"]+?)"><em>Printer Friendly Display<\/em><\/a>/i) {
		die "Congressional record has no printer friendly page at $url";
	}
	
	$URL = $1;
	
	# GET PRINTER FRIENDLY PAGE
	
	my $content = Download("http://thomas.loc.gov$URL");
	if (!$content) { return; }

	$content =~ s/<center><pre>\[Page\: [HS]\d+\]<\/pre><\/center>[\n\r]//g;
	$content =~ s/<center><pre>\[Time\: [\d\:]+\]<\/pre><\/center>[\n\r]//g;

	if ($TITLE =~ "TEXT OF AMENDMENTS") {
		TextOfAmendments($content, $SESSION, $WHERE, $DATE);
		return;
	}
	
	$content =~ s/(<p>\&nbsp;\&nbsp;\&nbsp;[^\n\r]*)(<p>\&nbsp;\&nbsp;\&nbsp;)/$1\n$2/g;
	$content =~ s/(<p>\&nbsp;\&nbsp;\&nbsp;[^\n\r]+)[\n\r]+(<p>\&nbsp;\&nbsp;\&nbsp;)([a-z])/$1 $3/g;
	$content =~ s/(<p>\&nbsp;\&nbsp;\&nbsp;[^\n\r]+)[\n\r]+(\w)/$1 $2/g;

	my @contentlines = split(/[\n\r]+/, $content);

	my $speakertitle;
	my $speakername;
	my $speaking = -1;
	my $lastspoke = -1;
	my $lastspokes = undef;
	my $ofwhere;
	my $spokencount = 0;
	my $topic = undef;
	my $nextlineisbill = "";

	my $repnameregex = "(Mr\\.|Ms\\.|Mrs\\.|Dr\\.|Senator) ((De|La|Mc|Mac)?[A-ZÀ-ÿ\\-'\\. ]+)( (of) ($StateNamesString))?";
	
	my $X = $XMLPARSER->parse_string("<record/>");
	
	$TITLE =~ s/\n//g;

	$X->documentElement->setAttribute('where', $WHERE);
	$X->documentElement->setAttribute('when', $DATE);
	$X->documentElement->setAttribute('ordinal', $ORDINAL);
	$X->documentElement->setAttribute('title', ToUTF8($TITLE, 1));
	
	my $curnode;

	foreach my $line (@contentlines) {
		if ($line !~ s/^<p>\&nbsp;\&nbsp;\&nbsp;//
			& $line !~ s/^<center>(.*)<\/center>/$1/
			) { next; }

		$line =~ s/\s+$//g;
		$line =~ s/<(b|em)>([\w\W]+?)<\/(b|em)>/$2/gi;
		
		if ($nextlineisbill == 1) {
			$topic = "Introducing $line";
			if ($line =~ /(^)($BillPattern)/) {
				$nextlineisbill = "[Introducing <bill type=\"" . MapBillType($3) . "\" number=\"$4\">$2</bill>] ";
				next;
			}
			undef $nextlineisbill;
		}

		$line =~ s/(^|\s|\()($BillPattern)/"$1<bill type=\"" . MapBillType($3) . "\" number=\"$4\">$2<\/bill>"/egi;
		
		#print "> $line\n";
		
		#$line =~ s/^(Mr\.|Ms\.|Mrs\.|Dr\.)([A-Z ]+) OF (\w+\. )/$1 of $2/;

		if ($line =~ /^ANNOUNCEMENT BY THE (SPEAKER|CHAIRMAN) PRO TEMPORE|^RECORDED VOTE/) {
			next;
		} elsif ($line !~ /[a-z]/ && $line !~ /[,:]\s*$/ && $line =~ /^[A-Z]/) {
			# no lowercase letters indicates metatext
			# except this-is-a-bill-heading giveaways
			if ($line =~ /^SEC\.|^TITLE\./) { next; }
			$topic = $line;
			if ($topic =~ /^AMENDMENTS? |GENERAL LEAVE/) { $topic = undef; }
			next;
		} elsif ($line =~ /^The clerk |^The question was taken\.$|^A recorded vote was ordered\.$|^The yeas and nays were ordered\.$|The yeas and nays resulted--|^The result was announced\-\-|^There being no objection, |^The form of the motion is as follows:|^The motion to .* was .*\.$|^The legislative clerk read as follows:$|The PRESIDING OFFICER laid before the Senate the following message:$/i) {
			$speaking = -1;
		} elsif ($line =~ /^By $repnameregex( of [\w ]+)?( \(for (himself, )?[\w\W]+\))?:\s*$/) {
			$nextlineisbill = 1;
			next;

		} elsif ($line =~ /^$repnameregex( of [\w ]+)?( \(for (himself, )?[\w\W]+\))? submitted the following / ) {
			$speaking = -1;

		} elsif ($line =~ /^\([\w\W]+\)\s*$/i) {
			$speaking = -1;
		} elsif ($line =~ s/^The PRESIDENT\.\s+//) {
			$speaking = 0;
			$speakertitle = "";
			$speakername = "The President";
			$ofwhere = "";
		} elsif ($line =~ s/^The VICE PRESIDENT\.\s+//) {
			$speaking = 0;
			$speakertitle = "";
			$speakername = "The Vice President";
			$ofwhere = "";
		} elsif ($line =~ s/^\s?(The|THE|Mr\.|Ms\.|Mrs\.|Dr\.) (ACTING |Acting )?(PRESIDENT|SPEAKER|PRESIDING OFFICER|CHAIRMAN)( pro tempore)?( \([\w\W]+\))?\.//) {
			$speaking = -2;	
		#} elsif ($line =~ s/^(Mr\.|Ms\.|Mrs\.|Dr\.) ((De|La|Mc|Mac)?[A-ZÀ-ÿ\-'\. ]+)( (of) ([\w ]+))?\.\s+//) {
		} elsif ($line =~ s/^[ ]{0,2}$repnameregex\.\s+//) {
			$speakertitle = $1;
			$speakername = $2;
			$ofwhere = $6;
			if ($speakername =~ /^(.+) ([\w\W]+)$/ && $1 ne "VAN") {
				$speakername = "$2, $1";
			}

			$speakertype = $WHERE eq "s" ? "sen" : "rep";
			if ($speakertitle eq "Senator") { $speakertype = "sen"; }
			
			$speakergender = undef;
			if ($speakertitle eq "Mr.") { $speakergender = "m"; }
			if ($speakertitle eq "Mrs." || $speakertitle eq "Ms.") { $speakergender = "f"; }

			$speaking = PersonDBGetID(
				title => $speakertype,
				name => $speakername,
				state => $StatePrefix{uc($ofwhere)}, 
				when => $DATE,
				gender => $speakergender);
			if (!defined($speaking)) { $speaking = 0; print "Unknown person in #$ORDINAL: $speakertitle $speakername of '$ofwhere'\n"; }

			$line = "$nextlineisbill$line";
			$nextlineisbill = "";
		}
		
		$line =~ s///g; # hard line breaks?
		
		if ($lastspoke != $speaking && $lastspoke > 0) {
			# "</speaking>\n";
		} elsif (($lastspoke != $speaking || $lastspokes ne "$speakertitle$speakername$ofwhere") && $lastspoke == 0) {
			# "</speaking-unknown-id>\n";
			$lastspokes = "";
		}

		if ($speaking > 0) {
			if ($lastspoke != $speaking) {
				$curnode = $X->createElement('speaking');
				$curnode->setAttribute('speaker', $speaking);
				$curnode->setAttribute('topic', ToUTF8($topic, 1));
				$X->documentElement->appendChild($curnode);
			}
			AddNode($curnode, "paragraph", $line);
			$spokencount++;
		} elsif ($speaking == 0) {
			if ($lastspokes ne "$speakertitle$speakername$ofwhere") {
				$curnode = $X->createElement('speaking-unknown-id');
				$curnode->setAttribute('title', ToUTF8($speakertitle, 1));
				$curnode->setAttribute('name', ToUTF8($speakername, 1));
				$curnode->setAttribute('of', ToUTF8($ofwhere, 1));
				#$curnode->setAttribute('topic', $topic);
				$X->documentElement->appendChild($curnode);
			}
			AddNode($curnode, "paragraph", $line);
			$spokencount++;
			$lastspokes = "$speakertitle$speakername$ofwhere";
		} elsif ($speaking == -2) {
			AddNode($X->documentElement, "chair", $line);
		} elsif ($speaking == -1) {
			AddNode($X->documentElement, "narrative", $line);
		}
		
		$lastspoke = $speaking;
	}

	if ($lastspoke > 0) {
		# "</speaking>\n";
	} elsif ($lastspoke == 0) {
		# "</speaking-unknown-id>\n";
	}
	
	# "</record>\n";

	$X->toFile($fn, 1);
	
	if ($spokencount < 1) { unlink $fn; }
}

sub AddNode {
	my ($parent, $name, $content) = @_;
	my $node = $parent->ownerDocument->createElement($name);
	$content = ToUTF8($content, 1);
	while ($content =~ s/^([\w\W]*?)(<bill type=[\w\W]*?<\/bill>)//) {
		my ($c, $b) = ($1, $2);
		$node->appendText($c);
		$node->appendWellBalancedChunk($b);
	}
	$node->appendText($content);
	$parent->appendChild($node);
}

sub TextOfAmendments {
	my $content = shift;
	my $session = shift;
	my $where = shift;
	my $date = shift;

	my ($w, $n);
	my $txt;

	$content =~ s/\r//g;
	$content =~ s/<p>\&nbsp;\&nbsp;\&nbsp;/\n/ig;

	my @lines = split(/\n/, $content);

	foreach my $line (@lines) {
		my $islast = ($line =~ s/<em>END<\/em>//);
		$line =~ s/\s+$//g;
		$line =~ s/<\/?(b|em|p|center|br|div)\/?>//gi;
		if ($line =~ /^([HS])A (\d+)\. (The|THE|Mr\.|Ms\.|Mrs\.|Dr\.) [\w\W]+? (proposed|submitted) an amendment/) {
			my ($nw, $nn) = ($1, $2);
			WriteAmendmentText($w, $n, $txt, $session, $where, $date);
			($w, $n) = ($nw, $nn);
			undef $txt;
		}
		$txt .= $line . "\n";
		if ($islast) { last; }
	}
	WriteAmendmentText($w, $n, $txt, $session, $where, $date);
}

sub WriteAmendmentText {
	my ($w, $n, $txt, $session, $where, $date) = @_;
	if (!defined($w)) { return; }

	my $loc;
	if ($where =~ /^h/i) { $loc = "House"; } else { $loc = "Senate"; }
	$txt .= "(As printed in the Congressional Record for the $loc on " .
		DateToString($date) . ".)\n";

	$w = lc($w);
	open TXT, ">../data/us/$session/bills.amdt/$w$n.txt";
	print TXT $txt;
	close TXT;
}
