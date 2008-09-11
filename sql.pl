use DBI;

my $dbh;

1;

sub DBOpen { # ($dbname, $username, $password)
	my $dbname = shift;
	my $db_user_name = shift;
	my $db_password = shift;
	
	if (defined($dbh)) { die "Database already open."; }

	my $dsn = "DBI:mysql:$dbname";

	$dbh = DBI->connect($dsn, $db_user_name, $db_password) || die "Connection to database failed: $DBI::errstr";
	$dbh->{'mysql_enable_utf8'} = 1;

	my $sth = $dbh->prepare('SET NAMES "UTF8"');
	$sth->execute();
}

sub DBClose {
	if (!defined($dbh)) { die "Database not open."; }
	$dbh->disconnect();
}

sub DBSelectByID { # ($table, $id, \@fields, [other select options]) => array
	my $table = shift;
	my $id = shift;
	my $fields = shift;
	return DBSelect("first", @_, $table, $fields, [DBSpecEQ(id, $id)]);
}

sub DBSelectFirst { # ([options], $table, \@fields, \@specs) => array
	unshift @_, "first";
	return &DBSelect;
}

sub DBSelectAll { # ([options], $table, \@fields, \@specs) => arrayref of arrayrefs
	unshift @_, "all";
	return &DBSelect;
}

sub DBSelectVector { # ($table, \@fields, \@specs) => array
	unshift @_, "all";
	my $all = &DBSelect;
	my @ret;
	foreach my $x (@{$all}) {
		push @ret, @{ $x };
	}
	return @ret;
}

sub DBSelectVectorDistinct { # ($table, \@fields, \@specs) => array
	unshift @_, "all";
	unshift @_, "distinct";
	my $all = &DBSelect;
	my @ret;
	foreach my $x (@{$all}) {
		push @ret, @{ $x };
	}
	return @ret;
}

sub DBSelect { # ([distinct], [first|all], [hash], $table, \@fields, \@specs, $limits) => array or arrayref
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
	my $specs = join(" and ", @{ $speclist });

	if ($specs ne "") { $specs = "where $specs"; }
	
	my $sql = qq{select $distinct $fields from $dbname $specs $limits};
	if ($DEBUG_SQL) { warn $sql; }

	my $sth = $dbh->prepare($sql);
	$sth->execute();
	if ($first) {
		my @ret = $sth->fetchrow_array();
		if (!$hash) { return @ret; }

		my %ret2;
		for (my $i = 0; $i < scalar(@fieldarray); $i++) {
			$ret2{$fieldarray[$i]} = $ret[$i];
		}
		return %ret2;
	} else {
		my $ret = $sth->fetchall_arrayref();
		if (!$hash) { return $ret; }
		
		my @ret2;
		foreach my $r (@{ $ret }) {
			my @ra = @{ $r };
			my %rr;
			for (my $i = 0; $i < scalar(@fieldarray); $i++) {
				$rr{$fieldarray[$i]} = $ra[$i];
			}
			push @ret2, { %rr };
		}
		return [@ret2];
	}
}

sub DBExecuteSelect {
	my $sth = $dbh->prepare($_[0]);
	$sth->execute();
	return $sth->fetchall_arrayref();
}

sub DBDelete { # ($table, \@specs)
	if (!defined($dbh)) { die "Database not open."; }
	
	my $dbname = shift;
	my $speclist = shift;

	my $specs = "";
	if ($speclist ne "all") {
		$specs = join(" and ", @{ $speclist });
		if ($specs ne "") { $specs = "where $specs"; }
		else { die "No specs given to DBDelete"; }
	}

	my $sth = $dbh->prepare(qq{delete from $dbname $specs});
	$sth->execute();
}

sub DBDeleteByID { # ($table, $id)
	DBDelete($_[0], [DBSpecEQ('id', $_[1])]);
}
	
sub DBInsert { # (['LOW_PRIORITY', 'DELAYED', 'IGNORE'], $table, %values) => inserted id
	my @opts;
	while ($_[0] eq 'LOW PRIORITY' || $_[0] eq 'DELAYED' || $_[0] eq 'IGNORE') {
		push @opts, $_[0]; shift;
	}
	my $table = shift;
	return DBInsertUpdate(insert, $table, \@opts, [], @_);
}

sub DBUpdate { # (['LOW PRIORITY', 'IGNORE'], $table, \@specs, %values)
	my @opts;
	while ($_[0] eq 'LOW_PRIORITY' || $_[0] eq 'IGNORE') {
		push @opts, $_[0]; shift;
	}
	my $table = shift;
	my $specs = shift;
	DBInsertUpdate(update, $table, \@opts, $specs, @_);
}

sub DBUpdateByID { # ($table, $id, %values)
	my $table = shift;
	my $id = shift;
	return DBUpdate($table, [DBSpecEQ(id, $id)], @_);
}

sub DBInsertUpdate { # (insert/update, $table, \@opts, \@specs, %values) => inserted id
	if (!defined($dbh)) { die "Database not open."; }
	
	my $command = shift;
	my $dbname = shift;
	my $optlist = shift;
	my $speclist = shift;
	my %values = @_;
	
	my @valuelist;
	my $valuestr;
	foreach my $k (keys(%values)) {
		if ($k eq "SQL_NO_ESCAPE") { next; }
		if (defined($values{$k})) {
			my $v = $values{$k};
			if (!$values{SQL_NO_ESCAPE}) {
				$v = DBEscape($v);
			}
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
	my $n = $sth->execute() or die "Row insertion had error.";

	if ($command eq "update") { return $n; }
	if ($n == 0) { return -1; }
	return $dbh->{'mysql_insertid'};	
}

sub DBExecute {
	my $cmd = shift;
	my $sth = $dbh->prepare($cmd);
	my $n = $sth->execute() or die "Statement had error.";
	return $n;
	#return $dbh->{'mysql_insertid'};	
}

sub DBEscape {
	my $v = shift;
	$v =~ s/\\/\\\\/g;
	$v =~ s/'/\\'/g;
	return $v;
}

sub DBSpecEQ { return DBSpec($_[0], '=', $_[1]); }
sub DBSpecNE { return DBSpecNot(DBSpecEQ(@_)); }
sub DBSpecLE { return DBSpec($_[0], '<=', $_[1]); }
sub DBSpecGE { return DBSpec($_[0], '>=', $_[1]); }
sub DBSpecLT { return DBSpec($_[0], '<', $_[1]); }
sub DBSpecGT { return DBSpec($_[0], '>', $_[1]); }
sub DBSpecContains { return DBSpec($_[0], 'like', '%' . DBEscape($_[1]) . '%', 1); }
sub DBSpecStartsWith { return DBSpec($_[0], 'like', DBEscape($_[1]) . '%', 1); }
sub DBSpecEndsWith { return DBSpec($_[0], 'like', '%' . DBEscape($_[1]), 1); }

sub DBSpec {
	my $field = shift; my $cmp = shift; my $value = shift;
	my $noescape = shift;
	if (!$noescape) { $value = DBEscape($value); }
	return "$field $cmp '$value'";
}
sub DBSpecNot {
	my $spec = shift;
	return "not($spec)";
}
sub DBSpecOrNull {
	my $field = shift; my $cmp = shift; my $value = shift;
	return "(" . DBSpec($field, $cmp, $value) . " or $field = NULL)";
}
sub DBSpecIn {
	my $field = shift;
	my @values = @_;
	if (scalar(@values) == 0) { die "Cannot pass empty array to DBSpecIn."; }
	foreach my $v (@values) { $v = DBEscape($v); }
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
