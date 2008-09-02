#!/usr/bin/perl

# This program uses pdftotext.

require "general.pl";
require "billdiff.pl";

my $gpolist;

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

1;

sub GetBillFullText {
	my $session = shift;
	my $nopdfs = shift;

	my $billdir = "../data/us/$session/bills";
	my $textdir = "../data/us/bills.text/$session";
	
	mkdir $textdir;
	
	# Download PDFs
	if (!$nopdfs) {
	opendir BILLS, "$billdir";
	foreach my $bill (sort(readdir(BILLS))) {
		if ($bill !~ /([a-z]+)(\d+)\.xml/) { next; }
		my ($type, $number) = ($1, $2);
		#my @billstat = stat("$billdir/$bill");
		#my @textstat = stat("$textdir/$type/$type$number.pdf");
		#if ($billstat[9] > $textstat[9]) {
			FetchBillTextPDF($session, $type, $number);
		#}
	}
	closedir BILLS;
	}

	# Download HTML versions
	opendir BILLS, "$billdir";
	foreach my $bill (sort(readdir(BILLS))) {
		if ($bill !~ /([a-z]+)(\d+)\.xml/) { next; }
		my ($type, $number) = ($1, $2);
		my @get_statuses;
		foreach my $status (GetBillStatusList($type)) {
			if (!-e "$textdir/$type/$type$number$status.pdf") { next; }
			if (-e "$textdir/$type/$type$number$status.html") { next; }
			push @get_statuses, $status;
		}
		if (scalar(@get_statuses) > 0) {
			FetchBillTextHTML($session, $type, $number, @get_statuses);
		}
	}
	closedir BILLS;
	
	# Download XML files
	FetchBillXml($session, $textdir) if ($session >= 108);

	# Textify bills
	foreach my $type (keys(%BillTypePrefix)) {
	opendir BILLS, "$textdir/$type";
	foreach my $bill (readdir(BILLS)) {
		if ($bill !~ /$type(\d+)([a-z]+)\.pdf/) { next; }
		my ($number, $status) = ($1, $2);
		if (-e "$textdir/$type/$type$number$status.txt") { next; }
		print "Textifying $bill\n" if (!$OUTPUT_ERRORS_ONLY);
		system("pdftotext -layout -nopgbrk -enc UTF-8 $textdir/$type/$bill");
		if (-e "/usr/bin/pdftotext" && !-e "$textdir/$type/$type$number$status.txt") {
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

	# Symlink the latest version to the unstatused files.
	opendir BILLS, "$billdir";
	foreach my $bill (readdir(BILLS)) {
		if ($bill !~ /([hsrcj]+)(\d+)\.xml/) { next; }
		my ($type, $number) = ($1, $2);
		unlink "$textdir/$type/$type$number.pdf";
		unlink "$textdir/$type/$type$number.txt";
		unlink "$textdir/$type/$type$number.xml";
		my @stz = GetBillStatusList($type);
		for (my $sli = scalar(@stz)-1; $sli>=0; $sli--) {
			my $file = "$type$number$stz[$sli]";
			if (-e "$textdir/$type/$file.pdf") {
				symlink "$file.pdf", "$textdir/$type/$type$number.pdf";
				symlink "$file.txt", "$textdir/$type/$type$number.txt";
				symlink "$file.xml", "$textdir/$type/$type$number.xml";
				last;
			}
		}
	}
	closedir BILLS;
}

sub FetchBillTextPDF {
	my ($session, $type, $number) = @_;
	my $basedir = "../data/us/bills.text/$session";
	
	FetchBillTextLoadGPOList($session);

	my @stz = GetBillStatusList($type);
	
	my @statuses;
	
	while ($gpolist =~ /cong_bills\&docid=f\:$type$number([a-z]+)\.txt\s*\"/g) {
		my $status = $1;
		push @statuses, $status;
	}
	
	foreach my $status (@statuses) {		
		my $URL = "http://frwebgate.access.gpo.gov/cgi-bin/getdoc.cgi?dbname=" . $session . "_cong_bills&docid=f:$type$number$status.txt.pdf";
		my $file = "$basedir/$type/$type$number$status.pdf";
		if (-e $file) { next; }

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
}

sub FetchBillTextLoadGPOList {
	my $session = shift;
	if (defined($gpolist)) { return; }

	# Cache the list for 12 hours.
	my @gpostat = stat("tmp.gpolist-$session");
	if ($gpostat[9] > time-60*60*12) {
		$gpolist = `cat tmp.gpolist-$session`;
		return;
	}
	
	print "Retreiving GPO Bill List... \n" if (!$OUTPUT_ERRORS_ONLY);;
	my $URL = "http://frwebgate.access.gpo.gov/cgi-bin/BillBrowse.cgi?dbname=" . $session . "_cong_bills\&wrapperTemplate=all" . $session . "bills_wrapper.html\&billtype=all";
	my $response = $UA->get($URL);
	if (!$response->is_success) {
		die "Could not fetch bill list at $URL: " .
			$response->code . " " .
			$response->message;
	}
	$HTTP_BYTES_FETCHED += length($response->content);
	$gpolist = $response->content;
	
	open GPOLIST, ">tmp.gpolist-$session";
	print GPOLIST $gpolist;
	close GPOLIST;
	
	print "Done.\n";
}

sub FetchBillXml {
	my $session = shift;
	my $textdir = shift;

	sleep(1);
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
		if (!-e $file) {
			sleep(1);
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
	my ($session, $type, $number, @get_statuses) = @_;

	print "Bill Text HTML: $session/$type$number\n" if (!$OUTPUT_ERRORS_ONLY);

	my $type2 = $type;
	if ($type2 eq "hr") { $type2 = "hres"; }
		
	my $URL = "http://thomas.loc.gov/cgi-bin/query/z?c$session:$type2$number:";
	sleep(1);
	my $response = $UA->get($URL);
	if (!$response->is_success) {
		warn "Could not fetch bill text at $URL: " .
			$response->code . " " .
			$response->message;
		return;
	}
	my $indexhtml = $response->content;
	$HTTP_BYTES_FETCHED += length($indexhtml);

	# First, when there's only one status available, this page isn't
	# an index but the text itself...

	if ($indexhtml =~ /Printer Friendly Display/) {
		FetchBillTextHTML2($session, $type, $number, $get_statuses[0], $indexhtml);
		return;
	}

	# And if the page says that the text hasn't been received from GPO,
	# that's ok.  We'll just move on.
	if ($indexhtml =~ /has not yet been received from GPO/) {
		return;
	}

	foreach my $status (@get_statuses) {
		my $file = "../data/us/bills.text/$session/$type/$type$number$status.html";
		if (-e $file) { next; }

		if ($indexhtml !~ /<a href="(\/cgi-bin\/query\/D\?[^"]+)">\[[HRESCONJ\.0-9]+\.$status\]<\/a>/i) {
			warn "Could not find link to status text for $status at $URL";
			next;
		}

		my $URL2 = "http://thomas.loc.gov" . $1;
		sleep(1);
		my $response = $UA->get($URL2);
		if (!$response->is_success) {
			warn "Could not fetch bill text at $URL: " . $response->code . " " . $response->message;
			return;
		}
		my $htmltext = $response->content;
		$HTTP_BYTES_FETCHED += length($htmltext);

		FetchBillTextHTML2($session, $type, $number, $status, $htmltext);
	}
}

sub FetchBillTextHTML2 {
	my ($session, $type, $number, $status, $htmlpage) = @_;
	my $file = "../data/us/bills.text/$session/$type/$type$number$status.html";
	if (-e $file) { return; }

	mkdir "../data/us/bills.text/$session/$type";

	# move to printer friendly page
	if ($htmlpage !~ /<a href="(\/cgi-bin\/query\/C\?[^"]+)"[^>]*>(<em>)?Printer Friendly Display/) {
		die "Could not find the link to the printer friendly display in $session/$type$number/$status";
	}

	my $URL = "http://thomas.loc.gov" . $1;
	sleep(1);
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
	if ($htmlpage !~ s/^[\w\W]*?<p>\s*([HRESCONJ\.]+ *$number R?($status|[A-Z]{2,3})(\dS)?[\n\r])/$1/i
		&& $htmlpage !~ s/^[\w\W]*?\n\s*([HRESCONJ\.]+ *$number R?($status|[A-Z]{2,3})(\dS)?<p>[\n\r])/$1/i
		&& ($status ne 'enr' || $htmlpage !~ s/^[\w\W]*?<p>\s*([HRESCONJ\.]+ ?$number[\n\r])/$1/i)
		&& $htmlpage !~ s/^[\w\W]*?<p>(<h3><b>Suspend the Rules and Pass the Bill)/$1/i) {
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

	opendir BILLS, "$billdir";
	foreach my $bill (sort(readdir(BILLS))) {
		if ($bill !~ /([a-z]+)(\d+)\.xml/) { next; }
		my ($type, $number) = ($1, $2);
		if ($onlythisbill ne "" && $onlythisbill ne "ALL" && $onlythisbill ne "$type$number") { next; }
		my $pstatus = undef;
		foreach my $status (GetBillStatusList($type)) {
			my $infile = "$textdir/$type/$type$number$status.html";
			if (!-e $infile) { next; }

			my $genfile = "$textdir/$type/$type$number$status.gen.html";

			if ($onlythisbill eq "" && -e $genfile) { $pstatus = $status; next; }
			#if ($onlythisbill eq "ALL" && -e $genfile && (-M $genfile) < 1) { $pstatus = $status; next; }

			print "$genfile\n";

			my $g;
			if (!defined($pstatus)) {
				open G, "<$infile";
				$g = join("", <G>);
				close G;
				$g = AddIdAttributesToBillText($g, "t0:" . $status);
			} else {
				$g = ComputeBillTextChanges($session, $type, $number, $pstatus, $status);
			}

			$g =~ s/(-{80})-*/$1/g;
			$g =~ s/([^\s<>]{80})/$1 /g;

			$g =~ s/((\d+) U\.S\.C\. (\d+))/<usc-reference title="$2" section="$3">$1<\/usc-reference>/g;
			
			open G, ">$genfile";
			print G $g;
			close G;

			$pstatus = $status;
		}
	}
	closedir BILLS;
	
}

sub GetBillStatusList {
	my $type = shift;
	if ($type =~ /^h/) { return (@statuslist_h, @statuslist_s, @statuslist_s2, @statuslist_h2, @statuslist_all); }
	if ($type =~ /^s/) { return (@statuslist_s, @statuslist_h, @statuslist_h2, @statuslist_s2, @statuslist_all); }
	die;
}
