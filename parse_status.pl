use Time::Local;
use LWP::UserAgent;

require "general.pl";
require "persondb.pl";
require "parse_rollcall.pl";
require "indexing.pl";

if ($ARGV[0] eq "PARSE_STATUS") { &Main; }
if ($ARGV[0] eq "PARSE_STATUS_STDIN") { &Main2; }
if ($ARGV[0] eq "REFRESH") { GovDBOpen(); RefreshBills($ARGV[1], $ARGV[2], $ARGV[3]); DBClose(); }
if ($ARGV[0] eq "ALLSESSION") { &AllSession; }
if ($ARGV[0] eq "ALLAMENDMENTS") { &AllAmendments; }

1;

sub Main {
	&GovDBOpen;
	GovGetBill($ARGV[1], $ARGV[2], $ARGV[3], 0, []);
	&DBClose;
}

sub Main2 {
	&GovDBOpen;
	while (!eof(STDIN)) {
		my $l = <STDIN>; chop $l;
		GovGetBill(split(/\s/, $l));
	}
	&DBClose;
}

sub RefreshBills {
	my ($session, $xpath, $pattern, $dontwarnifunchanged) = @_;
	
	my @bills = GetBillList($session);
	foreach $bill_ (@bills) {
		my $bill;
		eval { $bill = GetBill(@{ $bill_ }); };
		
		# Failed to parse?
		if ($@) {
			print "$$bill_[0] $$bill_[1] $$bill_[2]:$@\n";
			GovGetBill( $$bill_[0], $$bill_[1], $$bill_[2] );
			next;
		}
		
		# The wrong bill is inside the file!
		if ("$$bill_[1]$$bill_[0]-$$bill_[2]" ne $bill->findvalue('concat(@type,@session,"-",@number)')) {
			print "Deleting $$bill_[1]$$bill_[0]-$$bill_[2] because the wrong bill is inside!\n";
			unlink "../data/us/$session/bills/$$bill_[1]$$bill_[2].xml";
			next;
		}
		
		if ($xpath ne '' && RefreshTest($bill, $xpath, $pattern)) {
			GovGetBill( $$bill_[0], $$bill_[1], $$bill_[2] );
			if (!$dontwarnifunchanged) {
				$bill = GetBill(@{ $bill_ });
				if (RefreshTest($bill, $xpath, $pattern)) {
					print "$$bill_[0]$$bill_[1]$$bill_[2]: XPath expression still matches.\n";
				}
			}
		}
	}
}

sub AllAmendments {
	my $session = $ARGV[1];
	my $xpath = $ARGV[2];
	my $pattern = $ARGV[3];
	
	&GovDBOpen;
	my @bills = GetBillList($session);
	foreach $bill_ (@bills) {
		my $bill = GetBill(@{ $bill_ });
		my $billtype = $bill->getAttribute('type');
		my $billnumber = $bill->getAttribute('number');
		foreach my $a ($bill->findnodes("amendments/amendment")) {
			if ($xpath ne "") {
				my $af = "../data/us/$session/bills.amdt/" . $a->getAttribute('number') . ".xml";
				if (-e $af) {
					my $ax = $XMLPARSER->parse_file($af);
					if (!RefreshTest($ax, $xpath, $pattern)) { next; }
				}
			}

			$a->getAttribute('number') =~ /(h|s)(\d+)/;
			my ($ch, $num) = ($1, $2);
			my $char;
			if ($ch eq "h") { $char = 'Z'; } else { $char = 'P'; }
			ParseAmendment($session, $ch, $char, $num, $billtype, $billnumber);
		}
	}
	&DBClose;
}

sub RefreshTest {
	my $bill = shift;
	my $xpath = shift;
	my $pattern = shift;
	if ($pattern eq "") {
		my $value = $bill->findvalue($xpath);
		return $value eq "true";
	} elsif ($pattern eq "EXISTS") {
		my @value = $bill->findnodes($xpath);
		return scalar(@value) > 0;
	} elsif ($pattern eq "ENCODING") {
		foreach my $node ($bill->findnodes($xpath)) {
			if (HasUTF8Chars($node->textContent)) { return 1; }
		}
		return 0;
	} elsif ($pattern eq "CHECKPERSONID") {
		foreach my $node ($bill->findnodes($xpath)) {
			my $id = $node->textContent;
			if ($id eq "") { next; }
			if (defined($CHECKPERSONID{$id})) {
				if ($CHECKPERSONID{$id}) { return 1; }
				next;
			}
			print "$id\n";
			my ($ex) = DBSelectFirst(people, [id], ["id=$id"]);
			$CHECKPERSONID{$id} = !defined($ex);
			if (!defined($ex)) {
				print "$id\n";
				return 1;
			}
		}
		return 0;
	} else {
		foreach my $node ($bill->findnodes($xpath)) {
			if ($node->textContent =~ /$pattern/) { return 1; }
		}
		return 0;
	}
}

sub AllSession {
	&GovDBOpen;
	GovGetAllBills($ARGV[1], $ARGV[2]);
	&DBClose;
}

sub GovGetAllBills {
	my $SESSION = shift;    # Session number
	my $SKIPIFEXISTS = shift;
	my $content;

	if (1) {
		my $URL;
		if ($SESSION =~ /^http/) {
			$URL = $SESSION;
			$URL =~ /(\d\d\d)_cong_bills/;
			$SESSION = $1;
		} else {
			$URL = "http://frwebgate.access.gpo.gov/cgi-bin/BillBrowse.cgi?dbname=" . $SESSION . "_cong_bills&wrapperTemplate=all" . $SESSION . "bills_wrapper.html&billtype=all";
		}
		print $URL . "\n";
	        my $response = $UA->get($URL);
        	if (!$response->is_success) {
	                die "Could not fetch " .
        	        "bill list at $URL: " .
                	$response->code . " " .
	                $response->message; }
                $HTTP_BYTES_FETCHED += length($response->content);
		$content = $response->content;
	} else {
		$content = `cat data/bills$SESSION`;
	}

	my %billstatuses = ();
	my @bills = ();

	while ($content =~ m/cong_bills\&docid=f\:([a-z]+)(\d+)(\w+)\.txt[\n\r]"/g) {
		my $billtype = $1;
		my $billnumber = $2;
		my $billstatus = $3;

		push @bills, [$billtype, $billnumber];
		push @{ $billstatuses{$billtype . $billnumber} }, $billstatus;
	}

	my $lastb;
	foreach my $b (@bills) {
		my @bb = @{ $b };

		if ($lastb eq $bb[0] . $bb[1]) { next; }
		$lastb = $bb[0] . $bb[1];

		#if (!($bb[0] eq "sj" || $bb[0] eq "sc" || $bb[0] eq "hj" || $bb[0] eq "hc")) { next; }
		#if ($bb[0] =~ "^h") { next; }
		
		GovGetBill($SESSION, $bb[0], $bb[1], $SKIPIFEXISTS, $billstatuses{$bb[0] . $bb[1]});
	}
}

sub GovGetBill {
	my $SESSION = shift;    # Session number
	my $BILLTYPE = shift;   # h, hc, hj, hr, s, sc, sj, sr (case insens.)
	my $BILLNUMBER = shift;
	my $SKIPIFEXISTS = shift;
	my @BILLSTATUSES = @{ $_[0]; }; shift;
	
	if ($BILLNUMBER eq "") { die "No bill number given."; }

	my $xfn = "../data/us/$SESSION/bills/$BILLTYPE$BILLNUMBER.xml";
	if ($SKIPIFEXISTS && -e $xfn) { return; }
	if ($ENV{SKIP_RECENT} && -M $xfn < 4) { return; }

	sleep 1;
	print "Fetching $SESSION:$BILLTYPE$BILLNUMBER\n" if (!$OUTPUT_ERRORS_ONLY);

	my $BILLTYPE2 = $BILLTYPE;
	if ($BILLTYPE2 eq "hr") { $BILLTYPE2 = "hres"; }

	my $SERVER = "thomas.loc.gov";	
	my $PATH = "/cgi-bin/bdquery/z?d$SESSION:$BILLTYPE2$BILLNUMBER:\@\@\@L";
	my $URL = "http://$SERVER$PATH";

	my $now = time;
	my $updated = Now();

	my $response = $UA->get($URL);
	if (!$response->is_success) {
		warn "Could not fetch " .
		"bill($SESSION, $BILLTYPE, $BILLNUMBER) at $URL: " .
                $response->code . " " .
                $response->message;
		return; }

	$HTTP_BYTES_FETCHED += length($response->content);
	my $content = $response->content;
	$content =~ s/\n\r/\n/g;
	$content =~ s/\r/ /g; # amazing, stray carriage returns
	
	# bring cosponsorship date onto previous line
	$content =~ s/(\[[A-Z\d\-]+\])\n( - \d\d?\/)/$1$2/g;

	my @content = split(/\n+/, $content);

	my $SPONSOR_TITLE = undef;
	my $SPONSOR_NAME = undef;
	my $SPONSOR_STATE = undef;
	my $SPONSOR_ID = undef;
	my $INTRODUCED = undef;
	my $INTRODUCED2 = undef;
	my @ACTIONS = ();
	my @COMMITTEES = ();
	my %COSPONSORS = ();
	my $COSPONSORS_MISSING = 0;
	my @RELATEDBILLS = ();
	my @TITLES = ();
	my $STATUSNOW;
	my $STATUS_ON_TABLE_MOTION;
	my @CRS = ();
	my @AMENDMENTS = ();

	my $lastcommittee = undef;
	my $titles = undef;
	my $backup_title;
	my $wasvetoed = 0;

	my $titlesmode = 0;

	my $action_substate = -1; # there is an initial DL to start off the main list
	my $action_committee = undef;
	my $action_subcommittee = undef;

	while (scalar(@content) > 0) {
		my $cline = shift(@content);

		if ($titlesmode == 1) {
			if ($cline =~ /<\/ul>/) { $titlesmode = 0; next; }
			$titles .= $cline;
			next;
		}

		# TODO: Some bills (109th's debt ceiling limit) have No Sponsor.
		# SPONSOR
		if ($cline =~ /<br><b>Sponsor: <\/b>(No Sponsor|<a [^>]+>([\w\W]*)<\/a>\s+\[(\w\w(-\d+)?)\])/i) {
			my $SPONSOR_TEXT = $1;
			$SPONSOR_NAME = $2;
			$SPONSOR_STATE = $3;

			while (scalar(@content) > 0) {
				my $cline = shift(@content);
				if ($cline =~ /(\(by request\) )?\(introduced ([\d\/]+)\)/i) {
					$INTRODUCED = $2;
					last;
				}
			}

			$INTRODUCED2 = ParseDateTime($INTRODUCED);
			$INTRODUCED = ParseTime($INTRODUCED);

			if ($SPONSOR_TEXT ne "No Sponsor") {
				if ($SPONSOR_NAME =~ s/^(Sen|Rep)\.?\s+//i) { $SPONSOR_TITLE = $1; }

				$SPONSOR_ID = PersonDBGetID(
					title => $SPONSOR_TITLE,
					name => $SPONSOR_NAME,
					state => $SPONSOR_STATE,
					when => $INTRODUCED);
				if (!defined($SPONSOR_ID)) { warn "parsing bill $BILLTYPE$SESSION-$BILLNUMBER: Unknown sponsor: $SPONSOR_TITLE, $SPONSOR_NAME, $SPONSOR_STATE"; return; }
				else { $SPONSOR_ID = "id=\"$SPONSOR_ID\""; }
			} else {
				$SPONSOR_ID = "none=\"true\"";
			}
			
			$STATUSNOW = "<introduced date=\"$INTRODUCED\" datetime=\"$INTRODUCED2\"/>";

		# BACKUP TITLE
		} elsif ($cline =~ /<B>Title:<\/B> ([\w\W]+)/i) {
			$backup_title = ['official', 'introduced', HTMLify($1)];

		# ACTIONS
		} elsif ($cline =~ /<dt><strong>([\d\/ :apm]+):<\/strong><dd>([\w\W]+)/i) {
			my $when_old = $1;
			my $when = $1;
			my $what = $2;

			$what = HTMLify($what);
			$when_old = ParseTime($when_old);
			$when = ParseDateTime($when);

			my $statusdateattrs = "date=\"$when_old\" datetime=\"$when\"";
			my @axndateattrs = (date => $when_old, datetime => $when);
			
			# skip actions about amendments
			if ($what =~ /^[SH].AMDT.\d+/) { next; }

			if ($cline =~ /^<dl>/) { $action_substate++; }
			if ($cline =~ /^<\/dl>/) { $action_substate--; }

			my $action_state = [$when];
			if ($action_substate == 1) { $action_state = [$when, $action_committee]; }
			if ($action_substate == 2) { $action_state = [$when, $action_committee, $action_subcommittee]; }

			# house vote
			$what =~ s/, the Passed/, Passed/g; # 106 h4733 and others
			if ($what =~ /(On passage|On motion to suspend the rules and pass the bill|On motion to suspend the rules and agree to the resolution|On motion to suspend the rules and pass the resolution|On agreeing to the resolution|On agreeing to the conference report|Two-thirds of the Members present having voted in the affirmative the bill is passed,?)(, the objections of the President to the contrary notwithstanding.?)?(, as amended)? (Passed|Failed|Agreed to|Rejected) (by voice vote|without objection|by (the Yeas and Nays|recorded vote)((:)? \(2\/3 required\))?: \d+ - \d+(, \d+ Present)? \(Roll no\. \d+\))/i) {
				my $motion = $1;
				my $isoverride = $2;
				my $passfail = $4;
				my $how = $5;
				my $votetype;
				my $roll = "";
				
				if ($passfail =~ /Pass/ || $passfail =~ /Agreed/) { $passfail = "pass"; }
				else { $passfail = "fail"; }
				
				if ($wasvetoed && $motion =~ /Two-thirds of the Members present/) {
					$isoverride = 1;
				}
				if ($wasvetoed && !$isoverride) {
					warn "A vote after a veto?? Maybe we need to parse this as an override.";
				}

				if ($isoverride) {
					$votetype = "override";
				} elsif ($BILLTYPE =~ /^h/) {
					$votetype = "vote";
				} else {
					$votetype = "vote2";
				}
				
				if ($what =~ /\(Roll no\. (\d+)\)/i) {
					$roll = $1;
					$how = "roll";
				}
				
				my $suspension;
				if ($motion =~ /On motion to suspend the rules/ && $how eq 'roll') {
					$suspension = 1;
				}

				my $votenode = 'vote';
				if ($motion =~ /conference report/) {
					$votenode = 'vote-aux';
					$votetype = 'conference';
				}

				my $prevstatus = $STATUSNOW;
				if ($votenode eq 'vote') {
					$STATUSNOW = "<$votetype $statusdateattrs where=\"h\" result=\"$passfail\" how=\"$how\" roll=\"$roll\"/>";
				}

				push @ACTIONS, [$action_state, 2, $votenode, $what, { @axndateattrs, where => 'h', type => $votetype, result => $passfail, how => $how, roll => $roll, suspension => $suspension } ];
				
				if ($roll != 0) { GetHouseVote(YearFromDateTime($when), $roll, 1); }

				# Funny thing: on a motion to suspend the rules and 
				# pass, if the motion fails, the bill may still yet 
				# continue to be debated, or debate may end, probably 
				# with a "Motion to reconsider laid on the table Agreed 
				# to without objection."
				undef $STATUS_ON_TABLE_MOTION; # another vote resets this
				if ($motion =~ /On motion to suspend the rules/ && $passfail eq "fail") {
					$STATUS_ON_TABLE_MOTION = $STATUSNOW;
					$STATUSNOW = $prevstatus;
				}

			# senate vote
			} elsif ($what =~ /(Passed Senate|Failed of passage in Senate|Resolution agreed to in Senate|Received in the Senate, considered, and agreed to|Submitted in the Senate, considered, and agreed to|Introduced in the Senate, read twice, considered, read the third time, and passed|Received in the Senate, read twice, considered, read the third time, and passed|Senate agreed to conference report|Cloture \S*\s?on the motion to proceed .*?not invoked in Senate|Cloture on the bill not invoked in Senate)(,?[\w\W]*,?) (without objection|by Unanimous Consent|by Voice Vote|by Yea-Nay( Vote)?\. \d+\s*-\s*\d+\. Record Vote (No|Number): \d+)/) {
				my $motion = $1;
				my $passfail = $1;
				my $junk = $2;
				my $how = $3;
				my $roll = "";

				if ($passfail =~ /Passed|agreed/i) { $passfail = "pass"; }
				else { $passfail = "fail"; }

				if ($junk =~ /over veto/) {
					$votetype = "override";
				} elsif ($BILLTYPE =~ /^s/) {
					$votetype = "vote";
				} else {
					$votetype = "vote2";
				}
				
				if ($what =~ /Record Vote (No|Number): (\d+)\./) {
					$roll = $2;
					$how = "roll";
				}

				my $votenode = 'vote';
				if ($motion =~ /conference report/) {
					$votenode = 'vote-aux';
					$votetype = 'conference';
				}
				if ($motion =~ /Cloture/) {
					$votenode = "vote-aux";
					$votetype = "cloture";
				}


				if ($votenode eq 'vote') {
					$STATUSNOW = "<$votetype $statusdateattrs where=\"s\" result=\"$passfail\" how=\"$how\" roll=\"$roll\"/>";
				}

				push @ACTIONS, [$action_state, 2, $votenode, $what, { @axndateattrs, where => 's', type => $votetype, result => $passfail, how => $how, roll => $roll } ];
				
				if ($roll != 0) { GetSenateVote($SESSION, SubSessionFromYear(YearFromDateTime($when)), YearFromDateTime($when), $roll, 1); }

			} elsif ($what =~ /Placed on (the )?([\w ]+) Calendar( under ([\w ]+))?[,\.] Calendar No\. (\d+)\.|Committee Agreed to Seek Consideration Under Suspension of the Rules|Ordered to be Reported/i) {
				if ($STATUSNOW =~ /^<introduced/) {
					$STATUSNOW = "<calendar $statusdateattrs />";
				}
				push @ACTIONS, [$action_state, 2, "calendar", $what, { @axndateattrs, calendar => $2, under => $4, number => $5 }];
			} elsif ($what =~ /Cleared for White House|Presented to President/) {
				$STATUSNOW = "<topresident $statusdateattrs />";
				push @ACTIONS, [$action_state, 2, "topresident", $what, { @axndateattrs }];
			} elsif ($what =~ /Signed by President/) {
				$STATUSNOW = "<signed $statusdateattrs />";
				push @ACTIONS, [$action_state, 2, "signed", $what, { @axndateattrs }];
			} elsif ($what =~ /Vetoed by President/) {
				$STATUSNOW = "<veto $statusdateattrs />";
				push @ACTIONS, [$action_state, 2, "vetoed", $what, { @axndateattrs }];
				$wasvetoed = 1;
			} elsif ($what =~ /Became (Public|Private) Law No: ([\d\-]+)\./) {
				$STATUSNOW = "<enacted $statusdateattrs />";
				push @ACTIONS, [$action_state, 2, "enacted", $what, { @axndateattrs, type => lc($1), number => $2 }];

			} elsif ($what =~ /Passed House pursuant to/) {
				my $votetype;
				my $how = "by special rule";
				if ($BILLTYPE =~ /^h/) { $votetype = "vote"; } else { $votetype = "vote2"; }
				$STATUSNOW = "<$votetype $statusdateattrs where=\"h\" result=\"pass\" how=\"$how\"/>";
				push @ACTIONS, [$action_state, 2, "vote", $what, { @axndateattrs, where => 'h', type => $votetype, result => 'pass', how => $how } ];

			} elsif ($what =~ /Motion to reconsider laid on the table Agreed to without objection/) {
				# that's the end of that bill
				if (defined($STATUS_ON_TABLE_MOTION)) {
					$STATUSNOW = $STATUS_ON_TABLE_MOTION;
					undef $STATUS_ON_TABLE_MOTION;
				}

			} else {
				if ($what =~ /^Referred to ((House|Senate) .*[^\.]).?/) {
					$action_committee = $1;
				}
				if ($what =~ /^Referred to the Subcommittee on (.*[^\.]).?/) {
					$action_subcommittee = $1;
				}

				push @ACTIONS, [$action_state, 1, $statusdateattrs, $what];

			}

		# COSPONSORS
		} elsif ($cline =~ /<br><a href=[^>]+>(Rep|Sen) ([\w\W]+)<\/a> \[([A-Z\d\-]+)\] - (\d\d?\/\d\d?\/\d\d\d\d)(\(withdrawn - (\d\d?\/\d\d?\/\d\d\d\d)\))?/i) {
			# Wish I could easily get the date of the cosponsorship,
			# but it's on the next line.
			my $t = $1;
			my $n = $2;
			my $s = $3;
			my $d = $4;
			my $withdrawndate = $6;
			
			my $i = PersonDBGetID(title => $t, name => $n, state => $s, when => ParseTime($d));
			if (!defined($i)) {
				warn "parsing bill $BILLTYPE$SESSION-$BILLNUMBER: Unknown person: $t, $n, $s";
				$COSPONSORS_MISSING = 1;
			}
			else {
				if (!$COSPONSORS{$i}) {
					# If we've already seen this cosponsor, then it's
					# because he rejoined after withdrawing.
					$COSPONSORS{$i}{added} = ParseDateTime($d);
					if ($withdrawndate) {
						$COSPONSORS{$i}{removed} = ParseDateTime($withdrawndate);
					}
				}
			}

		# TITLES
		} elsif ($cline =~ /<a name="titles">/i) {
			$titlesmode = 1;

		} else {
			#print "UNKNOWN: $cline\n";
		}
	}

	if (!defined($INTRODUCED)) {
		warn "parsing bill $BILLTYPE$SESSION-$BILLNUMBER: Failed parse, no introduced date found: $URL";
		return;
	}


	# TITLES

	if ($titles eq "" || $titles =~ /\*NONE\*/) {
		# There's some bug in THOMAS that titles aren't appearing on the All Information status page.
		$URL =~ s/\@[\w\W]*$/\@\@\@T/;
		sleep 1;
		$response = $UA->get($URL);
		if (!$response->is_success) {
			warn "Could not fetch " .
				"bill-titles($SESSION, $BILLTYPE, $BILLNUMBER) at $URL: " .
            	$response->code . " " .
                $response->message;
			return; }
		$titles = $response->content;
	}
	$titles =~ s/[\n\r]//g;
	$titles =~ s/<\/?i>//gi;
	while ($titles =~ m/<li>([\w\W]*?)( as [\w ]*)?:<br>([\w\W]+?)(<p>|$)/gi) {
		my $type = $1;
		my $when = $2;
		my $ts = $3;
		$type =~ s/ title(\(s\))?//i;
		$when =~ s/^ as //i;
		
		foreach my $t (split(/<BR>/i, $ts)) {
			$t =~ s/<\/?[^>]+>//g;
			$t =~ s/&nbsp;/ /g;
			$t =~ s/\s*\(identified by CRS\)//gi;
			push @TITLES, [lc($type), lc($when), HTMLify($t)];
		}
	}

	if (scalar(@TITLES) == 0) { push @TITLES, $backup_title; }

	# SUMMARY

	my $summarymode = 0;
	my $SUMMARY = undef;

	$URL =~ s/\@[\w\W]*$/\@\@\@D\&summ2=m\&/;
	sleep 1;
	$response = $UA->get($URL);
	if (!$response->is_success) {
		warn "Could not fetch " .
		"bill-summary($SESSION, $BILLTYPE, $BILLNUMBER) at $URL: " .
                $response->code . " " .
                $response->message;
		return; }
	$content = $response->content;
	$content =~ s/\n\r/\n/g;
	$content =~ s/\r/ /g; # amazing, stray carriage returns
	@content = split(/\n+/, $content);
	$HTTP_BYTES_FETCHED += length($response->content);
	while (scalar(@content) > 0) {
		my $cline = shift(@content);
		if ($summarymode == 1) {
			if ($cline =~ /<HR/i) { $summarymode = 0; next; }
			if ($cline =~ /THOMAS Home/) { last; }
			$cline =~ s/<a[^>]*>([\w\W]*?)<\/a>/$1/ig;
			$SUMMARY .= $cline . "\n";
			next;
		} elsif ($cline =~ /<b><a name="summary">SUMMARY AS OF:<\/a><\/b>/i) {
			$summarymode = 1;
		}
	}

	# GET COMMITTEES

	sleep 1;
	$URL = "http://thomas.loc.gov/cgi-bin/bdquery/z?d$SESSION:$BILLTYPE2$BILLNUMBER:\@\@\@C";
	$response = $UA->get($URL);
	if (!$response->is_success) {
		die "Could not fetch " .
		"bill-committees($SESSION, $BILLTYPE, $BILLNUMBER) at $URL: " .
                $response->code . " " .
                $response->message; }
	$HTTP_BYTES_FETCHED += length($response->content);
	@content = split(/[\n\r]+/, $response->content);
	foreach $c (@content) {
		if ($c =~ /<a href="\/cgi-bin\/bdquery(tr)?\/R\?[^"]+">([\w\W]*)<\/a>\s*<\/td><td width="65\%">([\w\W]+)<\/td><\/tr>/i) {
 			my $c = $2;
			my $r = $3;
			$c =~ s/[\\\/]/\-/g;
			$c =~ s/  / /g;
			$r =~ s/[\\\/]/\-/g;
			if ($c =~ s/^Subcommittee on \s*([\w\W]*)$/$1/i) {
				push @COMMITTEES, [$lastcommittee, $c, $r];
			} else {
				push @COMMITTEES, [$c, undef, $r];
				$lastcommittee = $c;
			}
		}
	}

	# GET CRS TERMS

	sleep 1;
	$URL = "http://thomas.loc.gov/cgi-bin/bdquery/z?d$SESSION:$BILLTYPE2$BILLNUMBER:\@\@\@J&summ2=m&";
	$response = $UA->get($URL);
	if (!$response->is_success) {
		die "Could not fetch " .
		"crs($SESSION, $BILLTYPE, $BILLNUMBER) at $URL: " .
                $response->code . " " .
                $response->message; }
	$HTTP_BYTES_FETCHED += length($response->content);
	@content = split(/[\n\r]+/, $response->content);
	foreach $c (@content) {
		if ($c =~ /\@FIELD\(FLD001\+\@4/i ) {
			$c =~ /<a[^>]+>([\w\W]+)<\/a>/i;
			$c = $1;
			$c =~ s/[\\\/]/\-/g;
			push @CRS, htmlify($c);
		}
	}


	# GET RELATED BILLS

	sleep 1;
	$URL = "http://thomas.loc.gov/cgi-bin/bdquery/z?d$SESSION:$BILLTYPE2$BILLNUMBER:\@\@\@K";
	$response = $UA->get($URL);
	if (!$response->is_success) {
		die "Could not fetch " .
		"bill-relatedbills($SESSION, $BILLTYPE, $BILLNUMBER) at $URL: " .
                $response->code . " " .
                $response->message; }
	$HTTP_BYTES_FETCHED += length($response->content);
	@content = split(/[\n\r]+/, $response->content);
	foreach $c (@content) {
		if ($c =~ /<tr><td width="150"><a href="\/cgi-bin\/bdquery(tr)?\/z\?d(\d\d\d):\w+\d\d\d\d\d:">$BillPattern<\/a><\/td><td>([^<]+)<\/td><\/tr>/i) {
			my ($s, $t, $n, $r) = ($2, $3, $4, $5);
			$t = $BillTypeMap{lc($t)};
			$n = int($n);
			if ($t eq "") { $r = undef; }

			if ($r =~ /passed in (House|Senate) in lieu of this bill/) {
				$r = "supersedes";
			} elsif ($r =~ /This bill passed in (House|Senate) in lieu of /) {
				$r = "superseded";
			} elsif ($r =~ /identical bill/i) {
				$r = "identical";
			} elsif ($r =~ /^Rule/i) {
				$r = "rule";
			} else { $r = "unknown"; }

			if (defined($r)) {
				push @RELATEDBILLS, [$r, $s, $t, $n];
			}
		}
	}

	# GET AMENDMENTS

	sleep 1;
	$URL = "http://thomas.loc.gov/cgi-bin/bdquery/z?d$SESSION:$BILLTYPE2$BILLNUMBER:\@\@\@A";
	$response = $UA->get($URL);
	if (!$response->is_success) {
		die "Could not fetch " .
		"amendments($SESSION, $BILLTYPE, $BILLNUMBER) at $URL: " .
                $response->code . " " .
                $response->message; }
	$HTTP_BYTES_FETCHED += length($response->content);
	@content = split(/[\n\r]+/, $response->content);
	foreach $c (@content) {
		if ($c =~ /<a href="\/cgi-bin\/bdquery\/z\?d$SESSION:(HZ|SP)\d+:">/i ) {
			$c =~ s/<P><\/div>//g;
			foreach my $amd (split(/\&nbsp;-\&nbsp;/, $c)) {
				if ($amd !~ /<a href="\/cgi-bin\/bdquery\/z\?d$SESSION:([HS])([ZP])(\d+):">[HS]\.AMDT\.\d+<\/a>/) { warn $amd; next; }
				my $ch = lc($1);
				my $char = lc($2);
				my $num = int($3);
				push @AMENDMENTS, "$ch$num";
				ParseAmendment($SESSION, $ch, $char, $num, $BILLTYPE, $BILLNUMBER);
			}
		}
	}

	# REFORMAT

	my @ti;
	my $ti2;
	foreach $c (@TITLES) {
		my @cc = @{ $c };
		push @ti, "\t\t<title type=\"$cc[0]\" as=\"$cc[1]\">$cc[2]</title>";
	}
	$ti2 = join("\n", @ti);

	my @cos;
	my $cos2;
	foreach $c (keys(%COSPONSORS)) {
		my $j = "joined=\"$COSPONSORS{$c}{added}\"";
		my $r = ($COSPONSORS{$c}{removed} ? " withdrawn=\"$COSPONSORS{$c}{removed}\"" : '');
		push @cos, "\t\t<cosponsor id=\"$c\" $j$r/>";
	}
	$cos2 = join("\n", @cos);
	if ($COSPONSORS_MISSING) { $COSPONSORS_MISSING = ' missing-unrecognized-person="1"'; } else { $COSPONSORS_MISSING = ''; }

	my @act;
	my $act2;
	foreach $c (sort( { CompareDates($$a[0][0], $$b[0][0]); }  @ACTIONS)) {
		my @cc = @{ $c };
		my $ccstate = shift(@cc);
		my $ccc = shift(@cc);
		my ($ccdate, $cccommittee, $ccsubcommittee) = @{ $ccstate };
		my $axncom;
		if (defined($cccommittee)) {
			$axncom = "<committee name=\"" . htmlify($cccommittee) . "\"";
			if (defined($ccsubcommittee)) {
				$axncom .= " subcommittee=\"" . htmlify($ccsubcommittee) . "\"";
			}
			$axncom .= "/>";
		}
		if ($ccc == 1) {
			$cc[2] =~ s/<\/?[^>]+>//g;
			push @act, "\t\t<action $cc[0]>$axncom" . ParseActionText($cc[1]) . "</action>";
		} else {
			my $s = "<$cc[0] ";
			my %sk = %{ $cc[2] };
			foreach my $k (keys(%sk)) { if ($sk{$k} eq "") { next; } $s .= "$k=\"$sk{$k}\" "; }
			$s .= ">$axncom" . ParseActionText($cc[1]) . "</$cc[0]>";
			push @act, "\t\t$s";
		}
	}
	$act2 = join("\n", @act);

	my @com;
	my $com2;
	foreach $c (@COMMITTEES) {
		my @cc = @{ $c };
		push @com, "\t\t<committee name=\"$cc[0]\" subcommittee=\"$cc[1]\" activity=\"$cc[2]\" />";
	}
	$com2 = join("\n", @com);

	my @rb;
	my $rb2;
	foreach $c (@RELATEDBILLS) {
		my @cc = @{ $c };
		push @rb, "\t\t<bill relation=\"$cc[0]\" session=\"$cc[1]\" type=\"$cc[2]\" number=\"$cc[3]\" />";
	}
	$rb2 = join("\n", @rb);

	my @crs;
	my $crs2;
	foreach $c (@CRS) {
		push @crs, "\t\t<term name=\"$c\"/>";
	}
	$crs2 = join("\n", @crs);
	
	my @amdts;
	my $amdts;
	foreach my $a (@AMENDMENTS) {
		push @amdts, "\t\t<amendment number=\"$a\"/>";
	}
	$amdts = join("\n", @amdts);

	# reformat summary	
	$SUMMARY =~ s/\(There (is|are) \d+ other summar(y|ies)\)//;
	$SUMMARY =~ s/<p>/\n/ig;
	$SUMMARY =~ s/<[^>]+?>//g;
	$SUMMARY =~ s/\&nbsp;/ /g;
	$SUMMARY =~ s/\&quot;/"/g;
	$SUMMARY =~ s/\&apos;/'/g;
	$SUMMARY =~ s/&\#(\d+);/chr($1)/ge;
	my $SUMMARY2 = HTMLify($SUMMARY);

	mkdir "../data/us/$SESSION/bills";
	mkdir "../data/us/$SESSION/bills.summary";

	open XML, ">$xfn";
	print XML <<EOF;
<bill session="$SESSION" type="$BILLTYPE" number="$BILLNUMBER" retreived_date="$now" updated="$updated">
	<status>$STATUSNOW</status>

	<introduced date="$INTRODUCED" datetime="$INTRODUCED2"/>
	<titles>
$ti2
	</titles>
	<sponsor $SPONSOR_ID/>
	<cosponsors$COSPONSORS_MISSING>
$cos2
	</cosponsors>
	<actions>
$act2
	</actions>
	<committees>
$com2
	</committees>
	<relatedbills>
$rb2
	</relatedbills>
	<subjects>
$crs2
	</subjects>
	<amendments>
$amdts
	</amendments>
	<summary>
	$SUMMARY2
	</summary>
</bill>
EOF
	close XML;

	open SUMMARY, ">", "../data/us/$SESSION/bills.summary/$BILLTYPE$BILLNUMBER.summary.xml";
	print SUMMARY FormatBillSummary($SUMMARY);
	close SUMMARY;
	
	IndexBill($SESSION, $BILLTYPE, $BILLNUMBER);
}

sub ParseAmendment {
	my $session = shift;
	my $chamber = shift;
	my $char = shift;
	my $number = shift;
	my $billtype = shift;
	my $billnumber = shift;	
	
	if ($ENV{SKIP_AMENDMENTS}) { return; }

	`mkdir -p ../data/us/$session/bills.amdt`;
	my $fn = "../data/us/$session/bills.amdt/$chamber$number.xml";

	sleep 1;
	print "Fetching amendment $session:$chamber$number\n" if (!$OUTPUT_ERRORS_ONLY);

	my $URL = "http://thomas.loc.gov/cgi-bin/bdquery/z?d$session:$chamber$char$number:";

	my $now = time;
	my $updated = Now();
	my $response = $UA->get($URL);
	if (!$response->is_success) {
		warn "Could not fetch $URL" .
                $response->code . " " .
                $response->message;
		return; }

	$HTTP_BYTES_FETCHED += length($response->content);
	my $content = $response->content;
	$content =~ s/\r//g;
	
	my $sequence = '';
	my $sponsor;
	my $offered;
	my $description;
	my $purpose;
	my $status = 'offered';
	my $statusdate;
	my $actions = '';
	
	my ($sptitle, $spname, $spstate, $spcommittee);
	
	foreach my $line (split(/\n/, $content)) {
		$line =~ s/<\/?font[^>]*>//g;
	
		if ($line =~ /^ \(A(\d\d\d)\)/) {
			$sequence = int($1);
		} elsif ($line =~ /<br>Sponsor: <a [^>]*>(Rep|Sen) ([^<]*)<\/a> \[(\w\w(-\d+)?)\]/) {
			($sptitle, $spname, $spstate) = ($1, $2, $3);
		} elsif ($line =~ /<br>Sponsor: <a [^>]*>((House|Senate) [^<]*)<\/a>/) {
			($spcommittee) = ($1);
		} elsif ($line =~ /\((submitted|offered) (\d+\/\d+\/\d\d\d\d)\)/) {
			$offered = $2;
			if ($sptitle eq "") { next; }
			$sponsor = PersonDBGetID(
				title => $sptitle,
				name => $spname,
				state => $spstate,
				when => ParseTime($offered));
			if (!defined($sponsor)) { warn "parsing amendment $session:$chamber$number: Unknown sponsor: $sptitle, $spname, $spstate (bill not fetched)"; return; }
		} elsif ($line =~ s/^<p>AMENDMENT DESCRIPTION:<br>//) {
			$description = $line;
		} elsif ($line =~ s/^<p>AMENDMENT PURPOSE:<br>//) {
			$purpose = $line;
			if ($description eq "") { $description = $purpose; }
		} elsif ($line =~ /<dt><strong>(\d+\/\d+\/\d\d\d\d( \d+:\d\d(am|pm))?):<\/strong><dd>([\w\W]*)/) {
			my ($when, $axn) = ($1, $4);
			$axn = HTMLify($axn);
			my $axnxml = ParseActionText($axn);

			my $statusdateattrs = "date=\"" . ParseTime($when) . "\" datetime=\"" . ParseDateTime($when) . "\"";
			
			if ($axn =~ /On agreeing to the .* amendment (\(.*\) )?(Agreed to|Failed) (without objection|by [^\.:]+|by recorded vote: (\d+) - (\d+)(, \d+ Present)? \(Roll no. (\d+)\))\./) {
				my ($passfail, $method) = ($2, $3);
				if ($passfail =~ /Agree/) { $passfail = "pass"; } else { $passfail = "fail"; }
				my $rollattr = "";
				if ($method =~ /recorded vote/) {
					$method =~ /\(Roll no. (\d+)\)/;
					my $roll = $1;
					$method = "roll";
					$rollattr = " roll=\"$roll\"";
					
					if (lc($chamber) eq "h") { GetHouseVote(YearFromDate(ParseTime($when)), $roll, 1); }
					else { warn "parsing amendment $session:$chamber$number: House-style vote on Senate amendment?"; }
				}
				$actions .= "\t\t<vote $statusdateattrs result=\"$passfail\" how=\"$method\"$rollattr>$axnxml</vote>\n";
				$status = $passfail;
				$statusdate = $statusdateattrs;
			} elsif ($axn =~ /(Motion to table )?Amendment SA \d+ (as modified )?(agreed to|not agreed to) in Senate by ([^\.:\-]+|Yea-Nay( Vote)?. (\d+) - (\d+)(, \d+ Present)?. Record Vote Number: (\d+))\./i) {
				my ($totable, $passfail, $method) = ($1, $3, $4);
				if ($passfail !~ /not/) { $passfail = "pass"; } else { $passfail = "fail"; }

				if ($totable) {
					if ($passfail eq 'fail') { next; }
					$passfail = 'fail'; # i.e. treat a passed motion to table as a failed vote on accepting the amendment
				}

				my $rollattr = "";
				if ($method =~ /Yea-Nay/) {
					$method =~ /Record Vote Number: (\d+)/;
					my $roll = $1;
					$method = "roll";
					$rollattr = " roll=\"$roll\"";
					
					if (lc($chamber) eq "s") { GetSenateVote($session, SubSessionFromDate(ParseTime($when)), YearFromDate(ParseTime($when)), $roll, 1); }
					else { warn "parsing amendment $session:$chamber$number: Senate-style vote on House amendment?"; }
				}
				$actions .= "\t\t<vote $statusdateattrs result=\"$passfail\" how=\"$method\"$rollattr>$axnxml</vote>\n";
				$status = $passfail;
				$statusdate = $statusdateattrs;
			} elsif ($axn =~ /Proposed amendment SA \d+ withdrawn in Senate./
				|| $axn =~ /the [\w\W]+ amendment was withdrawn./) {
				$actions .= "\t\t<withdrawn $statusdateattrs>$axnxml</withdrawn>\n";
				$status = "withdrawn";
				$statusdate = $statusdateattrs;
			} else {
				$actions .= "\t\t<action $statusdateattrs>$axnxml</action>\n";
			}
		}
	}
	
	if (!defined($purpose)) { $purpose = "Amendment information not available."; $description = $purpose; }
	
	if ((!defined($sponsor) && !defined($spcommittee)) || !defined($offered)) {
		print "Parse failed on amendment: $URL\n";
		return;
	}
	
	$description = HTMLify(ToUTF8($description));
	$purpose = HTMLify(ToUTF8($purpose));
	
	$offered = "date=\"" . ParseTime($offered) . "\" datetime=\"" . ParseDateTime($offered) . "\"";
	if ($status eq "offered") { $statusdate = $offered; }

	my $sponsorxml;
	if (defined($sponsor)) { $sponsorxml = "id=\"$sponsor\""; }
	else { $sponsorxml = "committee=\"" . htmlify($spcommittee) . "\""; }

	open XML, ">", "$fn";
	print XML <<EOF;
<amendment session="$session" chamber="$chamber" number="$number" retreived_date="$now" updated="$updated">
	<amends type="$billtype" number="$billnumber" sequence="$sequence"/>
	<status $statusdate>$status</status>
	<sponsor $sponsorxml/>
	<offered $offered/>
	<description>$description</description>
	<purpose>$purpose</purpose>
	<actions>
$actions
	</actions>
</amendment>
EOF
	close XML;
}

sub HTMLify {
	my $t = $_[0];

	$t =~ s/<\/?P>/\n/gi;
	$t =~ s/<BR\s*\/?>/\n/gi;
	$t =~ s/<\/?[^>]+>//gi;

	$t =~ s/&nbsp;/ /gi;

	return ToUTF8(htmlify($t));
}

sub FormatBillSummary {
	my $summary = shift;

	$summary =~ s/\&/\&amp;/g;
	$summary =~ s/</\&lt;/g;
	$summary =~ s/>/\&gt;/g;		
	
	my @splits = split(/(Division|Title|Subtitle|Part|Chapter)\s+(\w+)\s*: (.*?) - |\((Sec)\. (\d+)\)|(\n)/, $summary);
	
	my %secorder = (Division => 1, Title => 2, Subtitle => 3, Part 
	=> 4, Chapter => 5, Section => 6, Paragraph => 7);
	
	my $ret;
	my @stack;
	my @idstack;
	
	$ret .= "<Paragraph type=\"Overview\">";
	push @stack, "Paragraph";
	
	while (scalar(@splits) > 0) {
		my $s = shift(@splits);
		
		if ($s eq "") {
		} elsif ($s =~ /^(Division|Title|Subtitle|Part|Chapter)$/ or $s eq "Sec") {
			my $sid = shift(@splits);
			my $sname;
			if ($s eq "Sec") {
				$s = "Section";
				$sname = "";
			} else {
				$sname = shift(@splits);
			}

			while (scalar(@stack) > 0 && $secorder{$s} <= $secorder{$stack[scalar(@stack)-1]}) {
				$ret .= "</" . pop(@stack) . ">"; 
				pop @idstack;
			}

			if ($sname ne "") { $sname = "name=\"$sname\""; }

			my $id = "$s-$sid";
			my $id2 = join(":", @idstack);

			$ret .= "<$s number=\"$sid\" $sname id=\"$id2\">";

			push @stack, $s;
			push @idstack, $id;

		} elsif ($s eq "\n") {
		} else {
			while (scalar(@stack) > 0 && $secorder{Paragraph} <= $secorder{$stack[scalar(@stack)-1]}) { $ret .= "</" . pop(@stack) . ">"; }
			
			$ret .= "<Paragraph>$s";
			push @stack, 'Paragraph';
		}
	}

	while (scalar(@stack) > 0) { $ret .= "</" . pop(@stack) . ">"; }
	
	$ret = "<summary>$ret</summary>";
	return ToUTF8($ret);

	#return $XMLPARSER->parse_string($ret)->findnodes('.');
}

sub ParseActionText {
	my $text = shift;

	my $ret;
	my $crref = "([^:()]*): (CR ([HS]\\d+(-\\d+)?(,\\s*)?)+)";
	# prohibiting parens in the label excludes (Roll Call:...)
	
	if ($text =~ s/\s*\((($crref;?\s*)+)\)$//) {
		my $r = $1;
		my @refs = split(/;\s*/, $r);
		foreach $r (@refs) {
			$r =~ /$crref/;
			my ($label, $ref) = ($1, $2);
			$label = HTMLify($label);
			$ref = HTMLify($ref);
			$ret .= "<reference label=\"$label\" ref=\"$ref\"/>";
		}
	}
	
	return "<text>" . HTMLify($text) . "</text>" . $ret;
}

sub CompareDates {
	my ($a, $b) = @_;
	# Compare two dates, but if one doesn't have a time,
	# then only compare the date portions.
	if ($a !~ /T/) { $b =~ s/T.*//; }
	if ($b !~ /T/) { $a =~ s/T.*//; }
	return $a cmp $b;
}
