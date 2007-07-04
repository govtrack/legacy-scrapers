use XML::LibXML;
$XMLPARSER = XML::LibXML->new();

use LWP::UserAgent;
$UA = LWP::UserAgent->new(keep_alive => 2, timeout => 30, agent => "GovTrack.us", from => "comments@govtrack.us");

use POSIX qw(strftime);
use Time::Local;

require "util.pl";


sub GetBill {
	my ($session, $billtype, $billnumber) = @_;

	if ($FILEBASE ne "") { chdir "$FILEBASE" . "gov"; }
	my $f = "../data/us/$session/bills/$billtype$billnumber.xml";
	if (!(-e $f)) { return undef; }
	return $XMLPARSER->parse_file($f)->documentElement;
}

sub GetBillList {
	my $SESSION = shift;
	my @bills;

	my $dir = "../data/us/$SESSION/bills";
	
	if ($FILEBASE ne "") { chdir "$FILEBASE" . "gov"; }
	opendir D, $dir;
	foreach my $d (readdir(D)) {
		if ($d =~ /([a-z]+)(\d+)\.xml/) {
			push @bills, [$SESSION, $1, $2, "$dir/$d"];
		}
	}
	closedir D;
	return @bills;
}	

1;

