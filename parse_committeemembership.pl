#!/usr/bin/perl

require "db.pl";
require "general.pl";
require "persondb.pl";

$SESSION = $ARGV[0];
if (!$SESSION) { die; }

GovDBOpen();

$testing = 0;

if (!$testing) {
	DBDelete('committees', [1]);
	DBDelete('people_committees', [1]);
}

$xml = $XMLPARSER->parse_string("<committees/>");

GetHouseCommittees();
GetSenateCommittees();

DBClose();

if (!$testing) {
	$xml->toFile("../data/us/$SESSION/committees.xml", 1);
} else {
	print $xml->toString(1);
}

sub GetSenateCommittees {
	my ($html, $mtime) = Download('http://www.senate.gov/pagelayout/committees/b_three_sections_with_teasers/membership.htm');
	if (!$html) { return; }
	
	while ($html =~ /="\/general\/committee_membership\/committee_memberships_(\w+?)\.htm">(.*?)</g) {
	
		my $code = $1;
		my $name = $2;
	
		my $ctype = 'Senate';
		if ($name =~ /^Joint/) {
			$ctype = 'Joint';
		} elsif ($name !~ /Senate/) {
			$name = "Senate $name";
		}
	
		print "$name\n";
	
		$Committee{lc($code)}{covered} = 1;
	
		my $cxml = AddXmlNode($xml->documentElement, 'committee',
			type => lc($ctype), code => $code, displayname => $name);
	
		my ($html2, $mtime2) = Download('http://www.senate.gov/general/committee_membership/committee_memberships_' . $code . '.htm');
		if (!$html2) { die; }
		$html2 =~ s/<\/position>\r?\n/<\/position>/g;
		$html2 =~ s/<\/state>\)\s+,/<\/state>\),/g;
	
		my $url;
		if ($html2 =~ /<span class="contenttext"><a href="(http:\/\/.*?senate.gov\/.*?)">/) {
			$url = $1;
			$cxml->setAttribute('url', $url);
		}
	
		DBInsert(committees, id => $code, type => lc($ctype), displayname => $name, url => $url) if (!$testing);
	
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
				$scxml = AddXmlNode($cxml, 'subcommittee', code => $subid, displayname => $subname);
	
				DBInsert(committees, id => $subcode, parent => $code, displayname => $subname) if (!$testing);
	
				next;
			}
	
			if ($line =~ /<pub_last>(.*)<\/pub_last>, <pub_first>(.*)<\/pub_first> \(<state>(.*)<\/state>\)(, <position>(.*)<\/position>)?/) {
				my ($l, $f, $s, $p) = ($1, $2, $3, $5);
				$p =~ s/ +$//;
	
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
	
				AddXmlNode($scxml, 'member', id => $pid, role => $p);
					#name => "$f $l",
			} elsif ($line =~ s/^\s+(<\/td>)?<td valign="top" nowrap>//) {
				foreach my $x (split(/<br>/, $line)) {
					if ($x !~ /(.*?)\s+\((\w\w)\)(, <position>(.*?)<\/position>)?/) { warn $x; next; }
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
	
					AddXmlNode($scxml, 'member', id => $pid, role => $position);
						###name => "$pname",
				}
				$afterMain = 1;
			}
		}
	}
}

sub GetHouseCommittees_Alt {
	for my $c ($XMLPARSER->parse_file("../data/us/committees.xml")->findnodes("committees/committee[not(\@type='senate') and not(\@obsolete='1')]")) {
		my $housecode = $c->getAttribute('code');
		if ($housecode eq 'JSEC') { $housecode = 'JEC'; }
		if ($housecode eq 'JSLC') { $housecode = 'HJL'; }
		if ($housecode eq 'JSPR') { $housecode = 'HJP'; }
		if ($housecode eq 'JSTX') { $housecode = 'HIT'; }
		if ($housecode eq 'HSHM') { $housecode = 'HHM'; }
		if ($housecode eq 'HLIG') { $housecode = 'HIG'; }
		
		$housecode =~ s/^HS/H/;

		if ($housecode eq "JCSE" || $housecode eq "HGW") { next; }
		
		GetHouseCommittees2(
			$c->getAttribute('displayname'),
			$housecode,
			$c->getAttribute('code'),
			$c->getAttribute('type'));
	}
}

sub GetHouseCommittees {
	my ($html, $mtime) = Download('http://clerk.house.gov/committee_info/index.aspx');
	if (!$html) { return; }
	
	while ($html =~ /\/committee_info\/index\.aspx\?comcode=([A-Z]{2})00">(.*?)<\//g) {
		my $housecode = $1;
		my $name = $2;
		
		my $ctype = 'House';
		if ($name =~ /^Joint/) {
			$ctype = 'Joint';
		} elsif ($name !~ /^House/) {
			$name = "House $name";
		}

		my $ourcode = "HS" . $housecode;

		#if ($housecode eq 'JEC') { $ourcode = 'JSEC'; }
		#if ($housecode eq 'HJL') { $ourcode = 'JSLC'; }
		#if ($housecode eq 'HJP') { $ourcode = 'JSPR'; }
		#if ($housecode eq 'HIT') { $ourcode = 'JSTX'; }
		#if ($housecode eq 'HM0') { $ourcode = 'HSHM'; }
		#if ($housecode eq 'HIG') { $ourcode = 'HLIG'; }
		
		if ($ourcode eq 'HSIG') { $ourcode = 'HLIG'; }
		if ($ourcode eq 'HSSO') { $ourcode = 'HLET'; }
	
		GetHouseCommittees2($name, $housecode, $ourcode, $ctype);
	}
}

sub GetHouseCommittees2 {
		my ($name, $housecode, $ourcode, $ctype) = @_;
		
		print "$ourcode $housecode $name\n";
		
		my $cxml;
		if (!$Committee{lc($ourcode)}{covered}) {
			$Committee{lc($ourcode)}{covered} = 1;
	
			$cxml = AddXmlNode($xml->documentElement, 'committee',
				type => lc($ctype), code => $ourcode, displayname => $name);
			
			DBInsert(committees, id => $ourcode, type => lc($ctype), displayname => $name, url => undef) if (!$testing);
		} else {
			# for joint committees, get the node from the senate
			($cxml) = $xml->documentElement->findnodes("committee[\@code='$ourcode']");
		}
		
		#print 'http://clerk.house.gov/committee_info/index.aspx?comcode=' . $housecode . '00' . "\n";
		my ($html2, $mtime2) = Download('http://clerk.house.gov/committee_info/index.aspx?comcode=' . $housecode . '00');
		if (!$html2) { die $housecode; }
		if ($html2 !~ /Committee on|Joint Economic/) { die $housecode; }
		
		# cleanup for bad line format in joint committee pages
		$html2 =~ s/(mem_contact_info[^>]+>)\s+/$1/g;
		$html2 =~ s/<\/li><li>/<\/li>\n<li>/g;
		
		my @subcoms;
		my %subcomnames;
		while ($html2 =~ /href="\/committee_info\/index.aspx\?subcomcode=${housecode}(\d\d)">(.*)/g) {
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

				print 'http://clerk.house.gov/committee_info/index.aspx?subcomcode=' . $housecode . $scid . "\n";
				($html2, $mtime2) = Download('http://clerk.house.gov/committee_info/index.aspx?subcomcode=' . $housecode . $scid);
				if (!$html2) { die; }

				$ccode = $ourcode . $scid;
				$subname = $subcomnames{$scid};

				$scxml = AddXmlNode($cxml, 'subcommittee', code => $scid, displayname => $subname);
	
				DBInsert(committees, id => "$ourcode$scid", parent => $ourcode, displayname => $subname) if (!$testing);
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
				
				if ($line =~ /mem_contact_info\.aspx\?statdis=([^"]+)"[^>]*>(.*?)\s*<\/a>(, \w\w, ([\w\s]+))?/) {
					my $statedist = $1;
					my $pname = $2;
					my $position = $4;
					
					$pname =~ s/  +/ /g;
					
					if ($rank++ == 1 && $ctype ne 'Joint') {
						if ($state == 1) { $position = "Chair"; }
						elsif ($state == 2) { $position = "Ranking Member"; }
						else { die; }
					}
					
					if ($statedist !~ /([A-Z]{2})([0-9]{2})/) { die "State/district $statedist"; }
					my $state = $1;
					my $dist = int($2);
					
					
					my $pid = PersonDBGetID(name => $pname, title => "rep", state => "$state", district => $dist, when => "now", nameformat => 'firstlast');
					if ($pname eq "Mary Bono Mack") { $pid = 400039; }
					if (!$pid) { die "Unknown person: $pname ($state|$dist)"; next; }
		
					DBInsert(people_committees,
						personid => $pid,
						committeeid => $ccode,
						type => $ctype,
						name => $name,
						subname => $subname,
						role => $position)
						   if (!$testing);
		
					AddXmlNode($scxml, 'member', id => $pid, role => $position);
						##name => $pname,
				}
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

