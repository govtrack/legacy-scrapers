use Parse::AccessLogEntry;
use URI;
use URI::QueryParam;
use XML::LibXML;

require "util.pl";  

$p = Parse::AccessLogEntry->new();

for my $wd ('house', 'senate', 'congress', 'act', 'bill', 'bills', 'resolution', 'legislation', 's.', 's', 's.res.', 's.j.res.', 's.con.res.', 'h.r.', 'hr', 'h.res.', 'h.con.res.', 'h.j.res.', 'vote',
	'of', 'what', 'sponsor', 'status', 'govtrack') {
	$stopwords{$wd} = 1;
}

while (!eof(STDIN)) {
	$line = <STDIN>;
	$log = $p->parse($line);
	
	if (!$first_date) { $first_date = $log->{date}; }
	
	my $r = $log->{refer};
	if ($r eq '-') { next; }
	
	my $f = $log->{file};
	if ($f !~ m%^/congress/bill\.xpd\?bill=((h|hj|hc|hr|s|sj|sc|sr)\d+-\d+)$%) { next; }
	$f = $1;
	
	$r = URI->new($r);
	eval { # parse may fail
		if ($r->host =~ /google/) {
			$F{$f}++;

			$q = lc($r->query_param('q'));
			@wds = split(/\s+/, $q);
			@stops = ();
			for my $wd (@wds) {
				push @stops, ($stopwords{$wd} || ($wd =~ /^[\d.]+:?$/) || ($wd =~ (/^[hs][a-z\.]*[- ]?\d+$/i))) ? 1 : '';
			}
			for $i (0..scalar(@wds)-1) {
				for $j ($i..scalar(@wds)-1) {
					$wd = join(" ", @wds[$i..$j]);
					if (join("", @stops[$i..$j]) ne "") { next; }
					if ($stopwords{$wd}) { next; }

					$wd =~ s/-/ /g;
					$wd =~ s/["()]//g;

					$Q{$f}{$wd} += sqrt(length($wd));
				}
			}
			
			$ctr++;
			if ($ctr == 5000) { last; }
		}
	};
}

$doc = $XMLPARSER->parse_string('<popular-bills/>');
$doc->documentElement->setAttribute('last-updated', Now());
$doc->documentElement->setAttribute('log-start', $first_date);

$ctr = 0;
@sorted = sort { $F{$b} <=> $F{$a} } keys %F; 
for my $f (@sorted) {
	#print "$F{$f} $f\n";
	my $fnode = $doc->createElement('bill');
	$fnode->setAttribute('id', $f);
	$fnode->setAttribute('hits', $F{$f});
	$doc->documentElement->appendChild($fnode);
	
	$ctr2 = 0;
	@sorted2 = sort { $Q{$f}{$b} <=> $Q{$f}{$a} } keys %{$Q{$f}}; 
	for my $i (0..scalar(@sorted2)-1) {
		my $q = $sorted2[$i];
		
		if ($Q{$f}{$q} < $Q{$f}{$sorted2[0]}/10) { last; }

		# If this term contains or is contained in a term we already saw, skip it.
		my $ok = 1;
		for my $i2 (0..$i-1) {
			my $q2 = $sorted2[$i2];
			if (index($q, $q2) >=0 || index($q2, $q) >= 0) { $ok = 0; last; }
		}
		if (!$ok) { next; }
	
		#print "   $Q{$f}{$q} <$q>\n";

		my $qnode = $doc->createElement('search-string');
		$qnode->setAttribute('score', $Q{$f}{$q});
		$qnode->appendText($q);
		$fnode->appendChild($qnode);
		
		if ($ctr2++ == 20) { last; }
	}

	if ($ctr++ == 100) { last; }
}

print $doc->toFile("../data/misc/popularbills.xml", 1);

