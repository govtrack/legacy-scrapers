use XML::LibXML;
use GD::Graph::lines;

require 'util.pl';

$session = $ARGV[0];
if (!$session) { die "specify session"; }

$indir = "../../data/us/$session/repstats.person";
$outdir = "../../data/us/$session/repstats/images/people";

system("mkdir -p $outdir");

# Compute some percentiles for each time period.

# Load in ALL of the statistical data.
foreach my $pid (ScanDir($indir)) {
	$pid =~ s/\.xml$//;
	my $stats = $XMLPARSER->parse_file("$indir/$pid.xml");
	for my $catnode ($stats->documentElement->findnodes('*')) {
		for my $histnode ($catnode->findnodes('hist-stat')) {
			my $time = $histnode->getAttribute('time');
			for my $attrnode ($histnode->findnodes('@*')) {
				if ($attrnode->nodeName eq 'time') { next; }
				push @{$alldata{$catnode->nodeName}{$attrnode->nodeName}{$time}}, $attrnode->nodeValue;
			}
		}
	}
}

# Generate percentiles.
foreach my $cat (keys(%alldata)) {
	foreach my $attr (keys(%{ $alldata{$cat} })) {
		foreach my $time (keys(%{ $alldata{$cat}{$attr} })) {
			my @vals = sort({$a <=> $b} @{$alldata{$cat}{$attr}{$time}});
			for (my $pctile = 0; $pctile < 100; $pctile++) {
				$percentile{$cat}{$attr}{$time}[$pctile] = $vals[int($pctile/100 * scalar(@vals))];
			}
		}
	}
}

DrawGraph("novote", "NoVotePct", "votes", undef, "Missed Votes", undef, "Percent of Votes Missed", 50, 90, "percent");

DrawGraph("leaderfollower", "LeaderFollower", "leaderfollower", undef, "Leadership Score", undef, "Leadership Score", undef, undef, "percentile");

sub DrawGraph {
	my $cat = shift;
	my $attr = shift;
	my $filename = shift;
	my $shorttitle = shift;
	my $longtitle = shift;
	my $shortyaxis = shift;
	my $longyaxis = shift;
	my $percentile1 = shift;
	my $percentile2 = shift;
	my $scale = shift;
	
	foreach my $pid (ScanDir($indir)) {
		$pid =~ s/\.xml$//;
		
		$stats = $XMLPARSER->parse_file("$indir/$pid.xml");
	
		my $smallwidth = 120;
		my $resizefactor = 3;
		for my $width ($smallwidth, 550) {
	
			my @data = ([], [], [], []);
			my $npoints = 0;
			for my $node ($stats->documentElement->findnodes("$cat/hist-stat")) {
				my $x = $node->getAttribute('time');
				my $y = $node->getAttribute($attr);
				push @{$data[0]}, NiceQuarter($x);
				if ($scale eq 'percent') {
					push @{$data[1]}, $y*100;
					push @{$data[2]}, $percentile{$cat}{$attr}{$x}[$percentile1]*100;
					push @{$data[3]}, $percentile{$cat}{$attr}{$x}[$percentile2]*100;
				} elsif ($scale eq 'percentile') {
					for (my $pctile = 0; $pctile < 100; $pctile++) {
						if ($percentile{$cat}{$attr}{$x}[$pctile] > $y) {
							push @{$data[1]}, $pctile;
							last;
						}
					}
				}
				$npoints++;
			}
			
			if (!$npoints) { next; }
			
			my $graph = GD::Graph::lines->new($width * $resizefactor, $width/550*250 * $resizefactor);
			$graph->set(
				x_label => undef,
				y_label => ($width == $smallwidth ? $shortyaxis : $longyaxis),
				title => ($width == $smallwidth ? $shorttitle : $longtitle),
				x_label_skip => ($npoints / 15),
				x_label_position => .5,
				x_labels_vertical => 1,
				x_plot_values => ($width == $smallwidth ? 0 : 1),
				y_plot_values => ($width == $smallwidth ? 0 : 1),
				text_space => ($width == $smallwidth ? 0 : undef),
				#y_tick_number => 5,
				#y_label_skip=> 1,
				#y_long_ticks => 1,
				#skip_undef => 1,
				line_width => $resizefactor*2,
				) or die $graph->error;
		
			#$graph->set_legend('This Person');

			if ($scale eq 'percentile') {
				$graph->set(
					y_min_value => 0,
					y_max_value => 100);
			}

			$ttf = '/usr/share/fonts/truetype/ttf-dejavu/DejaVuSans.ttf';
			if (!-e $ttf) { die $ttf; }
			$graph->set_title_font($ttf, 10*$resizefactor);
			$graph->set_legend_font($ttf, 8*$resizefactor);
			$graph->set_x_label_font($ttf, 8*$resizefactor);
			$graph->set_x_axis_font($ttf, 8*$resizefactor);
			$graph->set_y_label_font($ttf, ($width == $smallwidth ? 6 : 8)*$resizefactor);
			$graph->set_y_axis_font($ttf, 8*$resizefactor);
		
			$graph->set( line_types => [1, 3, 3, 3] ); # 3 = dotted
			$graph->set( dclrs => [ qw(red gray gray gray) ] );
			
			$graph->set(transparent => 0);
			 
			my $gd_larger = $graph->plot(\@data) or die $graph->error;
			
			my $gd = new GD::Image($width, $width/550*250, 1);
			$gd->copyResampled($gd_larger, 0,0, 0,0, $width,$width/550*250, $width * $resizefactor, $width/550*250 * $resizefactor);
		
			my $thumb = '';
			if ($width == $smallwidth) { $thumb = '-thumb'; }
			
			open(IMG, ">$outdir/$filename-$pid$thumb.png") or die $graph->error;
			binmode IMG;
			print IMG $gd->png;
			close(IMG);
		
		}
	}
}

sub NiceQuarter {
	my $x = $_[0];
	$x =~ s/-Q1/ Jan-Mar/;
	$x =~ s/-Q2/ Apr-Jun/;
	$x =~ s/-Q3/ Jul-Sep/;
	$x =~ s/-Q4/ Oct-Dec/;
	return $x;
}

