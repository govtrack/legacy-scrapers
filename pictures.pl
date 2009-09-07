#!/usr/bin/perl

use GD;

if ($ARGV[0] eq "THUMBS") {
	CreateThumbs($ARGV[1]);
} elsif ($ARGV[0] eq 'IMPORT') {
	my $pid = $ARGV[1];
	if ($ARGV[2] =~ /http:/) {
		system("wget -O ../data/photos/$ARGV[1].jpeg $ARGV[2]");
	} else {
		if ($pid eq "") {
			if ($ARGV[2] !~ /(^|\/)(\d+)\.jpeg$/) { die; }
			$pid = $2;
		}
		system("cp $ARGV[2] ../data/photos/$pid.jpeg");
	}
	CreateThumbs($pid);
	open CREDIT, ">../data/photos/$pid-credit.txt";
	print CREDIT "$ARGV[3] $ARGV[4]\n";
	close CREDIT;
} elsif ($ARGV[0] eq 'BIOGUIDE') {
	require "general.pl";
	require	"db.pl";
	GovDBOpen();
	@ids = DBSelect("people", ['id', 'bioguideid'], ["EXISTS(SELECT * FROM people_roles WHERE personid=id AND startdate>='2004-01-01')"]);
	DBClose();
	for my $id (@ids) {
		my ($pid, $bgid) = @$id;
		if ($bgid !~ /^([A-Z])(\d+)$/) { die $bgid; }
		my ($a, $b) = ($1, $2);
		if (-e "../data/photos/$pid.jpeg") { next; }
		sleep 1;
		print "$pid $bgid...\n";
		my $response = $UA->get(lc("http://bioguide.congress.gov/bioguide/photo/$a/$bgid.jpg"));
        if (!$response->is_success) { next; }
		print "\tGot it.\n";
        open PHOTO, ">../data/photos/$pid.jpeg";
        print PHOTO $response->content;
        close PHOTO;
        open PHOTO, ">../data/photos/$pid-credit.txt";
        print PHOTO lc("http://bioguide.congress.gov/scripts/biodisplay.pl?index=$bgid") . " Biographical Directory of the United States Congress\n";
        close PHOTO;
		CreateThumbs($pid);
	}

} else {
	1;
}

sub CreateThumbs {
	my $id = shift;
	resize("../data/photos/$id.jpeg", "../data/photos/$id-200px.jpeg", 200);
	resize("../data/photos/$id.jpeg", "../data/photos/$id-100px.jpeg", 100);
	resize("../data/photos/$id.jpeg", "../data/photos/$id-50px.jpeg", 50);
}

sub resize {
	my ($src, $dst, $width) = @_;

	my $srcimg = GD::Image->new($src) or die "Could not open image $src";

	my $height = $width * 1.2;
	
	my $dstimg = GD::Image->new($width, $height, 1);
	
	my ($srcx, $srcy) = (0,0);
	my ($srcw, $srch) = ($srcimg->width, $srcimg->height);
	
	# Since the aspect ratio of the input image surely won't
	# match with our uniform ratio of 1.2, we will crop the image
	# automatically and center in the larger axis.
	if ($height/$width*$srcimg->width < $srcimg->height) {
		$srcy = ($srcimg->height - $height/$width*$srcimg->width)/2;
		$srch -= $srcy*2;
	} else {
		$srcx = ($srcimg->width - $width/$height*$srcimg->height)/2;
		$srcw -= $srcx*2;
	}
	
	$dstimg->copyResampled($srcimg,
		0,0, # dest x/y
		$srcx,$srcy, # src x/y
		$width,$height, # dest w/h
		$srcw, $srch);
	
	open PNG, ">$dst" or die $@;
	print PNG $dstimg->jpeg();
	close PNG;
}

1;

