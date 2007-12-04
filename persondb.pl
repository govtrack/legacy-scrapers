require "db.pl";
require "util.pl";

my @ShortNames = (
	[tom, thomas],
	[dan, daniel],
	[ken, kenneth],
	[ted, theodore],
	[ron, ronald],
	[rob, robert],
	[bob, robert],
	[bill, william],
	[tim, timothy],
	[rick, richard],
	[ric, richard],
	[jim, james],
	[russ, russell],
	[mike, michael],
	[les, leslie],
	[doug, douglas],
	['wm.', william],
	[rod, rodney],
	['geo.', george],
	[chuck, charles],
	[roy, royden],
	[fred, frederick],
	[vic, victor],
	[newt, newton],
	[joe, joseph],
	[mel, melanie],
	[dave, david],
	[sid, sidney],
	[stan, stanley],
	[don, donald],
	[marty, martin],
	[gerry, gerald],
	[jerry, gerald],
	[jerry, jerald],
	[al, allen],
	[al, allan],
	[vin, vincent],
	[vince, vincent],
	[pat, patrick],
	[steve, steven],
	[greg, gregory],
	[frank, francis],
	[stan, stanley],
	[dick, richard],
	[charlie, charles],
	[sam, samuel],
	[herb, herbert],
	[max, maxwell]
	);

if ($ARGV[0] eq "QUERY") {
	shift(@ARGV);
	GovDBOpen();
	my $r = PersonDBGetID(@ARGV);
	print "$r\n";
	DBClose();
}

1;

#########################

sub PERSON_ROLE_THEN {
	my ($a, $b) = @_;
	if ($b eq '') { $b = $a; }
	return "((startdate = null or startdate <= '$b') and (enddate = null or enddate >= '$a'))";
}

sub GenderMF {
	my $a = $_[0];
	if ($a =~ /^M/i) { return "m"; }
	if ($a =~ /^F/i) { return "f"; }
	die "Unknown gender: $a";
}

sub PersonDBGetID {
	my %cri = @_;

	my ($title, $name, $when) = ($cri{title}, $cri{name}, $cri{when});
	my ($state, $district, $gender) = ($cri{state}, $cri{district}, $cri{gender});
	my ($nameformat) = ($cri{nameformat});

	my ($whenmode) = $cri{whenmode};

	if (!defined($name)) { die "Name is a required arguments."; }
	if ($when eq "now") { $when = time; }
	if ($state =~ /(\w\w)-(\d+)/) { $state = $1; $district = $2; if ($district == 98) { $district = 0; } }
	if ($title eq "sen") { undef($district); }

	my @matches1;
	my @matches2;
	my $matches2score;
	my $match;

	# Normalize extended characters (also
	# repeated below).
	$name =~ s/é/e/g;
	$name =~ s/ú/u/g;

	# Split last name, first name

	# Henry C. "Hank," Jr. 
	$name =~ s/,"/",/;
	
	my $lastname;
	my @fnames;
	my $namemod;

	$name =~ s/(\.)(\S)/$1 $2/g; # 'C.A.' => 'C. A.'

	if ($nameformat eq 'firstlast') {
		($name, $namemod) = ParseSuffix($name, $namemod);

		@fnames = split(/\s+/, $name);
		$lastname = pop(@fnames);
		push @fnames, $namemod if ($namemod ne "");

		if ($fnames[scalar(@fnames)-1] =~ /^(du|de|La|Van)$/i) {
			$lastname = pop(@fnames) . " " . $lastname;
		}

	} else { # either just last name, or 'last, first' format
		$lastname = $name;
		@fnames = ();
		if ($name =~ /^([^,]+),\s+([\w\W]+)/) {
			$lastname = $1;
			@fnames = split(/[\s,]+/, $2);
		
			# test namemod
			my $m = $fnames[scalar(@fnames)-1];
			if ($m =~ /^(Jr\.?|Sr\.?|I|II|III|IV)$/) {
				$namemod = $m;
				pop(@fnames);
			}
		}
	
		if ($lastname eq uc($lastname)) {
			$lastname = lc($lastname);
			$lastname =~ s/^(\w)/uc($1)/e;
		}

		($lastname, $namemod) = ParseSuffix($lastname, $namemod);
		push @fnames, $namemod if ($namemod ne "");

		#print "$lastname " . join("--", @fnames) . "\n";
	}
	
	# Single letter first name entries need a period
	foreach my $f (@fnames) {
		if (length($f) == 1) { $f .= "."; }
	}

	#print join("--", @fnames) . " $lastname\n";

	# Get list of matching records by last name.
	
	my ($when1, $when2) = ($when, $when);
	if ($whenmode eq "session") {
		$when1 = StartOfSession(SessionFromDate($when));
		$when2 = EndOfSession(SessionFromDate($when));
	}
	if ($whenmode eq "session#") {
		$when1 = StartOfSessionYMD($when);
		$when2 = EndOfSessionYMD($when);
		$whenmode = 'dbdate';
	}
	if ($whenmode ne "dbdate" && defined($when1)) {
		foreach my $w ($when1, $when2) {
			$w = DateToDBString($w);
		}
	}

	my @lastsplit = split(/ /, $lastname);

	# For women we better search the middle name field for maiden names,
	# but then if it matches the last name we have to undef the middle name
	# field because then it's not to be understood as a middle name.
	my $lastname2;
	$lastname =~ tr/ /-/;
	($lastname2 = $lastname) =~ tr/\-/ /;
	$matches1 = DBSelectAll(hash, people, [id, firstname, middlename, nickname, namemod, lastname],
		[DBSpecEQ(lastname,$lastname)
		. " or " . DBSpecEQ(lastname,$lastname2)
		. " or " . DBSpecEQ(middlename,$lastname2)
		. " or (" . DBSpecEQ("middlename",$lastsplit[0]) . " and " . DBSpecEQ("lastname",$lastsplit[1]) . " and " . scalar(@lastsplit) . '=2)'
		. " or " . DBSpecStartsWith(lastname,$lastname . '-')
		. " or " . DBSpecStartsWith(lastname,$lastname . ' ')
		. " or " . (scalar(@fnames) < 2 ? 0 : DBSpecEQ(lastname, $fnames[scalar(@fnames)-1] . ' ' . $lastname))
		. " or " . (scalar(@fnames) < 2 ? 0 : DBSpecEQ(lastname, $fnames[scalar(@fnames)-1] . '-' . $lastname))
		#. " or " . DBSpecEndsWith(lastname,'-' . $lastname)
		]);
	foreach my $match (@{$matches1}) {
		my @rolespec = ();
		if (defined($when1)) { push @rolespec, PERSON_ROLE_THEN($when1, $when2); }
		if (defined($title)) { push @rolespec, DBSpecEQ('type', lc($title)); }
		if (defined($state)) { push @rolespec, DBSpecEQ('state', uc($state)); }
		if (defined($district)) { push @rolespec, DBSpecEQ('district', $district); }
		my %role = DBSelectFirst(hash, people_roles, [type, state, district], [DBSpecEQ(personid, $$match{id}), @rolespec]);
		if (!defined($role{type})) { next; }

		#if (defined($gender) && $$match{gender} ne $gender) { next; }

		if ($lastname ne $$match{lastname} && $lastname eq $$match{middlename}) {
			undef $$match{middlename};
		}

		if ($cri{assumesuffix} && $namemod eq "" && $$match{namemod} ne "") { next; }

		# Normalize extended characters in the first/middle
		# name (also repeated above).
		for my $n ($$match{firstname}, $$match{nickname}, $$match{namemod}, $$match{middlename}) {
			$n =~ s/é/e/g;
			$n =~ s/ú/u/g;
		}

		# Make list of possible first name strings
		my @fntests = ();
		push @fntests, [$$match{firstname}, $$match{nickname}, $$match{namemod}] if ($$match{nickname} ne "");
		push @fntests, [$$match{firstname}, $$match{middlename}, $$match{namemod}];
		push @fntests, [$$match{firstname}, "(" . $$match{nickname} . ")", $$match{namemod}] if ($$match{nickname} ne "");
		push @fntests, [$$match{firstname}, "\"" . $$match{nickname} . "\"", $$match{namemod}] if ($$match{nickname} ne "");
		push @fntests, [$$match{firstname}, $$match{middlename}, "(" . $$match{nickname} . ")", $$match{namemod}] if ($$match{nickname} ne "");
		push @fntests, [$$match{firstname}, $$match{middlename}, "\"" . $$match{nickname} . "\"", $$match{namemod}] if ($$match{nickname} ne "");
		push @fntests, [$$match{nickname}, $$match{middlename}, $$match{namemod}] if ($$match{nickname} ne "");
		push @fntests, [$$match{firstname}, $$match{namemod}] if ($$match{namemod} ne "");
		push @fntests, [$$match{nickname}, $$match{namemod}] if ($$match{nickname} ne "");
		push @fntests, [$$match{middlename}] if ($$match{middlename} ne "");
		
		my $fnmatch = 0;
		foreach my $fntest (@fntests) {
			my $ml = fntestcmp(\@fnames, $fntest);
			if ($ml > $fnmatch) { $fnmatch = $ml; }
			#print "$$match{id} $ml " . join("--", @fnames) . " ?  " . join("--", @{$fntest}) . "\n";
		}

		if ($fnmatch == 0 && scalar(@fnames) > 0) { next; }
		if ($fnmatch < $matches2score) { next; }

		if ($matches2score < $fnmatch) { @matches2 = (); }
		push @matches2, $$match{id};
		$matches2score = $fnmatch;
	}

	if (scalar(@matches2) > 1) { warn "Multiple people match " . join(", ", @_) . ": " . join(", ", @matches2); }
	if (scalar(@matches2) == 1) { return $matches2[0]; }

	return undef;
}

sub fntestcmp {
	my @person = @{ $_[0] };
	my @test = @{ $_[1] };

	for (my $i = 0; $i < scalar(@test); $i++) {
		$test[$i] =~ s/(\.)([^\s|])/$1 $2/g; # 'C.A.' => 'C.', 'A.'
		splice(@test, $i, 1, split(/\s+/, $test[$i]));
	}

	for (my $i = 0; $i < scalar(@test); $i++) {
		if ($test[$i] eq "") { next; }
		if ($i >= scalar(@person)) { return $i; }

		my $f = 0;
		foreach my $t (split(/\|/, lc($test[$i]))) {
			if (lc($person[$i]) eq $t) { $f = 1; last; }
			if (uc($person[$i]) eq uc(substr($t, 0, 1)) . ".") { $f = 1; last; } 
			if (uc($t) eq uc(substr($person[$i], 0, 1)) . ".") { $f = 1; last; } 
			foreach my $sn (@ShortNames) {
				if ((lc($person[$i]) eq $$sn[0] || lc($person[$i]) eq $$sn[1])
				 && ($t eq $$sn[0] || $t eq $$sn[1])) { $f = 1; last; }
			}
		}
		if ($f == 1) { next; }

		return 0;	
	}

	return scalar(@test);
}

sub ParseSuffix {
	my ($a, $b) = @_;
	if ($a =~ s/,?\s+(J[rR]\.?|S[rR]\.?|I|II|III|IV)\s*$//) {
		$b = $1;
	}
	return ($a, $b);
}
