#!/usr/bin/perl

require "db.pl";
require "general.pl";
require "persondb.pl";

$FIRSTSESSION = 93;
$SESSION = SessionFromDate(time);

GovDBOpen();

$testing = 0;

if (!$testing) {
	DBDelete('committees', [1]);
	DBDelete('people_committees', [1]);
}

$xml = $XMLPARSER->parse_string("<committees/>");

GetThomasNames();
GetSenateCommittees();
GetHouseCommittees();
AddMissingRecords();

DBClose();

if (!$testing) {
	$xml->toFile("../data/us/$SESSION/committees.xml", 1);
} else {
	print $xml->toString(1);
}

sub GetThomasNames {
	# Get the names Thomas uses for committees.
	for my $session ($FIRSTSESSION..$SESSION) {
		my $sessionurl = sprintf("%03d", $session);
		
		sleep(1);
		print "Getting THOMAS committee list for $session.\n";
		my $response = $UA->get("http://thomas.loc.gov/bss/d${sessionurl}query.html");
		if (!$response->is_success) { warn "Could not get THOMAS committee list."; last; }
		my $html = "" . $response->content;
		
		my $cct = 0;
		while ($html =~ /<option value="\s*([^">]*)\{([hs])([a-z]+)([0-9]+)\}">-*.*<\/option>/g) {
			my ($name, $ch, $id, $subid) = ($1, $2, $3, $4);
			if ($subid == 0) {
				$Committee{"$ch$id"}{$session}{thomasname} = $name;
			} else {
				$Committee{"$ch$id"}{$session}{subs}{int($subid)}{thomasname} = $name;
			}
			$cct++;
		}
		
		if ($cct == 0) { print "No committees found!\n"; }
	}
}

sub GetSenateCommittees {
	sleep(1);
	$response = $UA->get('http://www.senate.gov/pagelayout/committees/b_three_sections_with_teasers/membership.htm');
	if (!$response->is_success) { warn "Could not get Senate committee list."; }
	$html = $response->content;
	
	while ($html =~ /="\/general\/committee_membership\/committee_memberships_(\w+?)\.htm">(.*?)</g) {
	
		my $code = $1;
		my $name = $2;
	
		my $ctype = 'Senate';
		if ($name =~ /^Joint/) {
			$ctype = 'Joint';
		} elsif ($name !~ /Senate/) {
			$name = "Senate $name";
		}
	
		if ($name =~ /Commission/) { next; }
	
		print "$name\n";
	
		my $thomasname = $Committee{lc($code)}{$SESSION}{thomasname};
		if ($thomasname eq "") { print " Thomas Name not found ($code).\n"; }
		$Committee{lc($code)}{covered} = 1;
	
		my $cxml = AddXmlNode($xml->documentElement, 'committee',
			type => lc($ctype), code => $code, displayname => $name);
		AddCommitteeNames($cxml, $code);
	
		#sleep(1);
		$response = $UA->get('http://www.senate.gov/general/committee_membership/committee_memberships_' . $code . '.htm');
		if (!$response->is_success) { die "Could not get Senate committee info $code."; }
		my $html2 = $response->content;
		$html2 =~ s/<\/position>\r?\n/<\/position>/g;
		$html2 =~ s/<\/state>\)\s+,/<\/state>\),/g;
	
		my $url;
		if ($html2 =~ /<span class="contenttext"><a href="(http:\/\/.*?senate.gov\/.*?)">/) {
			$url = $1;
			$cxml->setAttribute('url', $url);
		}
	
		if ($thomasname eq "") { $thomasname = $name; } # fallback
		else { $thomasname = "$ctype $thomasname"; }
		DBInsert(committees, id => $code, type => lc($ctype), displayname => $name, thomasname => $thomasname, url => $url) if (!$testing);
	
		my @lines = split(/\r?\n/, $html2);
		my $subcode = $code;
		my $subid = undef;
		my $subname = undef;
		my $subctr = 0;
		my $afterMain = 0;
		my $scxml = $cxml;
		foreach my $line (@lines) {
			if ($line =~ /<A NAME="([^"]+)">/i) {
				$subcode = $1;
				if ($subcode !~ /^$code(\d+)$/) { die $subcode; }
				$subid = int($1);
				$subcode = "$code$subid";
			}
	
			if ($line =~ /<subcommittee_name>(.*)<\/subcommittee_name>/ && $afterMain) {
				$subname = $1;
				$subctr++;
				$subname =~ s/^(Permanent )?Subcommittee on //;
				$subname =~ s/  / /g;
				print "  $subname\n";
				my $thomasnamesub = $Committee{lc($code)}{$SESSION}{subs}{$subid}{thomasname};
				#if ($thomasnamesub eq "") { print "    Thomas Name not found ($subcode).\n"; }
				$scxml = AddXmlNode($cxml, 'subcommittee', code => $subid, displayname => $subname);
				AddCommitteeNames($scxml, $code, $subid);
	
				if ($thomasnamesub eq "") { $thomasnamesub = $subname; } # fallback
				DBInsert(committees, id => $subcode, parent => $code, displayname => $subname, thomasname => $thomasnamesub) if (!$testing);
	
				next;
			}
	
			if ($line =~ /<pub_last>(.*)<\/pub_last>, <pub_first>(.*)<\/pub_first> \(<state>(.*)<\/state>\)(, <position>(.*)<\/position>)?/) {
				my ($l, $f, $s, $p) = ($1, $2, $3, $5);
	
				my $pid = PersonDBGetID(name => "$l, $f", title => "sen", state => "$s", when => "now");
				if (!$pid) { warn "Unknown person: $l, $f ($s)"; next; }
	
				if ($p eq "Ranking") { $p = "Ranking Member"; }
	
				DBInsert(people_committees,
					personid => $pid,
					committeeid => $subcode,
					type => $ctype,
					name => $name,
					subname => $subname,
					role => $p,
					senatecode => ($subname eq '' ? $code : "$code-$subctr"))
					   if (!$testing);
				$afterMain = 1;
	
				AddXmlNode($scxml, 'member', name => "$f $l", id => $pid, role => $p);
			} elsif ($line =~ s/^\s+(<\/td>)?<td nowrap="nowrap">//) {
				foreach my $x (split(/<br>/, $line)) {
					if ($x !~ /(.*?) \((\w\w)\)(, <position>(.*?)<\/position>)?/) { warn $x; next; }
					my ($pname, $state, $position) = ($1, $2, $4);
	
					my $pid = PersonDBGetID(name => $pname, title => "sen", state => $state, when => "now");
					if (!$pid) { warn "Unknown person: $x"; next; }
	
					if ($position eq "Ranking") { $position = "Ranking Member"; }
	
					DBInsert(people_committees,
						personid => $pid,
						committeeid => $subcode,
						type => $ctype,
						name => $name,
						subname => $subname,
						role => $position,
						senatecode => ($subname eq '' ? $code : "$code-$subctr"))
						    if (!$testing);
	
					AddXmlNode($scxml, 'member', name => "$pname", id => $pid, role => $p);
				}
				$afterMain = 1;
			}
		}
	}
}

sub GetHouseCommittees {
	sleep(1);
	$response = $UA->get('http://clerk.house.gov/committee_info/index.html');
	if (!$response->is_success) { warn "Could not get House committee list."; }
	$html = $response->content;
	
	while ($html =~ /\/committee_info\/index\.html\?comcode=([A-Z]{3})00">(.*?)<\//g) {
		my $housecode = $1;
		my $name = $2;
		
		my $ctype = 'House';
		if ($name =~ /^Joint/) {
			$ctype = 'Joint';
		} elsif ($name !~ /^House/) {
			$name = "House $name";
		}
		
		print "$name\n";
		
		my $ourcode = $housecode;
		$ourcode =~ s/^H/HS/;

		if ($housecode eq 'JEC') { $ourcode = 'JSEC'; }
		if ($housecode eq 'HJL') { $ourcode = 'JSLC'; }
		if ($housecode eq 'HJP') { $ourcode = 'JSPR'; }
		if ($housecode eq 'HIT') { $ourcode = 'JSTX'; }
	
		my $thomasname = $Committee{lc($ourcode)}{$SESSION}{thomasname};
		if ($thomasname eq "") { print " Thomas Name not found ($ourcode).\n"; }
		
		my $cxml;
		if (!$Committee{lc($ourcode)}{covered}) {
			$Committee{lc($ourcode)}{covered} = 1;
	
			$cxml = AddXmlNode($xml->documentElement, 'committee',
				type => lc($ctype), code => $ourcode, displayname => $name);
			AddCommitteeNames($cxml, $ourcode);
			
			if ($thomasname eq "") { $thomasname = $name; } # fallback
			else { $thomasname = "$ctype $thomasname"; }
			DBInsert(committees, id => $ourcode, type => lc($ctype), displayname => $name, thomasname => $thomasname, url => undef) if (!$testing);
		} else {
			# for joint committees, get the node from the senate
			($cxml) = $xml->documentElement->findnodes("committee[\@code='$ourcode']");
		}
		
		sleep(1);
		$response = $UA->get('http://clerk.house.gov/committee_info/index.html?comcode=' . $housecode . '00');
		if (!$response->is_success) { warn "Could not get House committee info for $ourcode."; }
		$html2 = $response->content;
		
		# cleanup for bad line format in joint committee pages
		$html2 =~ s/(mem_contact_info[^>]+>)\s+/$1/g;
		$html2 =~ s/<\/li><li>/<\/li>\n<li>/g;
		
		my @subcoms;
		my %subcomnames;
		while ($html2 =~ /href="index.html\?subcomcode=${housecode}(\d\d)">(.*?)<\//g) {
			my $scid = $1;
			my $scname = $2;
			
			$scname =~ s/ Subcommittee$//i;
			
			push @subcoms, $scid;
			$subcomnames{$scid} = $scname;
		}
		
		foreach my $scid (undef, @subcoms) {
			my $ccode;
			my $subname;
			my $scxml;
			if (!defined($scid)) {
				# looking at main committee membership
				$ccode = $ourcode;
				$subname = undef;
				$scxml = $cxml;
			} else {
				# fetch info for this subcommittee

				sleep(1);
				$response = $UA->get('http://clerk.house.gov/committee_info/index.html?subcomcode=' . $housecode . $scid);
				if (!$response->is_success) { warn "Could not get House subcommittee info for $ourcode$scid."; }
				$html2 = $response->content;

				$ccode = $ourcode . $scid;
				$subname = $subcomnames{$scid};

				my $thomasnamesub = $Committee{lc($ourcode)}{$SESSION}{subs}{$scid}{thomasname};
				#if ($thomasnamesub eq "") { print "    Thomas Name not found ($ourcode$scid).\n"; }
				$scxml = AddXmlNode($cxml, 'subcommittee', code => $scid, displayname => $subname);
				AddCommitteeNames($scxml, $ourcode, $scid);
	
				if ($thomasnamesub eq "") { $thomasnamesub = $subname; } # fallback
				DBInsert(committees, id => "$ourcode$scid", parent => $ourcode, displayname => $subname, thomasname => $thomasnamesub) if (!$testing);
			}

			my @lines = split(/[\n\r]+/, $html2);
			my $state = 0;
			my $rank = -1;
			foreach my $line (@lines) {
				$line =~ s/<\/?em>//g;
			
				if ($line =~ /<div id="secondary_group">/) {
					$state = 2;
					$rank = 1;
				}
				if ($line =~ /<div id="primary_group">/) {
					$state = 1;
					$rank = 1;
				}
				
				if ($line =~ /mem_contact_info\.html\?statdis=([^"]+)">(.*?)\s*<\/a>(, \w\w, ([\w\s]+))?/) {
					my $statedist = $1;
					my $pname = $2;
					my $position = $4;
					
					$pname = ToUTF8($pname);
					$pname =~ s/  +/ /g;
					
					if ($rank++ == 1 && $ctype ne 'Joint') {
						if ($state == 1) { $position = "Chair"; }
						elsif ($state == 2) { $position = "Ranking Member"; }
						else { die; }
					}
					
					if ($statedist !~ /([A-Z]{2})([0-9]{2})/) { die "State/district $statedist"; }
					my $state = $1;
					my $dist = $2;
					
					
					my $pid = PersonDBGetID(name => $pname, title => "rep", state => "$state", district => $dist, when => "now", nameformat => 'firstlast');
					if (!$pid) { warn "Unknown person: $pname ($statedist)"; next; }
		
					DBInsert(people_committees,
						personid => $pid,
						committeeid => $ccode,
						type => $ctype,
						name => $name,
						subname => $subname,
						role => $position)
						   if (!$testing);
		
					AddXmlNode($scxml, 'member', name => $pname, id => $pid, role => $position);
				}
			}
		}
		
	}
}

sub AddMissingRecords {
	# then add records that we saw on Thomas but not on the Senate/House sites (cause House took ages to update at the start of 2007)
	foreach my $code (keys(%Committee)) {
		if ($Committee{$code}{covered}) { next; }
		
		my $ctype;
		if ($code =~ /^h/) { $ctype = 'House'; } else { $ctype = 'Senate'; }
		
		my $cname;
		for my $session ($FIRSTSESSION..$SESSION) {
			if ($Committee{$code}{$session}{thomasname} ne "") {
				$cname = $Committee{$code}{$session}{thomasname};
			}
		}
	
		my $displayname = $ctype . " Committee on " . $cname;
		
		my $cxml = AddXmlNode($xml->documentElement, 'committee',
			type => lc($ctype), code => uc($code), displayname => $displayname);
		AddCommitteeNames($cxml, uc($code));
		
		if (!$Committee{$code}{$SESSION}{thomasname}) {
			$cxml->setAttribute("obsolete", "1");
		} else {
			DBInsert(committees, id => uc($code), type => lc($ctype),
				displayname => $displayname, thomasname => $Committee{$code}{$SESSION}{thomasname})
				     if (!$testing);
		}
	}
}

sub AddXmlNode {
	my $parent = shift;
	my $name = shift;

	my $node = $parent->ownerDocument->createElement($name);
	$parent->appendChild($node);
	while (scalar(@_) > 0) {
		my $k = shift;
		my $v = shift;
		if ($v eq '') { next; }
		$node->setAttribute($k, $v);
	}

	return $node;
}

sub AddCommitteeNames {
	my $cxml = shift;
	my $code = shift;
	my $subid = shift;
	
	my $ctype;
	if ($code =~ /^J/) { return; } # no Thomas names for joint committees
	if ($code =~ /^H/) { $ctype = 'House'; } else { $ctype = 'Senate'; }

	my $names = $cxml->ownerDocument->createElement("thomas-names");
	
	my $first = 1;
	for my $session ($FIRSTSESSION..$SESSION) {
		my $tname;
		if (!$subid) { $tname = $Committee{lc($code)}{$session}{thomasname}; }
		else { $tname = $Committee{lc($code)}{$session}{subs}{int($subid)}{thomasname}; }
		if ($tname eq '') { next; }
		if (!$subid) { $tname = $ctype . " " . $tname; }
		my $namenode = $cxml->ownerDocument->createElement("name");
		$namenode->setAttribute('session', $session);
		$names->appendChild($namenode);
		$namenode->appendText($tname);
		if ($first) { $cxml->appendChild($names); $first = 0; } # add the first time we see a name
	}
}
