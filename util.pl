use Time::Local;
use DateTime;
use POSIX qw(strftime);
use XML::LibXML;
use LWP::UserAgent;
use Digest::MD5 qw(md5 md5_hex md5_base64);
use IO::Compress::Gzip qw(gzip $GzipError);
use IO::Uncompress::Gunzip qw(gunzip $GunzipError);
use Encode;
use HTML::Encoding 'encoding_from_http_message';
   
$XMLPARSER = XML::LibXML->new();
$XMLPARSER->expand_entities(0);

$UA = LWP::UserAgent->new(keep_alive => 2, timeout => 30, agent => "GovTrack.us", from => "operations@govtrack.us");

%ChamberNameLong = ( s => 'Senate', h => 'House of Representatives' );
%ChamberNameShort = ( s => 'Senate', h => 'House' );
%ChamberNameShortOther = ( h => 'Senate', s => 'House' );

%VoteResult = (pass => 1, passed => 1, 'agreed to' => 1, fail => -1, failed => -1, rejected => -1);

# BILL TYPE PREFIX, NAME, MAP

%BillTypePrefix = (
	h => "H.R.",
	s => "S.",
	hj => "H.J.Res.",
	sj => "S.J.Res.",
	hc => "H.Con.Res.",
	sc => "S.Con.Res.",
	hr => "H.Res.",
	sr => "S.Res."
	);

%BillTypeName = (
	h => "House Bill",
	s => "Senate Bill",
	hj => "House Joint Resolution",
	sj => "Senate Joint Resolution",
	hc => "House Concurrent Resolution",
	sc => "Senate Concurrent Resolution",
	hr => "House Simple Resolution",
	sr => "Senate Simple Resolution"
	);
	
%BillTypeMap = (
	'H. R.' => 'h',
	'H. Con. Res.' => 'hc',
	'H. J. Res.' => 'hj',
	'H. Res.' => 'hr',
	'S.' => 's',
	'S. Con. Res.' => 'sc',
	'S. J. Res.' => 'sj',
	'S. Res.' => 'sr');

foreach my $bt (keys(%BillTypeMap)) {
	my $x;
	($x = lc($bt)) =~ s/ //g;
	$BillTypeMap{$x} = $BillTypeMap{$bt};
	($x = lc($bt)) =~ s/[ \.]//g;
	$BillTypeMap{$x} = $BillTypeMap{$bt};
}

$BillTypePattern = join("|", keys(%BillTypeMap));
$BillTypePattern =~ s/ /\\s\?/g;
$BillTypePattern =~ s/\./\\\./g;

$BillPattern = "($BillTypePattern)\\s?(\\d+)";
$BillAmendmentPattern = "($BillTypePattern|H\.Amdt\.|S\.Amdt\.)\\s?(\\d+)";

# END OF BILL TYPE MAP

my $sn = 0;
%StatusNumber = (
		'introduced' => $sn++,
		'calendar' => $sn++,
		'vote' => $sn++,
		'vote2' => $sn++,
		'topresident' => $sn++,
		'signed' => $sn++,
		'veto' => $sn++,
		'override' => $sn++,
		'enacted' => $sn++);
%StatusText = (
		'introduced' => 'Introduced',
		'calendar' => 'Scheduled for Debate',
		'vote' => 'Voted on in Originating Chamber',
		'vote2' => 'Voted on in Both Chambers',
		'topresident' => 'Sent to President',
		'signed' => 'Signed by President',
		'veto' => 'Vetoed by President',
		'override' => 'Veto Overridden',
		'enacted' => 'Enacted');

%StatePrefix = (
	ALABAMA => AL, ALASKA => AK, 'AMERICAN SAMOA' => AS, ARIZONA => AZ,
	ARKANSAS => AR, CALIFORNIA => CA, COLORADO => CO, CONNECTICUT => CT,
	DELAWARE => DE, 'DISTRICT OF COLUMBIA' => DC, 'FEDERATED STATES OF MICRONESIA' => FM,
	FLORIDA => FL, GEORGIA => GA, GUAM => GU, HAWAII => HI, IDAHO => ID,
	ILLINOIS => IL, INDIANA => IN, IOWA => IA, KANSAS => KS, KENTUCKY => KY,
	LOUISIANA => LA, MAINE => ME, 'MARSHALL ISLANDS' => MH, MARYLAND => MD,
	MASSACHUSETTS => MA, MICHIGAN => MI, MINNESOTA => MN, MISSISSIPPI => MS,
	MISSOURI => MO, MONTANA => MT, NEBRASKA => 'NE', NEVADA => NV, 'NEW HAMPSHIRE' => NH,
	'NEW JERSEY' => NJ, 'NEW MEXICO' => NM, 'NEW YORK' => NY, 'NORTH CAROLINA' => NC,
	'NORTH DAKOTA' => ND, 'NORTHERN MARIANA ISLANDS' => MP, OHIO => OH, OKLAHOMA => OK,
	OREGON => OR, PALAU => PW, PENNSYLVANIA => PA, 'PUERTO RICO' => PR, 'RHODE ISLAND' => RI,
	'SOUTH CAROLINA' => SC, 'SOUTH DAKOTA' => SD, TENNESSEE => TN, TEXAS => TX, UTAH => UT,
	VERMONT => VT, 'VIRGIN ISLANDS' => VI, VIRGINIA => VA, WASHINGTON => WA,
	'WEST VIRGINIA' => WV, WISCONSIN => WI, WYOMING => WY);
%StateName = (
	AL => 'Alabama', AK => 'Alaska', AS => 'American Samoa', AZ => 'Arizona',
	AR => 'Arkansas', CA => 'California', CO => 'Colorado', CT => 'Connecticut',
	DE => 'Delaware', DC => 'District of Columbia', FM => 'Federated States of Micronesia',
	FL => 'Florida', GA => 'Georgia', GU => 'Guam', HI => 'Hawaii', ID => 'Idaho',
	IL => 'Illinois', IN => 'Indiana', IA => 'Iowa', KS => 'Kansas', KY => 'Kentucky',
	LA => 'Louisiana', ME => 'Maine', MH => 'Marshall Islands', MD => 'Maryland',
	MA => 'Massachusetts', MI => 'Michigan', MN => 'Minnesota', MS => 'Mississippi',
	MO => 'Missouri', MT => 'Montana', NE => 'Nebraska', NV => 'Nevada', NH => 'New Hampshire',
	NJ => 'New Jersey', NM => 'New Mexico', NY => 'New York', NC => 'North Carolina',
	ND => 'North Dakota', MP => 'Northern Mariana Islands', OH => 'Ohio', OK => 'Oklahoma',
	OR => 'Oregon', PW => 'Palau', PA => 'Pennsylvania', PR => 'Puerto Rico', RI => 'Rhode Island',
	SC => 'South Carolina', SD => 'South Dakota', TN => 'Tennessee', TX => 'Texas', UT => 'Utah',
	VT => 'Vermont', VI => 'Virgin Islands', VA => 'Virginia', WA => 'Washington',
	WV => 'West Virginia', WI => 'Wisconsin', WY => 'Wyoming');
@StateNames = values(%StateName);
$StateNamesString = join("|", @StateNames);
		
%Months = ( JANUARY => 1, FEBRUARY => 2, MARCH => 3, APRIL => 4, MAY => 5, JUNE => 6, JULY => 7, AUGUST => 8, SEPTEMBER => 9, OCTOBER => 10, NOVEMBER => 11, DECEMBER => 12,
	JAN => 1, FEB => 2, MAR => 3, APR => 4, MAY => 5, JUN => 6, JUL => 7, AUG => 8, SEP => 9, SEPT => 9, OCT => 10, NOV => 11, DEC => 12);
@MonthAbbr = (Jan, Feb, Mar, Apr, May, Jun, Jul, Aug, Sep, Oct, Nov, Dec);

# Congress Sessions
open SESSIONS, "<../data/us/sessions.tsv";
while (!eof(SESSIONS)) {
	$_ = <SESSIONS>; chop; split(/\t/);
	my ($cong, $sess, $st, $en) = @_;
	if (!defined($SessionStart{$cong})) { $SessionStart{$cong} = $st; }
	$SessionEnd{$cong} = $en;
	push @SessionList, [$cong, $sess, $st, $en];
}
close SESSIONS;

my @CachedProjection;

1;
		
sub SessionFromYear {
	if (!$_[1]) { die; } # flag that it is ok
	my $year = shift;
	return int(($year - 1787)/2);
}
sub StartOfSession {
	die;
	my $session = shift;
	return timelocal(0,0,0, 1, 0, $session*2+1787);
}
sub EndOfSession {
	die;
	my $session = shift;
	return timelocal(0,0,0, 31, 11, $session*2+1788);
}
sub StartOfSessionYMD {
	my $cong = shift;
	return $SessionStart{$cong};
}
sub EndOfSessionYMD {
	my $cong = shift;
	if (!$SessionEnd{$cong}) { return "9999-99-99"; }
	return $SessionEnd{$cong};
}
sub SessionFromDate {
	die;
	return SessionFromYear(YearFromDate($_[0]));
}
sub SubSessionFromYear {
	if (!$_[1]) { die; } # flag that it is ok
	my $year = shift;
	return 2 - ($year % 2);
}
sub SessionFromDateTime {
	for my $rec (@SessionList) {
		if ($_[0] ge $$rec[2] && $_[0] le $$rec[3]) { return $$rec[0]; }
		if ($_[0] ge $$rec[2] && !$$rec[3]) { return $$rec[0]; }
	}
	die $_[0];
}
sub SubSessionFromDateTime {
	for my $rec (@SessionList) {
		if ($_[0] ge $$rec[2] && $_[0] le $$rec[3]) { return $$rec[1]; }
		if ($_[0] ge $$rec[2] && !$$rec[3]) { return $$rec[1]; }
	}
	die $_[0];
}


sub YearFromDate {
	my $date = shift;
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)
		= localtime($date);
	return $year += 1900;
}

sub YMDFromDate {
	my $date = shift;
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)
		= localtime($date);
	return ($year+1900, $mon+1, $mday);
}

sub ParseTime {
	my $when = shift;

	if ($when =~ /^(\d+)\/(\d+)\/(\d+) (\d+):(\d+)(am|pm)$/) {
		my $h = $4;
		if ($h == 12 && $6 eq 'am') { $h = 0; }
		elsif ($h != 12 && $6 eq 'pm') { $h += 12; }
		$when = timelocal(0,$5,$h,$2,$1-1,$3);
	} elsif ($when =~ /^(\d+)\/(\d+)\/(\d+)$/) {
		$when = timelocal(0,0,0,$2,$1-1,$3);
	} elsif ($when =~ /^(\d\d\d\d)-(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d)( GMT)?/) {
		$when = timelocal($6, $5, $4, $3, $2-1, $1);
	} elsif ($when =~ /^([a-zA-Z]+) (\d+), (\d\d\d\d)$/) {
		$when = timelocal(0,0,0,$2,$Months{uc($1)}-1,$3);		
	} else {
		$when = "";
	}

	return $when;
}

sub GetBillDisplayNumber {
	my $bill = shift;
	my $nosession = shift;

	if (ref($bill) eq "XML::LibXML::NodeList") { $bill = $bill->get_node(1); }
	my $p = $BillTypePrefix{$bill->getAttribute("type")};
	my $n = $bill->getAttribute("number");

	if ($bill->findvalue('@session') ne $SESSION && !$nosession) {
		$n = $bill->findvalue('@session') . "/$n";
	}

	return "$p $n";
}

sub GetBillDisplayTitle {
	my $bill = shift;
	my $dotrim = shift;
	my $nosession = shift;
	my $official = shift;

	my $number = GetBillDisplayNumber($bill, $nosession);
	my $maxlen = ($dotrim ? 50 : 5000);

	my $titlenode_as;
	my $titlenode;

	if (!$official) {
	$titlenode_as = $bill->findvalue('titles/title[@type="short"][position()=last()]/@as');
	$titlenode = $bill->findvalue("titles/title[\@type='short' and \@as='$titlenode_as'][position()=1]");
	if ($titlenode ne "") { return $number . ": " . $titlenode; }

	$titlenode_as = $bill->findvalue('titles/title[@type="popular"][position()=last()]/@as');
	$titlenode = $bill->findvalue("titles/title[\@type='popular' and \@as='$titlenode_as'][position()=1]");
	if ($titlenode ne "") { return $number . ": " . $titlenode; }
	}

	$titlenode_as = $bill->findvalue('titles/title[@type="official"][position()=last()]/@as');
	$titlenode = $bill->findvalue("titles/title[\@type='official' and \@as='$titlenode_as'][position()=1]");
	if ($titlenode ne "") { return $number . ": " . Trunc($titlenode, $maxlen); }
	
	return $number;
}

sub Trunc {
	my $str = shift;
	my $len = shift;
	if (length($str) > $len) {
		$str = substr($str, 0, $len-3);
		$str =~ s/[\s,]+\w+$//;
		return $str . "...";
	}
	return $str;
}

sub htmlify {
	my $html = shift;
	my $apos = shift;
	my $nobr = shift;
	
	$html =~ s/&/&amp;/g;
	
	$html =~ s/(\s)\s+/$1/g;
	
	$html =~ s/</&lt;/g;
	$html =~ s/>/&gt;/g;
	$html =~ s/"/&quot;/g;
	$html =~ s/'/&apos;/g if ($apos);
	
	$html =~ s/\n/<br\/>/g if (!$nobr);

	$html =~ s/\`\`/\&quot;/g;
	$html =~ s/\'\'/\&quot;/g;

	$html =~ s/[\001-\011]|[\013-\020]//g;
	
	if ($html =~ s/([^A-Za-z0-9 \t:;.,'"\-_\S\/\(\)\!\#\%\&\*\+\\\[\]\^\`\~\|\{\}\n])//g) { warn "Bad character " . ord($1); }

	return $html;
}

sub ToUTF8 {
	my $str = shift;
	my $decodeHTMLEntities = shift;

	if ($decodeHTMLEntities) {
		$str =~ s/&\#(\d+);/chr($1)/ge;
	}

	$str =~ s/[\001-\010]//g;
	$str =~ s/\011/ /g;
	$str =~ s/[\013-\037]//g;
	$str =~ s/(\`\`|\'\')/"/g;
	return $str;
}

sub DateToString {
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)
		= localtime($_[0]);
	$mon = $MonthAbbr[$mon];
	$year += 1900;
	if ($_[1] eq "noyear") {
		return "$mon $mday";
	} else {
		return "$mon $mday, $year";
	}
}

sub DateToDBString {
	my $date = shift;
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)
		= localtime($date);
	$year += 1900;
	$mon++;
	return sprintf("%04d-%02d-%02d", $year, $mon, $mday);
}
sub TimestampToString {
	my $date = shift;
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)
		= localtime($date);
	$mon = $MonthAbbr[$mon];
	$year += 1900;
	return sprintf("$mon $mday, $year %02d:%02d:%02d", $hour, $min, $sec);
}
sub DateToDBTimestamp {
	my $date = shift;
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)
		= localtime($date);
	$year += 1900;
	$mon++;
	return sprintf("%04d%02d%02d%02d%02d%02d", $year, $mon, $mday, $hour, $min, $sec);
}
sub DateToDigitString {
	my $date = shift;
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)
		= localtime($date);
	$year += 1900;
	$mon++;
	return sprintf("%04d%02d%02d", $year, $mon, $mday);
}
sub DBDateToDate {
	if ($_[0] !~ /(\d\d\d\d)-(\d\d)-(\d\d)( (\d\d):(\d\d):(\d\d))?/) { die $_[0]; }
	return timelocal($7,$6,$5,$3,$2-1,$1);
}
sub DBTimestampToDate {
	if ($_[0] eq "00000000000000") { return undef; }
	$_[0] =~ /(\d\d\d\d)(\d\d)(\d\d)(\d\d)(\d\d)(\d\d)/;
	return timelocal($6,$5,$4,$3,$2-1,$1);
}
sub DBDateToString {
	return DateToString(DBDateToDate($_[0]));
}
sub DBTimestampToString {
	return TimestampToString(DBTimestampToDate($_[0]));
}
sub DateToISOString {
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)
		= localtime($_[0]);
	$mon++;
	$year += 1900;
	return FormDateTime($year, $mon, $mday, $hour, $min, $sec);
}

# Date-Time Handling in ISO Format
sub Now {
	return DateToISOString(time);
}
sub ParseDateTime {
	my $when = shift;

	my ($year, $month, $date, $hour, $minute, $second);

	if ($when =~ /^(\d+)\/(\d+)\/(\d+),?\s+(\d+):(\d+)\s*(am|pm)$/i) {
		$year = $3; $month = $1; $date = $2;
		$hour = $4; $minute = $5; $ampm = $6;
		if ($ampm =~ /p/i && $hour != 12) { $hour += 12; }
		if ($ampm =~ /a/i && $hour == 12) { $hour -= 12; }
	} elsif ($when =~ /^(\d+)\/(\d+)\/(\d+)$/) {
		$year = $3; $month = $1; $date = $2;
	} elsif ($when =~ /^(\d\d\d\d)-(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d)( GMT)?/) {
		$year = $1; $month = $2; $date = $3;
		$hour = $4; $minute = $5; $second = $6;
		if ($7 ne "") { warn "GMT timezome ignored"; }
	} elsif ($when =~ /^([a-zA-Z]+) (\d+), (\d\d\d\d)(,?\s+(\d+):(\d+)\s*(am|pm))?$/i) {
		$year = $3; $month = $Months{uc($1)}; $date = $2;
		$hour = $5; $minute = $6; $ampm = $7;
		if ($ampm =~ /p/i && $hour != 12) { $hour += 12; }
		if ($ampm =~ /a/i && $hour == 12) { $hour -= 12; }
	} elsif ($when =~ /^(\d+)-([A-Z]+)-(\d\d\d\d)( (\d+):(\d+)\s+(AM|PM))?$/i) {
		$year = $3; $month = $Months{uc($2)}; $date = $1;
		$hour = $5; $minute = $6; $ampm = $7;
		if ($ampm =~ /p/i && $hour != 12) { $hour += 12; }
		if ($ampm =~ /a/i && $hour == 12) { $hour -= 12; }
	} else {
		warn "cant parse $when";
		return undef;
	}
	return FormDateTime($year, $month, $date, $hour, $minute, $second);
}
sub FormDateTime {
	my ($year, $month, $date, $hour, $minute, $second) = @_;
	my $when = sprintf("%04d-%02d-%02d", $year, $month, $date);
	if (defined($hour)) {
		my $dt = DateTime->new(year=>$year, month=>$month, day=>$date,
			hour=>$hour, minute=>int($minute), second=>int($second),
			time_zone=>'America/New_York');
		my $tz = abs(int($dt->offset / 60 / 60)); # we know it's negative
		$when .= sprintf("T%02d:%02d:%02d-%02d:00", $hour, $minute, $second, $tz);
	}
	return $when;
}
sub YearFromDateTime {
	my $dt = shift;
	if ($dt =~ /^(\d\d\d\d)/) { return $1; }
	die "Invalid date-time: $dt";
}
sub ParseDateTimeValue {
	if ($_[0] !~ /^(\d\d\d\d)-(\d\d)-(\d\d)(T(\d\d):(\d\d):(\d\d)-0[45]:00)?$/) { die; }
	return ($1, $2, $3, $5, $6, $7);
}
sub ParseISODateTime {
	if ($_[0] !~ /^(\d\d\d\d)-(\d\d)-(\d\d)(T(\d\d):(\d\d):(\d\d)(\.\d+)(Z|-0[45]:00))?$/) { die; }
	return FormDateTime($1, $2, $3, $5, $6, $7);
}
sub DateTimeToDBString {
	my ($year, $month, $date, $hour, $minute, $second) = ParseDateTimeValue($_[0]);
	if (!defined($hour)) {
		return sprintf("%04d-%02d-%02d", $year, $month, $date);
	}
	return sprintf("%04d-%02d-%02d %02d:%02d:%02d", $year, $month, $date, $hour, $minute, $second);
}
sub DateTimeToDate {
	my ($year, $month, $date, $hour, $minute, $second) = ParseDateTimeValue($_[0]);
	$year -= 1900;
	$month--;
	return timelocal($second, $minute, $hour, $date, $month, $year);
}
	
sub NodeListUnion {
	my $list = XML::LibXML::NodeList->new();
	foreach my $n (@_) { $list->append($n); }
	return $list;
}

sub firstchar {
	return substr($_[0], 0, 1);
}

sub Uniqueify {
	my %h;
	my @a;
	foreach my $e (@_) {
		if (!defined($h{$e})) {
			push @a, $e;
			$h{$e} = 1;
		}
	}
	return @a;
}

sub TitleCase {
	if (uc("$_[0]") ne "$_[0]") { return $_[0]; }
	$_[0] =~ s/(^|\W)(\w)([\w']*)/$1 . uc($2) . lc($3)/ge;
	$_[0] =~ s/(^|\W)Dc($|\W)/$1DC$3/g;
	$_[0] =~ s/([\w,] )(A|An|The|To|From|By|Of|On|And|Or|But)( )/$1 . lc($2) . $3/ge;
	return $_[0];
}

sub Ordinate {
	my $o = $_[0];
	my $n = "$o" % 10;
	if ("$o" % 100 >= 11 && "$o" % 100 < 20) { $o .= "th"; }
	elsif ($n == 1) { $o .= "st"; }
	elsif ($n == 2) { $o .= "nd"; }
	elsif ($n == 3) { $o .= "rd"; }
	else { $o .= "th"; }
	return $o;
}

sub ScanDir {
	opendir SCANDIR, "$_[0]";
	my @d = readdir(SCANDIR);
	closedir SCANDIR;

	my @r;
	foreach $dd (@d) {
		if ($dd eq "." || $dd eq "..") { next; }
		if ($_[1] ne "") {
			if ($dd =~ /$_[1]/) { push @r, $dd; }
		} else {
			push @r, $dd;
		}
	}

	return @r;
}
                                                                                                                     
sub mean {
	my $x = 0;
	foreach my $v (@_) {
		$x += $v;
	}
	return $x / scalar(@_);
}

sub stddev {
	my $m = mean(@_);
	my $x = 0;
	foreach my $v (@_) {
		$x += ($v - $m) * ($v - $m);
	}
	return sqrt($x / scalar(@_));
}

sub zscores {
	my @ret;
	my $m = mean(@_);
	my $s = stddev(@_);
	if ($s == 0) { $s = 1; }
	foreach my $v (@_) {
		push @ret, ($v-$m) / $s;
	}
	return @ret;
}

sub correl {
	my @a = zscores(@{$_[0]});
	my @b = zscores(@{$_[1]});
	my $r = 0;
	for (my $i = 0; $i < scalar(@a); $i++) {
		$r += $a[$i] * $b[$i];
	}
	return $r / scalar(@a);
}

sub AlbersEqualAreaConicProjection {
	# http://mathworld.wolfram.com/AlbersEqual-AreaConicProjection.html
	my ($lat, $long, $origin_lat, $origin_long, $stpar1, $stpar2) = @_;
	my ($rad, $n, $C, $ro0, $ckey) = @CachedProjection;
	my $key = "$origin_lat $origin_long $stpar1 $stpar2";
	if ($ckey ne $key) {
		$rad = 3.141592654 / 180;
		$n = .5*(sin($stpar1*$rad)+sin($stpar2*$rad));
		$C = cos($stpar1*$rad)*cos($stpar1*$rad) + 2*$n*sin($stpar1*$rad);
		$ro0 = sqrt($C - 2*$n*sin($origin_lat*$rad)) / $n;
		@CachedProjection = ($rad, $n, $C, $ro0, $key);
	}

	my $theta = $n*($long-$origin_long);
	my $ro = sqrt($C - 2*$n*sin($lat*$rad)) / $n;
	return ($ro*sin($theta*$rad), $ro0 - $ro*cos($theta*$rad));
}

sub fileage { # in days
	my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,
       $atime,$mtime,$ctime,$blksize,$blocks)
           = stat($_[0]);
	return (time - $mtime) / 60 / 60 / 24;
}

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

sub WriteStatus {
	my ($item, $descr) = @_;
	
	my $date = Now();
	my $newline = "$item\t$date\t$descr\n";

	my @items;
	push @items, $newline;
	
	open STATUS, "<scraping_status.txt";
	while (!eof(STATUS)) {
		my $line = <STATUS>;
		if ($line =~ /^$item\t/) { next; }
		push @items, $line;
	}
	close STATUS;

	open STATUS, ">scraping_status.txt";
	for my $line (@items) {
		print STATUS $line;
	}
	close STATUS;
}

sub Download {
	# The goal of this routine is to download an HTML page and decode it to
	# UTF-8 (with the Perl UTF8 flag set). It will also cache the page on
	# disk so we can load it from the disk later if the CACHED environment
	# varialbe is set.

	my $URL = shift;
	my %opts = @_;
	
	my $postopts = '';
	if ($opts{post}) {
		for my $k (sort(keys(%{ $opts{post} }))) {
			if ($postopts eq '') {
				$postopts = '?';
			} else {
				$postopts .= '&';
			}
			$postopts .= $k . '=' . $opts{post}{$k};
		}
	}
	
	my $key = md5_base64($URL . $postopts);
	$key =~ s#/#-#g;
	if ($key !~ /^(.)(.)/) { die; }
	my $sd1 = $1;
	my $sd2 = $2;
	my $fn = "../mirror/$sd1/$sd2/$key";
	
	if ($ENV{CACHED} && -e $fn && !$opts{nocache}) {
		my $data;
		gunzip $fn => \$data or die "gzip failed: $GunzipError\n";
		my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,
		        $atime,$mtime,$ctime,$blksize,$blocks)
		                   = stat($fn);
		if (!$opts{binary}) { $data = decode("utf8", $data, 1); } # explicitly mark this string flagged as UTF8
		return ($data, $mtime);
	}
	
	sleep(1);
	my $response;
	if (!$opts{post}) {
		$response = $UA->get($URL);
	} else {
		$response = $UA->post($URL, $opts{post});
	}
	if (!$response->is_success) {
		warn "Could not fetch $URL: " . $response->message;
		return undef;
	}

	# Decode any Content-Encoding and character set.
	my $data = $response->decoded_content(); #(charset => 'none');
	
	$HTTP_BYTES_FETCHED += length($data);
	
	# If this is HTML, then any numeric &#...;-style entities must use
	# Unicode code points. If the encoding is ISO-8859-1, we find that
	# often the encoding is *really* Windows 1252 where &#146; is a
	# sensible code point but technically invalid character entity.
	# So before going on, we correct these mistakes in the input so
	# that we are sure to have the correct UTF-8 encoded HTML document.
	# Unfortunately, we can't decode entities here because if we were
	# to decode an < entity all hell would break loose.
	if ($response->content_type eq "text/html" && !$opts{binary}) {
		my $charset = encoding_from_http_message($response);
		
		if ($charset eq 'iso-8859-1') {
			# Replace &#...; entities by:
			#     converting it to binary data: Perl chr assumes Unicode so we use pack instead.
			#     treating it as Windws 1252 and decoding it into Perl UTF8-flagged character data
			#     using ord to convert that back to a Unicode code point
			#     and wrapping it back in &#...;.
			# This is totally over-engineered because I think there might just be
			# a small handful of characters where this actually occurs and
			# can't simply be treated as Unicode code points.
			$data =~ s/\&\#(\d+)\;/'&#' . ord(decode('windows-1252', pack("C", $1))) . ';'/eg;
		}
	}

	if (!$opts{nocache}) {
		mkdir "../mirror";
		mkdir "../mirror/$sd1";
		mkdir "../mirror/$sd1/$sd2";
		my $data2 = $data;
		if (!$opts{binary}) { $data2 = encode("utf8", $data); } # explicitly encode it as UTF8 before compression and storage to disk
		gzip \$data2 => $fn;
	}
	
	return ($data, time);
}

1;

