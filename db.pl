require "sql.pl";

1;

sub GovDBOpen {
	#      database,   username,   password
	if (!$ENV{REMOTE_DB}) {
		DBOpen("govtrack", "govtrack", "");
	} else {
		DBOpen("database=govtrack;host=govtrack.us", "govtrack_sandbox", "");
	}
}
