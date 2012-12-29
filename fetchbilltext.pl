#!/usr/bin/perl

# This program uses pdftotext.

require "general.pl";
require "billdiff.pl";
require "db.pl";

my %fdsys_to_gt_billtype = (
	'hr' => 'h', 'hres' => 'hr', 'hjres' => 'hj', 'hconres' => 'hc',
	's' => 's', 'sres' => 'sr', 'sjres' => 'sj', 'sconres' => 'sc');
	
my @statuslist_h = (
	ih,   #    Introduced in House
	ihr,  #    Introduced in House-Reprint
	ih_s, #    Introduced in House (No.) Star Print
	rih,  #    Referral Instructions House
	rfh,  #    Referred in House
	rfhr, #    Referred in House-Reprint
	rfh_s,#    Referred in House (No.) Star Print
	rth,  #    Referred to Committee House
	rah,  #    Referred w/Amendments House
	rch,  #    Reference Change House
	rh,   #    Reported in House
	rhr,  #    Reported in House-Reprint
	rh_s, #    Reported in House (No.) Star Print
	rdh,  #    Received in House
	ash,  #    Additional Sponsors House
	sc,   #    Sponsor Change House
	cdh,  #    Committee Discharged House
	hdh,  #    Held at Desk House
	iph,  #    Indefinitely Postponed in House
	lth,  #    Laid on Table in House
	oph,  #    Ordered to be Printed House
	pch,  #    Placed on Calendar House
	ah,   # Amendment in House (never seen this but have seen 'as'/'as2' on HR 1, 111)
	ah2,  # Amendment in House (see above)
	fah,  #    Failed Amendment House
	ath,  #    Agreed to House
	cph,  #    Considered and Passed House
	eh,   #    Engrossed in House
	ehr,  #    Engrossed in House-Reprint
	eh_s, #    Engrossed in House (No.) Star Print [*]
);

my @statuslist_h2 = (
	eah,  #    Engrossed Amendment House
	reah, #    Re-engrossed Amendment House
	);

my @statuslist_s = (
	is,   #    Introduced in Senate
	isr,  #    Introduced in Senate-Reprint
	is_s, #    Introduced in Senate (No.) Star Print
	ris,  #    Referral Instructions Senate
	rfs,  #    Referred in Senate
	rfsr, #    Referred in Senate-Reprint
	rfs_s,#    Referred in Senate (No.) Star Print
	rts,  #    Referred to Committee Senate
	ras,  #    Referred w/Amendments Senate
	rcs,  #    Reference Change Senate
	rs,   #    Reported in Senate
	rsr,  #    Reported in Senate-Reprint
	rs_s, #    Reported in Senate (No.) Star Print
	rds,  #    Received in Senate
	sas,  #    Additional Sponsors Senate
	cds,  #    Committee Discharged Senate
	hds,  #    Held at Desk Senate
	ips,  #    Indefinitely Postponed in Senate
	lts,  #    Laid on Table in Senate
	ops,  #    Ordered to be Printed Senate
	pcs,  #    Placed on Calendar Senate
	as,   # Amendment in Senate
	as2,  # Amendment in Senate (again?)
	ats,  #    Agreed to Senate
	cps,  #    Considered and Passed Senate
	fps,  #    Failed Passage Senate
	es,   #    Engrossed in Senate
	esr,  #    Engrossed in Senate-Reprint
	es_s, #    Engrossed in Senate (No.) Star Print
	);

my @statuslist_s2 = (
	eas,  #    Engrossed Amendment Senate
	res, #    Re-engrossed Amendment Senate
	);

my @statuslist_all = (
	re,   #    Reprint of an Amendment
	s_p,  #    Star (No.) Print of an Amendment
#	pp,   #    Public Print
	enr,  #    Enrolled Bill
	renr, #    Re-enrolled
	);



$HTMLPARSER = XML::LibXML->new();
$HTMLPARSER->recover(1);

if ($ARGV[0] eq "FULLTEXT") { shift(@ARGV); GetBillFullText(@ARGV); }
if ($ARGV[0] eq "GENERATE") { shift(@ARGV); CreateGeneratedBillTexts(@ARGV); }
if ($ARGV[0] eq "SIMHASH") { shift(@ARGV); ComputeSimHashes(@ARGV); }
if ($ARGV[0] eq "FINDSIMS") { shift(@ARGV); FindSimilarBills(@ARGV); }

1;

sub GetBillFullText {
	my $session = shift;
	my $nopdfs = shift;

	my $billdir = "../data/us/$session/bills";
	my $textdir = "../data/us/bills.text/$session";
	
	mkdir $textdir;
	
	for my $year (YearFromYMD(StartOfSessionYMD($session)) .. YearFromYMD(EndOfSessionYMD($session))) {
		# file may contain bills from a different congress because it is
		# by calendar year, but we are filtering in the regex properly.
		my $response = $UA->get("http://www.gpo.gov/smap/fdsys/sitemap_$year/${year}_BILLS_sitemap.xml");
		if (!$response->is_success) { warn "Could not fetch bill list for $year"; next; }
		my $content = $response->content;
		$HTTP_BYTES_FETCHED += length($content);
		while ($content =~ m|http://www.gpo.gov/fdsys/pkg/BILLS-$session([a-z]+)(\d+)([a-z]\w*)/content-detail|g) {
			FetchBillTextPDF($session, $1, $2, $3) if (!$nopdfs);
			FetchBillTextHTML($session, $fdsys_to_gt_billtype{$1}, $2, $3);
		}
	}

	# Download XML files
	FetchBillXml($session, $textdir) if ($session >= 108);

	# Textify bills
	if (-e "/usr/bin/pdftotext") {
	foreach my $type (keys(%BillTypePrefix)) {
	opendir BILLS, "$textdir/$type";
	foreach my $bill (readdir(BILLS)) {
		if ($bill !~ /$type(\d+)([a-z]+)\.pdf/) { next; }
		my ($number, $status) = ($1, $2);
		if (-e "$textdir/$type/$type$number$status.txt") { next; }
		print "Textifying $bill\n" if (!$OUTPUT_ERRORS_ONLY);
		system("pdftotext -layout -nopgbrk -enc UTF-8 $textdir/$type/$bill");
		if (!-e "$textdir/$type/$type$number$status.txt") {
			# PDF-to-text failed.  It should have printed something.
			unlink "$textdir/$type/$bill"; # fetch again next time

			#open TEXT, ">$textdir/$type$number$status.txt";
			#print TEXT "There was an error creating the text version of
#this bill. Please use the PDF version instead.\n";
			#close TEXT;
		} else {
			system("perl billtextlinefixup.pl $textdir/$type/$type$number$status.txt");
		}
	}
	closedir BILLS;
	}
	} else {
		warn "pdftotext is not installed";
	}

	# Generate thumbnails
	if (-e "/usr/bin/pdftoppm") {
	foreach my $type (keys(%BillTypePrefix)) {
	opendir BILLS, "$textdir/$type";
	foreach my $bill (readdir(BILLS)) {
		if ($bill !~ /$type(\d+)([a-z]+)\.pdf/) { next; }
		my ($number, $status) = ($1, $2);
		my $of = "$textdir/$type/$type$number$status-thumb200.png";
		if (-e $of) { next; }
		print "Generating image thumbnail $bill\n" if (!$OUTPUT_ERRORS_ONLY);
		system("pdftoppm -f 1 -l 1 -scale-to 200 -png $textdir/$type/$bill > $of");
	}
	closedir BILLS;
	}
	} else {
		warn "pdftoppm is not installed";
	}

	# Symlink the latest version to the unstatused files.
	opendir BILLS, "$billdir";
	foreach my $bill (readdir(BILLS)) {
		if ($bill !~ /([hsrcj]+)(\d+)\.xml/) { next; }
		my ($type, $number) = ($1, $2);
		my @stz = GetBillStatusList($type);
		for my $ext ('.pdf', '.txt', '.html', '.xml', ".mods.xml", "-thumb200.png") {
		unlink "$textdir/$type/$type$number$ext";
		for (my $sli = scalar(@stz)-1; $sli>=0; $sli--) {
			my $file = "$type$number$stz[$sli]";
			if (-e "$textdir/$type/$file$ext") {
				symlink "$file$ext", "$textdir/$type/$type$number$ext";
				last;
			}
		}
		}
	}
	closedir BILLS;
}

sub FetchBillTextPDF {
	my ($session, $fdstype, $number, $status) = @_;
	my $type = $fdsys_to_gt_billtype{$fdstype};
	
	my $basedir = "../data/us/bills.text/$session";
	
		# PDF
	
		my $URL = "http://www.gpo.gov/fdsys/pkg/BILLS-$session$fdstype$number$status/pdf/BILLS-$session$fdstype$number$status.pdf";
		my $file = "$basedir/$type/$type$number$status.pdf";
		if (!-e $file || $ENV{FORCE}) {
			print "Bill Text PDF: $session/$type$number/$status\n" if (!$OUTPUT_ERRORS_ONLY);
		
			#sleep(1);
			my $response = $UA->get($URL);
			if (!$response->is_success) {
				warn "Could not fetch bill text at $URL: " .
					$response->code . " " .
					$response->message;
				next;
			}
			$HTTP_BYTES_FETCHED += length($response->content);
		
			mkdir $basedir;
			mkdir "$basedir/$type";
			open TEXT, ">$file";
			print TEXT $response->content;
			close TEXT;
		}
		
		# MODS
		
		my $file = "$basedir/$type/$type$number$status.mods.xml";
		if (!-e $file || $ENV{FORCE}) {
			print "Bill Text MODS: $session/$type$number/$status\n" if (!$OUTPUT_ERRORS_ONLY);
			
			#sleep(1);
			# Statuses on FDSYS are generally capitalized, but not always, and it seems to be random.
			my $status2 = uc($status);
			my $URL = "http://www.gpo.gov/fdsys/pkg/BILLS-${session}${fdstype}${number}${status2}/mods.xml";
			my $response = $UA->get($URL);
			if (!$response->is_success || $response->content =~ /Error Detected|nocontent.htm/) {
				$status2 = lc($status);
				$URL = "http://www.gpo.gov/fdsys/pkg/BILLS-${session}${fdstype}${number}${status2}/mods.xml";
				$response = $UA->get($URL);
			}
			if (!$response->is_success || $response->content =~ /Error Detected|nocontent.htm/) {
				warn "Could not fetch bill text at $URL (tried capital/lowercase status): " .
					$response->code . " " .
					$response->message;
				next;
			}
			$HTTP_BYTES_FETCHED += length($response->content);
			
			mkdir $basedir;
			mkdir "$basedir/$type";
			open TEXT, ">$file";
			print TEXT $response->content;
			close TEXT;
		}
}

sub FetchBillXml {
	my $session = shift;
	my $textdir = shift;

	#sleep(1);
	print "Retreiving House XML Bill List... \n" if (!$OUTPUT_ERRORS_ONLY);;
	my $URL = "http://thomas.loc.gov/home/gpoxmlc$session/";
	my $response = $UA->get($URL);
	if (!$response->is_success) {
		die "Could not fetch XML bill list at $URL: " .
			$response->code . " " .
			$response->message;
	}
	$HTTP_BYTES_FETCHED += length($response->content);

	my $list = $response->content;
	while ($list =~ /"([hs][cjr]?)(\d+)_(\w+)\.xml"/g) {
		my $type = $1;
		my $num = $2;
		my $st = $3;

		my $file = "$textdir/$type/$type$num$st.xml";
		if (!-e $file || $ENV{FORCE}) {
			#sleep(1);
			print "Bill Text XML: $session/$type$num/$st\n" if (!$OUTPUT_ERRORS_ONLY);
			my $URL = "http://thomas.loc.gov/home/gpoxmlc$session/$type$num" . "_$st.xml";
			my $response = $UA->get($URL);
			if (!$response->is_success) {
				die "Could not fetch XML bill text at $URL: " .
					$response->code . " " .
					$response->message;
			}
			$HTTP_BYTES_FETCHED += length($response->content);

			mkdir "$textdir/$type";
			open XML, ">$file";
			print XML $response->content;
			close XML;
		}
	}
}

sub FetchBillTextHTML {
	my ($session, $type, $number, $status) = @_;

	my $type2 = $type;
	if ($type2 eq "hr") { $type2 = "hres"; }
		
		my $file = "../data/us/bills.text/$session/$type/$type$number$status.html";
		if (-e $file) { next; }

	print "Bill Text HTML: $session/$type$number/$status\n" if (!$OUTPUT_ERRORS_ONLY);

		# THOMAS started generating pages w/o the temp link if you don't specify Mozilla in the UA
		my $UA = LWP::UserAgent->new(keep_alive => 2, timeout => 30, agent => "Mozilla/4.0 (GovTrack.us scraper)", from => "operations@govtrack.us");

		my $URL2 = "http://thomas.loc.gov/cgi-bin/query/z?c$session:$type2$number.$status:";
		my $response = $UA->get($URL2);
		if (!$response->is_success) {
			warn "Could not fetch bill text at $URL: " . $response->code . " " . $response->message;
			return;
		}
		my $htmltext = $response->content;
		$HTTP_BYTES_FETCHED += length($htmltext);

		FetchBillTextHTML2($session, $type, $number, $status, $htmltext);
}

sub FetchBillTextHTML2 {
	my ($session, $type, $number, $status, $htmlpage) = @_;
	my $file = "../data/us/bills.text/$session/$type/$type$number$status.html";
	if (-e $file) { return; }

	mkdir "../data/us/bills.text/$session/$type";

	# move to printer friendly page
	if ($htmlpage !~ /<a href="(\/cgi-bin\/query\/C\?[^"]+)"[^>]*>(<em>)?Printer Friendly/i) {
		warn "Could not find the link to the printer friendly display in $session/$type$number/$status";
		return;
	}

	my $URL = "http://thomas.loc.gov" . $1;
	#sleep(1);
	my $response = $UA->get($URL);
	if (!$response->is_success) {
		warn "Could not fetch bill text at $URL: " . $response->code . " " . $response->message;
		return;
	}
	$htmlpage = $response->content;
	$HTTP_BYTES_FETCHED += length($htmlpage);

	if ($status =~ /ea[sh]/ && $htmlpage =~ /^[\w\W]*?<p>([HRESCONJ\.]+ \?\? EA[SH][\n\r])/i) {
		warn "Bill text for $session/$type$number/$status appears to be an amendment.  Skipping.";
		return;
	}

	# chop off everything before the status line
	# sometimes IH appears here as RIH
	# sometimes the wrong status code shows up (EH instead of ENR)
	if ($htmlpage !~ s/^[\w\W]*?<p>(<em>.<\/em>)?\s*([HRESCONJ\.]+ *$number R?($status|[A-Z]{2,3})(\dS)?(\/PP)?[\n\r])/$2/i
		&& $htmlpage !~ s/^[\w\W]*?\n\s*([HRESCONJ\.]+ *$number ?R?($status|[A-Z]{2,3}|IHIS|)(\dS)?<p>[\n\r])/$1/i
		&& ($status ne 'enr' || $htmlpage !~ s/^[\w\W]*?<p>\s*([HRESCONJ\.]+ ?$number[\n\r])/$1/i)
		&& $htmlpage !~ s/^[\w\W]*?<p>(<h3><b>Suspend the Rules and Pass the Bill)/$1/i
		&& (($status ne 'as' && $status ne 'as2') || $htmlpage !~ s/^[\w\W]*?(<p>AMENDMENT NO. <b>\d+<\/b>\s*<p><i39>Purpose: In the nature of a substitute.<\/i39>)/$1/i)
		) {
		warn "Could not find start of bill text for $session/$type$number/$status";
		return;
	}

	# chop off everything after the end
	if ($htmlpage !~ s/[\n\r]+<p\/><em>END<\/em>[\w\W]*$//) {
		die "Could not find end of bill text for $session/$type$number/$status";
	}
	
	# make some corrections that trick the HTML parser
	$htmlpage =~ s/<\/?[tb]title>//g;
	$htmlpage =~ s/<\/?b>//g;

	# put <p> tags within the <ul> tags
	$htmlpage =~ s/<p>((<ul>)*)/$1<p>/g;

	# merge paragraphs at common indentation levels into one <ul>
	while ($htmlpage =~ s/<\/ul>(\s*)<ul>/$1/gi) { }
	
	# there are unescaped ampersands; although 'recover' mode
	# will interpret them OK, we can get rid of some warnings
	$htmlpage =~ s/ \& / \&amp; /g;

	# there are unescaped brackets too
	$htmlpage =~ s/ < / \&lt; /g;

	$htmlpage = ToUTF8($htmlpage);

	my $doc = $HTMLPARSER->parse_html_string($htmlpage);
	($doc) = $doc->findnodes('html/body');
	if (!defined($doc)) {
		die "No body node in parsed HTML document for $session/$type$number/$status";
	}
	
	# This routine does two things:
	# Making sure <center> elements contain only elements, and not text
	# directly.
	# Indenting insertions, which is important because some would otherwise
	# appear as top-level text, which is confusing for section headings
	# that get rendered in bold.
	FixBillTextHtml($doc);

	my $html = $doc->toString(1);

	# correct some characters; can't do this earlier exactly because
	# we look for `'s to insert blockquote elements
	$html =~ s/\``/\&#8220;/g;
	$html =~ s/\''/\&#8221;/g;
	$html =~ s/\`/\&#8216;/g;
	$html =~ s/\'/\&#8217;/g;

	# clean up some spaces in paragraphs
	$html =~ s/(<p>)\s*/$1/g;
	$html =~ s/\s*(<\/p>)/$1/g;

	open H, ">$file";
	binmode(H, "utf8");
	print H $html;
	close H
}

sub FixBillTextHtml {
	my $node = shift;
	my $alreadyinbq = shift;
	
	my $child = $node->firstChild;
	while ($child) {
		if ($child->nodeName eq 'center') {
			# Any text/<em> elements inside <center> are wrapped in <p> tags.
			my $c = $child->firstChild;
			my $lastp;
			while ($c) {
				if (ref($c) eq 'XML::LibXML::Text' || $c->nodeName eq 'em') {
					if (!$lastp) {
						$lastp = $node->ownerDocument->createElement('p');
						$child->insertBefore($lastp, $c);
					}
					$child->removeChild($c);
					if (ref($c) eq 'XML::LibXML::Text') {
						$lastp->appendText($c->textContent);
					} else {
						$lastp->appendChild($c);
					}
					$c = $lastp;
				} else {
					undef $lastp;
				}
				$c = $c->nextSibling;
			}
		}
		
		if (ref($child) eq 'XML::LibXML::Element'
		  && $child->textContent =~ /^\s*\`/
		  && !$alreadyinbq) {
		  	# Turn "`..." into blockquotes.
		  	
			my $bq = $node->ownerDocument->createElement('blockquote');
			$node->insertBefore($bq, $child);
			while ($bq->nextSibling && ($bq->nextSibling->textContent =~ /^\s*\`/ || ref($bq->nextSibling) eq 'XML::LibXML::Text')) {
				my $s = $bq->nextSibling;
				$node->removeChild($s);
				$bq->appendChild($s);
				FixBillTextHtml($s, 1);
			}
			
			$child = $bq->nextSibling;
			next;
		}

		FixBillTextHtml($child, $alreadyinbq);
		$child = $child->nextSibling;
	}
}

sub CreateGeneratedBillTexts {
	my $session = shift;
	my $onlythisbill = shift;

	print "Generating bill diffs and enhanced HTML...\n" if (!$OUTPUT_ERRORS_ONLY);
	
	my $billdir = "../data/us/$session/bills";
	my $textdir = "../data/us/bills.text/$session";
	my $cmpdir = "../data/us/bills.text.cmp/$session";
	
	# This isn't working and creates weird directories probably because
	# it's executed with sh and not bash, so the braces are treated
	# literally.
	#system("mkdir -p {$textdir,$cmpdir}/{h,s,hr,sr,hj,sj,hc,sc}");

	opendir BILLS, "$billdir";
	foreach my $bill (sort(readdir(BILLS))) {
		if ($bill !~ /([a-z]+)(\d+)\.xml/) { next; }
		my ($type, $number) = ($1, $2);
		if ($onlythisbill ne "" && $onlythisbill ne "ALL" && $onlythisbill ne "$type$number") { next; }
		
		my @statuses = GetBillStatusList($type);
		
		# Create a revised XML HTML version that marks up certain
		# things.
		foreach my $status (@statuses) {
			my $infile = "$textdir/$type/$type$number$status.html";
			if (!-e $infile) { next; }

			my $genfile = "$textdir/$type/$type$number$status.gen.html";

			if ($onlythisbill eq "" && -e $genfile) { next; }
			if ($onlythisbill eq "ALL" && -e $genfile && (-M $genfile) < 2) { next; }

			print "$genfile\n";

			my $file;
			
			eval {
				$file = $XMLPARSER->parse_file("$infile");
			};
			if ($@) {
				warn "$infile: $@";
				next;
			}
			
			$file->documentElement->setAttribute('status', $status);
			AddIdAttributesToBillText($file, "t0:" . $status);
			
			my $g = $file->toString;
			$g = BillTextMarkup($g);
			
			open G, ">$genfile";
			print G $g;
			close G;
		}

		for (my $i = 0; $i < scalar(@statuses)-1; $i++) {
			my $status1 = $statuses[$i];
			my $g1 = "$textdir/$type/$type$number$status1.gen.html";
			if (!-e $g1) { next; }
			for (my $j = $i+1; $j < scalar(@statuses); $j++) {
				my $status2 = $statuses[$j];
				my $g2 = "$textdir/$type/$type$number$status2.gen.html";
				if (!-e $g2) { next; }
				mkdir "$cmpdir";
				mkdir "$cmpdir/$type";
				my $outfile = "$cmpdir/$type/$type${number}_$status1-$status2.xml";
				if ($onlythisbill eq "" && -e $outfile) { next; }
				if ($onlythisbill eq "ALL" && -e $outfile && (-M $outfile) < 2) { next; }
				my $c = ComputeBillTextChanges($session, $type, $number, $status1, $status2);

				my $g = $c->toString(1);
				$g = BillTextMarkup($g);
			
				open G, ">$outfile";
				print G $g;
				close G;
			}
		}
    }
	closedir BILLS;
}

sub BillTextMarkup {
	my $g = shift;
	
	$g =~ s/(-{80})-*/$1/g;
	$g =~ s/([^\s<>]{80})/$1 /g;

	# mark up U.S.C. references
	$g =~ s/((\d[0-9A-Za-z\-]*) U\.S\.C\. (\d[0-9A-Za-z\-]*)((\s*\([^\) <\&]+\))*))/usctag($1, $2, $3, $4)/eg;
	$g =~ s/(Section (\d[0-9A-Za-z\-]*)((\s*\([^\) <\&]+\))*) of title ([^\s<\&]+), United States Code)/usctag($1, $5, $2, $3)/egi;
			
	# mark up references to public laws
	$g =~ s/(Public Law (\d+)-(\d+))/<public-law-reference session="$2" number="$3">$1<\/public-law-reference>/g;
	
	return $g;
}

sub GetBillStatusList {
	my $type = shift;
	if ($type =~ /^h/) { return (@statuslist_h, @statuslist_s, @statuslist_s2, @statuslist_h2, @statuslist_all); }
	if ($type =~ /^s/) { return (@statuslist_s, @statuslist_h, @statuslist_h2, @statuslist_s2, @statuslist_all); }
	die;
}

sub ComputeSimHashes {
	my $session = shift;
	my $onlythisbill = shift;

	GovDBOpen();

	print "Computing simhashes...\n" if (!$OUTPUT_ERRORS_ONLY);
	
	my $billdir = "../data/us/$session/bills";
	my $textdir = "../data/us/bills.text/$session";

	opendir BILLS, "$billdir";
	foreach my $bill (sort(readdir(BILLS))) {
		if ($bill !~ /([a-z]+)(\d+)\.xml/) { next; }
		my ($type, $number) = ($1, $2);
		if ($onlythisbill ne "" && $onlythisbill ne "ALL" && $onlythisbill ne "$type$number") { next; }
		foreach my $status (GetBillStatusList($type)) {
			my $infile = "$textdir/$type/$type$number$status.html";
			if (!-e $infile) { next; }

			# Compute simhash. Get the text content of the original
			# HTML version, put that in a file, and run a simhash
			# program. Then put the result into a database.
			my $doc = $XMLPARSER->parse_file($infile);
			open DAT, ">/tmp/govtrack-simhash.txt";
			binmode(DAT, ":utf8");
			print DAT $doc->textContent;
			close DAT;
			my $hash = `simhash/shash-0.3/shash /tmp/govtrack-simhash.txt`;
			#unlink "/tmp/govtrack-simhash.txt";

			if ($hash !~ /^((....)(....)(....)(....)) /) { die; }
			my ($hash, $b1, $b2, $b3, $b4) = ($1, $2, $3, $4, $5);
			for my $b ($b1, $b2, $b3, $b4) {
				$b = hex($b);
			}
			
			print "$infile $hash\n";

			DBDelete(billtextsimhash, ["session=$session and type='$type' and number='$number' and status='$status'"]);
			DBInsert(billtextsimhash,
				session => $session, type => $type, number => $number, status => $status,
				simhash => $hash, block1 => $b1, block2 => $b2, block3 => $b3, block4 => $b4);
		}
	}
	
	DBClose();
}

sub FindSimilarBills {
	my ($session, $type, $number, $status2) = @_;
	
	GovDBOpen();
	
	# Collect the comparisons for all of the bill versions we are comparing to.
	my @hashes;
	my $comp = '0';
	for my $status (GetBillStatusList($type)) {
		if ($status2 && $status2 ne $status) { next; }
		
		# Get the hash for this bill text.
		my ($hash, $b1, $b2, $b3, $b4) = DBSelectFirst(billtextsimhash,
			["simhash, block1, block2, block3, block4"],
			["session=$session and type='$type' and number='$number' and status='$status'"]);
		if (!$hash) { next; }
		
		push @hashes, $hash;
		
		$comp .= " OR (block1=$b1 and block2=$b2 and block3=$b3) or (block1=$b1 and block2=$b2 and block4=$b4) or (block1=$b1 and block3=$b3 and block4=$b4) or (block2=$b2 and block3=$b3 and block4=$b4)";
	}
	
	# Look for similar hashes, with at most 16 bits difference
	# (16 bit hamming distance), which means three of the four
	# blocks must match, from any of the bill versions.
	# We ignore status.
	my @results = DBSelect(billtextsimhash,
		["session, type, number, status, simhash"],
		#["(block1=$b1 and block2=$b2 and block3=$b3) or (block1=$b1 and block2=$b2 and block4=$b4) or (block1=$b1 and block3=$b3 and block4=$b4) or (block2=$b2 and block3=$b3 and block4=$b4)"]
		[$comp]
		);
		
	# Filter out the results that have a hamming distance
	# greater than 5.
	my %matches;
	for my $r (@results) {
		my ($s, $t, $n, $st, $h) = @$r;
		if ($matches{"$s$t$n"}) { next; }
		
		my $mind = 64;
		my $minh;
		for my $hash (@hashes) {
			my $d = hamming($hash, $h);
			if ($d < $mind) { $mind = $d; $minh = $hash; }
		}
		if ($mind > 4) { next; }
		
		$matches{"$s$t$n"} = 1;
		print "$s $t$n $mind $minh/$h\n";
	}
	
	DBClose();
}

sub hamming {
	my ($a, $b) = @_;
	my $d = 0;
	if (length($a) != length($b)) { die; }
	for (my $i = 0; $i < length($a); $i+=2) {
		my $a1 = hex(substr($a, $i, 2));
		my $b1 = hex(substr($b, $i, 2));
		for (my $j = 0; $j < 8; $j++) {
			$d += ((($a1 & 1<<$j) != ($b1 & 1<<$j)) ? 1 : 0);
		}
	}
	return $d;
}

sub usctag {
	my ($text, $title, $section, $paragraph) = @_;
	$paragraph =~ s/<[^>]+>//g; # remove tags which occur rarely
	return "<usc-reference title=\"$title\" section=\"$section\" paragraph=\"" . splitUSCGraphId($paragraph) . "\">$text<\/usc-reference>"
}

sub splitUSCGraphId {
	my $x = shift;
	my @xx = split(/[()\s]+/, $x);
	if ($xx[0] eq '') { shift(@xx); }
	if ($xx[-1] eq '') { pop(@xx); }
	return join("_", @xx);
}
