#!/usr/bin/perl

require "general.pl";
require "db.pl";

if ($ARGV[0] eq "POPULARMONITORS") {
	GovDBOpen();
	GetPopularMonitors(); 
	DBClose();
}

1;

sub GetPopularMonitors {
	my %Monitors;
	my %billmatrix;
	my %billcount;
	my %monmatrix;
	
	# get a count of subscribers for each monitor, which we need
	# to build the TFIDF.
	foreach my $monitors (DBSelectVector('users', ['monitors'])) {
		foreach my $mon (split(/,/, $monitors)) {
			if ($mon eq "") { next; }
			if ($mon =~ /^(misc|option|blog|user|meta):/) { next; }
			$Monitors{$mon}++;
		}
	}
			
	# Build the bill (on disk) and monitor (in database) matrix.
	foreach my $monitors (DBSelectVector('users', ['monitors'])) {
		my @mons;
		my @bills;
		foreach my $mon (split(/,/, $monitors)) {
			if ($mon eq "") { next; }
			if ($mon =~ /^(misc|option|blog|user|meta):/) { next; }
			push @mons, $mon;
			if ($mon =~ /^bill:(.*)/) {
				push @bills, $1;
			}
		}
		
		# monitor matrix
		if (scalar(@mons) < 30) { # too many just creates too many records
			for my $m1 (@mons) {
				for my $m2 (@mons) {
					if ($m1 eq $m2) { next; }
					my $idf = 1.0 / $Monitors{$m2};
					$monmatrix{$m1}{$m2}{count}++;
					$monmatrix{$m1}{$m2}{tfidf} += $idf;
				}
			}
		}
		
		# bill matrix
		for my $b1 (@bills) {
			$billcount{$b1}++;
			for my $b2 (@bills) {
				if ($b1 eq $b2) { next; }
				$billmatrix{$b1}{$b2}++;
			}
		}
	}

	open DATA, ">../data/misc/monitors.popular.xml";
	print DATA "<monitors>\n";

	my @monitors = reverse( sort { $Monitors{$a} <=> $Monitors{$b} } keys(%Monitors) );
	foreach my $mon (@monitors) {
		$num = $Monitors{$mon};
		$mon = htmlify($mon);
		if ($num < 20) { last; }
		print DATA "\t<monitor name=\"$mon\" users=\"$num\"/>\n";
	}

	print DATA "</monitors>\n";
	close DATA;

	# Add the monitor matrix to the database.
	DBDelete(monitormatrix, [1]);
	for my $m1 (keys(%monmatrix)) {
		for my $m2 (keys(%{ $monmatrix{$m1} })) {
			# If there is a low count, then weight the TFIDF down.
			if ($monmatrix{$m1}{$m2}{count} < 10) {
				$monmatrix{$m1}{$m2}{tfidf} *= sqrt($monmatrix{$m1}{$m2}{count} / 10);
			}
			
			if ($monmatrix{$m1}{$m2}{tfidf} < .2) { next; }
			DBExecute("INSERT DELAYED INTO monitormatrix (monitor1, monitor2, count, tfidf) VALUES (\"$m1\", \"$m2\", $monmatrix{$m1}{$m2}{count}, $monmatrix{$m1}{$m2}{tfidf})");
		}
	}
	
	# Write out the bill matrix.
	open DATA, ">../data/misc/monitors.billmatrix.xml";
	print DATA "<bill-matrix>\n";
	my @bills = keys(%billmatrix);
	@bills = sort({ $billcount{$b} <=> $billcount{$a} } @bills);
	for my $bill (@bills) {
		if ($billcount{$bill} < 10) { next; }
		print DATA "\t<bill id=\"$bill\" count=\"$billcount{$bill}\">\n";
		my @bills2 = keys(%{ $billmatrix{$bill} });
		@bills2 = sort({ $billmatrix{$bill}{$b} <=> $billmatrix{$bill}{$a} } @bills2);
		for my $bill2 (@bills2) {
			my $ct = $billmatrix{$bill}{$bill2};
			if ($ct <= 2 || $ct <= $billmatrix{$bill}{$bills2[0]}/4) { next; }
			print DATA "\t\t<bill id=\"$bill2\" count=\"$ct\">\n";
		}
		print DATA "\t</bill>\n";
	}
	print DATA "</bill-matrix>";
	close DATA;
}
