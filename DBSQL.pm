package DBSQL;

use strict;
use warnings;

use DBI;

my $dbh;
my $DEBUG_SQL = 0 || $ENV{SQL_DEBUG};

1;

sub IsOpen {
	return defined($dbh);
}

sub Open { # ($dbname, $username, $password)
	# The first argument is the name of the database
	# or if it's on another computer, database@host.

	my $dbname = shift;
	my $db_user_name = shift;
	my $db_password = shift;
	
	if (defined($dbh)) { die "Database already open."; }

	my $dsn = "DBI:mysql:$dbname";

	$dbh = DBI->connect($dsn, $db_user_name, $db_password) || die "Connection to database failed: $DBI::errstr";
	$dbh->{'mysql_enable_utf8'} = 1;

	my $sth = $dbh->prepare('SET NAMES "UTF8"');
	$sth->execute();
	$sth->finish();
}

sub Close {
	if (!defined($dbh)) { die "Database not open."; }
	$dbh->disconnect();
	undef $dbh;
}

sub Execute {
	my $sth = $dbh->prepare($_[0]);
	$sth->execute();
	if ($sth->rows) {
		my @ret = @{ $sth->fetchall_arrayref() };
		$sth->finish();
		return @ret;
	} else {
		my @ret = ();
		return @ret;
	}
}

sub SelectByID { # ($table, $id, \@fields, [other select options]) => array
	my $table = shift;
	my $id = shift;
	my $fields = shift;
	return Select("first", @_, $table, $fields, [SpecEQ('id', $id)]);
}

sub SelectFirst { # ([options], $table, \@fields, \@specs) => array
	unshift @_, "first";
	return &Select;
}

sub SelectAll { # ([options], $table, \@fields, \@specs) => array of arrayrefs
	unshift @_, "all";
	return &Select;
}

sub SelectVector { # ($table, \@fields, \@specs) => array
	unshift @_, "all";
	my @all = &Select;
	my @ret;
	foreach my $x (@all) {
		push @ret, @{ $x };
	}
	return @ret;
}

sub SelectVectorDistinct { # ($table, \@fields, \@specs) => array
	unshift @_, "all";
	unshift @_, "distinct";
	my @all = &Select;
	my @ret;
	foreach my $x (@all) {
		push @ret, @{ $x };
	}
	return @ret;
}

sub Select { # ([DISTINCT], [FIRST|ALL], [HASH], $table, \@fields, \@specs, $limits) => array or arrayref
	if (!defined($dbh)) { die "Database not open."; }
	
	my $first = 0;
	my $hash = 0;
	my $distinct = "";
	
	if (lc($_[0]) eq "distinct") { $distinct = "distinct"; shift; }
	if (lc($_[0]) eq "first") { $first = 1; shift; }
	if (lc($_[0]) eq "all") { $first = 0; shift; }
	if (lc($_[0]) eq "hash") { $hash = 1; shift; }

	my $dbname = shift;
	my $fieldlist = shift;
	my $speclist = shift;
	my $limits = shift;

	my @fieldarray = @{ $fieldlist };
	my $fields = join(", ", @fieldarray);
	my $specs = (defined($speclist) ? join(" and ", @{ $speclist }) : "");
	if (!defined($limits)) { $limits = ''; }

	if ($specs ne "") { $specs = "where $specs"; } else { $specs = ''; }
	
	my $sql = "select $distinct $fields from $dbname $specs $limits";
	if ($DEBUG_SQL) { warn $sql; }

	my $sth = $dbh->prepare($sql);
	$sth->execute();
	if ($first) {
		my @ret = $sth->fetchrow_array();
		for my $v (@ret) { utf8::decode($v); } # set the UTF8 flag on the strings
		$sth->finish();
		if (!$hash) { return @ret; }

		my %ret2;
		for (my $i = 0; $i < scalar(@fieldarray); $i++) {
			$ret2{$fieldarray[$i]} = $ret[$i];
		}
		return %ret2;
	} else {
		my @ret = @{ $sth->fetchall_arrayref() };
 		$sth->finish();
 		
 		for my $r (@ret) {
	 		for my $v (@$r) { utf8::decode($v); } # set the UTF8 flag on the strings
 		}
 		
		if (!$hash) { return @ret; }
 		 		
 		my @ret2;
		foreach my $r (@ret) {
			my @ra = @{ $r };
			my %rr;
			for (my $i = 0; $i < scalar(@fieldarray); $i++) {
				$rr{$fieldarray[$i]} = $ra[$i];
			}
			push @ret2, { %rr };
		}
		return @ret2;
	}
}

sub Delete { # ($table, \@specs)
	if (!defined($dbh)) { die "Database not open."; }
	
	my $dbname = shift;
	my $speclist = shift;

	my $specs = "";
	if ($speclist ne "all") {
		$specs = join(" and ", @{ $speclist });
		if ($specs ne "") { $specs = "where $specs"; }
		else { die "No specs given to Delete"; }
	}

	my $sth = $dbh->prepare(qq{delete from $dbname $specs});
	$sth->execute();
	$sth->finish();
}

sub DeleteByID { # ($table, $id)
	Delete($_[0], [SpecEQ('id', $_[1])]);
}
	
sub Insert { # (['LOW_PRIORITY', 'DELAYED', 'IGNORE'], $table, %values) => inserted id
	my @opts;
	while ($_[0] eq 'LOW PRIORITY' || $_[0] eq 'DELAYED' || $_[0] eq 'IGNORE') {
		push @opts, $_[0]; shift;
	}
	my $table = shift;
	return InsertUpdate('insert', $table, \@opts, [], @_);
}

sub Update { # (['LOW PRIORITY', 'IGNORE'], $table, \@specs, %values)
	my @opts;
	while ($_[0] eq 'LOW_PRIORITY' || $_[0] eq 'IGNORE') {
		push @opts, $_[0]; shift;
	}
	my $table = shift;
	my $specs = shift;
	InsertUpdate('update', $table, \@opts, $specs, @_);
}

sub UpdateByID { # ($table, $id, %values)
	my $table = shift;
	my $id = shift;
	return Update($table, [SpecEQ('id', $id)], @_);
}

sub InsertUpdate { # (insert/update, $table, \@opts, \@specs, %values) => inserted id
	if (!defined($dbh)) { die "Database not open."; }
	
	my $command = shift;
	my $dbname = shift;
	my $optlist = shift;
	my $speclist = shift;
	my %values = @_;
	
	my @valuelist;
	my $valuestr;
	foreach my $k (keys(%values)) {
		if (defined($values{$k})) {
			my $v = $values{$k};
			$v = Escape($v);
			push @valuelist, "$k = '$v'";
		} else {
			push @valuelist, "$k = NULL";
		}
	}
	$valuestr = join(", ", @valuelist);

	my $opts = join(" ", @{ $optlist });
	
	my $specs = join(" and ", @{ $speclist });
	if ($specs ne "") { $specs = "where $specs"; }

	my $cmd = qq{$command $opts $dbname set $valuestr $specs};
	if ($DEBUG_SQL) { warn $cmd; }

	my $sth = $dbh->prepare($cmd);
	my $n = $sth->execute() or die "Row insertion had error: " . $DBI::errstr;
	$sth->finish();

	if ($command eq "update") { return $n; }
	if ($n == 0) { return -1; }
	return $dbh->{'mysql_insertid'};	
}

sub Escape {
	my $v = shift;
	$v =~ s/\\/\\\\/g;
	$v =~ s/'/\\'/g;
	return $v;
}

sub SpecEQ { return Spec($_[0], '=', $_[1]); }
sub SpecNE { return SpecNot(SpecEQ(@_)); }
sub SpecLE { return Spec($_[0], '<=', $_[1]); }
sub SpecGE { return Spec($_[0], '>=', $_[1]); }
sub SpecLT { return Spec($_[0], '<', $_[1]); }
sub SpecGT { return Spec($_[0], '>', $_[1]); }
sub SpecContains { return Spec($_[0], 'like', '%' . Escape($_[1]) . '%', 1); }
sub SpecStartsWith { return Spec($_[0], 'like', Escape($_[1]) . '%', 1); }
sub SpecEndsWith { return Spec($_[0], 'like', '%' . Escape($_[1]), 1); }

sub Spec {
	my $field = shift; my $cmp = shift; my $value = shift;
	my $noescape = shift;
	if (!$value) { $value = ''; }
	if (!$noescape) { $value = Escape($value); }
	return "$field $cmp '$value'";
}
sub SpecNot {
	my $spec = shift;
	return "not($spec)";
}
sub SpecOrNull {
	my $field = shift; my $cmp = shift; my $value = shift;
	return "(" . Spec($field, $cmp, $value) . " or $field IS NULL)";
}
sub SpecIn {
	my $field = shift;
	my @values = @_;
	if (scalar(@values) == 0) { die "Cannot pass empty array to SpecIn."; }
	foreach my $v (@values) { $v = Escape($v); }
	my $j = join(", ", @values);
	return "($field IN ($j))";
}

sub MakeDBDate {
	my $date = shift;
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)
		= localtime($date);
	$year += 1900;
	$mon++;
	return sprintf("%04d%02d%02d%02d%02d%02d", $year, $mon, $mday, $hour, $min, $sec);
}
sub GetDBDate {
    $_[0] =~ /(\d\d\d\d)-(\d\d)-(\d\d)( (\d\d):(\d\d):(\d\d))?/;
    return timelocal($7,$6,$5,$3,$2-1,$1);
}
sub GetDBTimestamp {
    if ($_[0] eq "00000000000000") { return undef; }
    $_[0] =~ /(\d\d\d\d)(\d\d)(\d\d)(\d\d)(\d\d)(\d\d)/;
    return timelocal($6,$5,$4,$3,$2-1,$1);
}

sub SpecFromHash {
	my @ret;
	while (scalar(@_)) {
		my $k = shift;
		my $v = shift;
		if (defined($v)) {
			push @ret, SpecEQ($k, $v);
		} else {
			push @ret, "($k IS NULL)";
		}
	}
	return @ret;
}
