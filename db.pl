require "sql.pl";

1;

sub GovDBOpen {
	#      database,   username,   password
	# database can be govtrack@govtrack.us for remote connections,
	# when permitted
	DBOpen("govtrack", "govtrack", "");
}
