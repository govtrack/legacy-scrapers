#!/usr/bin/perl

use XML::LibXML;

use utf8; # because of our empty node sentinel as a literal utf8 string

my $XMLPARSER = XML::LibXML->new();

if ($ARGV[0] eq "BILLDIFF") {
	shift @ARGV;
	print ComputeBillTextChanges(@ARGV)->toString(1);
}

1;

sub AddIdAttributesToBillText {
		# Put an id on every node. It is very important that this function
		# remains stable otherwise people's references to paragraphs in
		# the wild may change on them.
		my $xml = $_[0];
		my $prefix = $_[1];
		if (ref($_[0]) eq "") { $xml = $XMLPARSER->parse_string($xml); }
		my @stack = $xml->documentElement->childNodes;
		my $nid = 0;
		while (@stack) {
			my $n = shift(@stack);
			if (ref($n) eq 'XML::LibXML::Element' && $n->nodeName =~ /^(p|h1|h2|h3|h4|h5|pre)$/ && $n->textContent ne "") {
				$n->setAttribute("nid", $prefix . ":" . ++$nid);
			}
			unshift @stack, $n->childNodes;
		}
		if (ref($_[0]) eq "") { $xml = $xml->toString(1); }
		return $xml;
}

sub ProcessCorrespondences {
	my @last_corresp = ($_[0], $_[1], $_[2]);
	my ($oldstart_, $newstart_) = ($_[3], $_[4]);
	my ($nodeStart1, $nodeStart2) = ($_[5], $_[6]);
	my ($oldskip, $newskip) = ($_[7], $_[8]);
	#print "Last: " . join("::", @last_corresp) . "\n";
	#print "Now: $changetype " . join("::", $oldstart_, $newstart_) . "\n";
	#if ($oldstart_ - $last_corresp[0] != $newstart_ - $last_corresp[1]) { print (($oldstart_ - $last_corresp[0]) - ($newstart_ - $last_corresp[1])) . "\n"; }
	
	# Though these regions were in a correspondence, that was at
	# the grouped-word level, which really doesn't help us because
	# node boundaries are at the character level. So we have to
	# match up node boundaries as best we can. Maybe there's a
	# better way of doing this.... Actually I don't know (or
	# remember) why the character ranges aren't also in correspondence.
	
	# Make a list of pairs of node boundaries one from the left and
	# one from the right in this region.
	my @corresps;
	for (my $i = 0; $i < $oldstart_ - $last_corresp[0]; $i++) {
		my $leftnode = $$nodeStart1{$last_corresp[0]+$i};
		if (!$leftnode || $leftnode->textContent !~ /\S/) { next; }
		
		# Pick the character position in the right document that matches
		# $i, by percent through the corresponding area. Scan 150 characters
		# around that for corresponding nodes only.
		my $jp;
		if ($oldstart_ - $last_corresp[0] - 1 == 0) {
			$jp = 0;
		} else {
			$jp = int($i/($oldstart_ - $last_corresp[0] - 1) * ($newstart_ - $last_corresp[1] - 1));
		}
		for (my $j = $jp-150; $j < $jp+150; $j++) {
			if ($j < 0 || $j >= $newstart_ - $last_corresp[1]) { next; }
		
			my $rightnode = $$nodeStart2{$last_corresp[1]+$j};
			if (!$rightnode || $rightnode->textContent !~ /\S/) { next; }
			
			my $dist = abs($i/($oldstart_ - $last_corresp[0]) - $j/($newstart_ - $last_corresp[1]));
			push @corresps, [$dist, $leftnode, $rightnode];
		}
	}
	
	# Match up the node boundaries that are cloesest in their relative
	# position in the matched range.
	my %matched;
	@corresps = sort( { $$a[0] <=> $$b[0] } @corresps);
	for my $c (@corresps) {
		my $leftnode = $$c[1];
		my $rightnode = $$c[2];
		if ($matched{$leftnode} || $matched{$rightnode}) { next; }
		$matched{$leftnode} = 1;
		$matched{$rightnode} = 1;
		
		while ($leftnode->parentNode && trim($leftnode->textContent) eq trim($leftnode->parentNode->textContent) && (ref($leftnode) ne 'XML::LibXML::Element' || !$leftnode->getAttribute('nid'))) { $leftnode = $leftnode->parentNode; }
		while ($rightnode->parentNode && trim($rightnode->textContent) eq trim($rightnode->parentNode->textContent) && (ref($rightnode) ne 'XML::LibXML::Element' || !$rightnode->getAttribute('nid'))) { $rightnode = $rightnode->parentNode; }
		
		if (ref($leftnode) ne 'XML::LibXML::Element') { next; }
		if (ref($rightnode) ne 'XML::LibXML::Element') { next; }
		
		#print $leftnode->textContent . "\n";
		#print $rightnode->textContent . "\n";
		#print "\n";
		
		my $nid = $leftnode->getAttribute('nid');
		if (!$nid) { next; }
		if ($leftnode->getAttribute('tracking-nids') ne '') {
			$nid = $leftnode->getAttribute('tracking-nids') . ',' . $nid;
		}
		$rightnode->setAttribute('tracking-nids', $nid);
	}
	

	$last_corresp[0] = $oldstart_ + $oldskip;
	$last_corresp[1] = $newstart_ + $newskip;
	#print "Next: " . join("::", @last_corresp) . "\n";
	return @last_corresp;
}

sub ComputeBillTextChanges {

	($session, $type, $number, $status1, $status2) = @_;

	$prefix = "../data/us/bills.text/$session/$type/$type$number";

	$XMLPARSER->keep_blanks(0);
	my $file1 = $XMLPARSER->parse_file("$prefix$status1.gen.html");
	my $file2 = $XMLPARSER->parse_file("$prefix$status2.gen.html");
	$XMLPARSER->keep_blanks(1);

	my $file2 = RichDiff($file1, $file2);

	$file2->documentElement->setAttribute("previous-status", $status1);
	$file2->documentElement->setAttribute("status", $status2);

	return $file2;
}

sub RichDiff {
	my ($file1, $file2) = @_;

	# Remove change history from left document.
	foreach my $node ($file1->findnodes("//inserted")) {
		while ($node->lastChild) {
			my $x = $node->lastChild;
			$x->unbindNode;
			$node->parentNode->insertAfter($x, $node);
		}
		$node->unbindNode;
	}
	foreach my $node ($file1->findnodes("//removed")) {
		$node->unbindNode;
	}
	foreach my $cnode ($file1->findnodes("//changed")) {
		foreach my $node ($cnode->findnodes("changed-to")) {
			while ($node->firstChild) {
				my $x = $node->firstChild;
				$x->unbindNode;
				$cnode->parentNode->insertAfter($x, $cnode);
			}
		}
		$cnode->unbindNode;
	}
	
	# Add node ids to the right document.
	AddIdAttributesToBillText($file2, "t0:" . $status2);

	# For the purposes of diffs, we'll remove all lines in the new
	# document marked "[Struck out->] ... [<-Struck out]" because
	# we don't want the version history within the file to get in
	# the way of an actual version history.
	foreach my $node ($file2->findnodes("//*")) {
		if ($node->textContent =~ /^\s*\[Struck out->\][\w\W]*\[<-Struck out\]\s*$/) {
			# Remove this node, and pop up the node hierarchy
			# to remove any now-text-empty elements.
			while ($node->parentNode) {
				my $p = $node->parentNode;
				$p->removeChild($node);
				$node = $p;
				if ($node->textContent =~ /\S/) { last; }
			}
		}
	}

	# Also remove whitespace at the start of a node if the node was
	# preceded by whitespace.
	foreach my $node ($file1->findnodes("//text()"), $file2->findnodes("//text()")) {
		if (isWSBefore($node) && $node->textContent =~ /^\s+/) {
			$node->replaceNode($node->ownerDocument->createTextNode(trim($node->textContent)));
		}
	}
	
	# Importantly, there cannot be any empty nodes in the document, since
	# when we flatten it to text these nodes won't correspond to anything.
	# We will add <temporary-empty-node-filler>!</temporary-empty-node-filler>
	# inside, where ! is a special character we don't expect to find elsewhere.
	# It should be a single character so that it is indivisible. When processing
	# the changes, it must not be possible to separate this from the containing
	# element.
	my $empty_node_filler_tag = 'temporary-empty-node-filler';
	my $empty_node_sentinel = "‽";
	foreach my $node ($file1->findnodes("//*"), $file2->findnodes("//*")) {
		if ($node->textContent eq '') {
			my $w = $node->ownerDocument->createElement($empty_node_filler_tag);
			$w->appendText($empty_node_sentinel);
			$node->appendChild($w);
		}
	}
	
	my ($text1, $text1length, %nodeStart1) = SerializeDocument($file1, 0);
	my ($text2, $text2length, %nodeStart2) = SerializeDocument($file2, 0);
	
	my ($list1, $wordStarts1) = MakeWordList($text1);
	my ($list2, $wordStarts2) = MakeWordList($text2);

	my @files = ("/tmp/govtrack-diff-a", "/tmp/govtrack-diff-b");

	WriteDiffTextToFile($files[0], @$list1);
	WriteDiffTextToFile($files[1], @$list2);
	
	# Because we can have text deleted at the very end of the file, which
	# positions the character beyond the text, we will insert a dummy empty
	# node at the end of the document. Since it's totally empty, there's
	# no need to remove it later.
	my $final_blank = $file2->createTextNode('');
	my $lastnode = $file2;
	while ($lastnode->lastChild) { $lastnode = $lastnode->lastChild; }
	$lastnode->parentNode->insertAfter($final_blank, $lastnode);
	$nodeStart2{length($text2)} = $final_blank;

	#binmode(STDOUT, ":utf8");
	#print "0:" . length($text1) . "\n";
	#print "0:" . length($text2) . "\n";
	#print "\n";

	# Mark up the differences in the right document, pulling in text from the left document.

	my $diffsize = 0;
	my $diffdenominator = length($text2);
	my @last_corresp = (0, 0, 0);
	
	open DIFF, "diff --minimal $files[0] $files[1] |";
	while (!eof(DIFF)) {
		# Because the diff was over words, we are reading word units.
		
		my $line = <DIFF>; chop $line;
		if ($line !~ /^(\d+)(,(\d+))?([acd])(\d+)(,(\d+))?$/) {
			if ($line !~ /^[<>\-]/) { die $line; }
			next;
		}
		my $changetype = $4;
		my $oldstart = $1 - 1;
		my $oldend = (defined($3) ? $3-1 : $oldstart);
		my $newstart = $5 - 1;
		my $newend = (defined($7) ? $7-1 : $newstart);

		if ($changetype eq 'a') { $oldend = $oldstart - 1; }
		if ($changetype eq 'd') { $newstart++; $newend = $newstart - 1; }
		
		# Convert the word units into character units. Concatenate the
		# words in the ranges on the old and new sides, and get the
		# starting character indexes for the word positions on the old
		# and new sides.
		
		my $oldstring = join("", @$list1[$oldstart..$oldend]);
		my $newstring = join("", @$list2[$newstart..$newend]);
		
		$oldstart = $$wordStarts1[$oldstart];
		$newstart = $$wordStarts2[$newstart];
		
		#print "$oldstart: $oldstring\n";
		#print "$newstart: $newstring\n";
		#print "\n";

		# note total character changes
		if (length($oldstring) > length($newstring)) {
			$diffdenominator += length($oldstring) - length($newstring); # we want to divide by something sensible later
			$diffsize += length($oldstring);
		} else {
			$diffsize += length($newstring);
		}
		
		# Process any common region up to this point, and then have it skip the uncommon region in this block.
		@last_corresp = ProcessCorrespondences(@last_corresp, $oldstart, $newstart, \%nodeStart1, \%nodeStart2, length($oldstring), length($newstring));

		# since our units were groups of words, it's possible
		# to have a whole word or space in common at the start or end
		# which wasn't really changed, so let's strip those off.
		while (substr($oldstring,0,1) eq substr($newstring,0,1) && length($oldstring) > 0) {
			$oldstring = substr($oldstring,1);
			$newstring = substr($newstring,1);
			$oldstart++;
			$newstart++;
		}
		while (substr($oldstring,length($oldstring)-1,1) eq substr($newstring,length($newstring)-1,1) && length($oldstring) > 0) {
			$oldstring = substr($oldstring,0,length($oldstring)-1);
			$newstring = substr($newstring,0,length($newstring)-1);
		}
		
		# Double check we have a change. Probably not necessary...
		if (trim($oldstring) eq trim($newstring)) { next; }

		# Find the text node that contains the character position that we're
		# looking at in the old and new documents. We might be in the middle
		# of a text node, so we get how far into it we are also (the offset).
		my ($leftnode, $rightnode, $leftoffset, $rightoffset);
		for (my $i = $oldstart; $i >= 0; $i--) {
			$leftnode = $nodeStart1{$i};
			$leftoffset = $oldstart - $i;
			if (defined($leftnode)) { last; }
		}
		for (my $i = $newstart; $i >= 0; $i--) {
			$rightnode = $nodeStart2{$i};
			$rightoffset = $newstart - $i;
			if (defined($rightnode)) { last; }
		}

		# Split the nodes that we're in so that we are at a text node boundary.
		# We hold on to the portions after the split.
		($leftnode_dummy, $leftnode) = SplitNode($leftnode, $leftoffset, $oldstart, \%nodeStart1);
		($rightnode_dummy, $rightnode) = SplitNode($rightnode, $rightoffset, $newstart, \%nodeStart2);
		
		# If the left and right parts of the change are both confined to a single
		# text node, then we'll replace the node with a <changed> node. The change
		# is confined enough that we know how the parts correspond. Otherwise,
		# we wouldn't know how to match up the structure of the left and right
		# sides.
		# Don't do this if an empty node sentinel is found because then we are
		# dealing with structure, not text.
		if ($oldstring ne '' && $newstring ne ''
			&& length($oldstring) <= length($leftnode->textContent)
			&& length($newstring) <= length($rightnode->textContent)
			&& $oldstring !~ /$empty_node_sentinel/
			&& $newstring !~ /$empty_node_sentinel/) {
			
			# The left and right portions might be less than a whole text node.
			# This time we split the nodes but hold onto the portions before the split.
			($leftnode, $leftnode_dummy) = SplitNode($leftnode, length($oldstring), $oldstart+length($oldstring), \%nodeStart1);
			($rightnode, $rightnode_dummy) = SplitNode($rightnode, length($newstring), $newstart+length($newstring), \%nodeStart2);
			
			my $changenode = $rightnode->ownerDocument->createElement('changed');
			$rightnode->replaceNode($changenode);
			
			my $changefrom = $rightnode->ownerDocument->createElement('changed-from');
			$changenode->appendChild($changefrom);
			$changefrom->appendChild($leftnode->cloneNode());
			
			my $changeto = $rightnode->ownerDocument->createElement('changed-to');
			$changenode->appendChild($changeto);
			$changeto->appendChild($rightnode);

			next;
		}

		# Insert the text in the old document within a <removed> node, copying
		# in as much document structure as is contained wholly within the
		# changed/deleted text. Put the <removed> node right before the node
		# in the right document where we are.
		if ($oldstring ne '') {
			my $delnode = $rightnode->ownerDocument->createElement('removed');
			$rightnode->parentNode->insertBefore($delnode, $rightnode);

			while ($oldstring ne '') {
				# Loop invariant: We're at the start of a text node, $leftnode.
				if (length($oldstring) < length($leftnode->textContent)) {
					# Our change doesn't go to the end of this text node.
					# Take all of $oldstring, and we're done really.

					$delnode->appendChild($delnode->ownerDocument->createTextNode($oldstring));
					last;

				} else {
					# This change goes at least as far as this text node. Try to copy in the parent
					# node if it doesn't go out of the range of this change.
					while ($leftnode->parentNode
						&& $leftnode->parentNode->firstChild->isSameNode($leftnode)
						&& length($leftnode->parentNode->textContent) <= length($oldstring)) {
						$leftnode = $leftnode->parentNode;
					}
					
					# Copy in whatever was the highest node we found that will work.
					$delnode->appendChild($leftnode->cloneNode(1));

					# Advance past whatever we copied in. Move the character position.
					$oldstart += length($leftnode->textContent);
					
					# And chop off what we processed of $oldstring.
					$oldstring = substr($oldstring, length($leftnode->textContent));
					
					# And find whatever node we're positioned at now.
					for (my $i = $oldstart; $i >= 0; $i--) {
						$leftnode = $nodeStart1{$i};
						$leftoffset = $oldstart - $i;
						if (defined($leftnode)) { last; }
					}
					
					# And split that node if we're in the middle of it.
					($leftnode_dummy, $leftnode) = SplitNode($leftnode, $leftoffset, $oldstart, \%nodeStart1);
				}
			}
		}
		
		# Wrap any text in the right document in this change in an <inserted> node.
		if ($newstring ne '') {
			# This works similarly with inserting <removed> nodes, except rather than
			# inserting all of the deleted content into a single <removed> node,
			# we wrap changed nodes in the right document with as many <inserted>
			# nodes as we need. If we can group text nodes that fall under a single
			# structural element, we do that. Otherwise, we will end up wraping
			# individual text nodes.
			
			while ($newstring ne '') {
				# Loop invariant: We're at the start of a text node, $rightnode.
				if (length($newstring) < length($rightnode->textContent)) {
					# Our change doesn't go to the end of this text node.

					# Split the node.
					($rightnode, $rightnode_dummy) = SplitNode($rightnode, length($newstring), $newstart+length($newstring), \%nodeStart2);
					
					# If this is to the right of an insertion we've already processed,
					# include the node to the left.
					if ($rightnode->previousSibling && $rightnode->previousSibling->nodeName eq 'inserted') {
						my $p = $rightnode->previousSibling;
						$rightnode->unbindNode;
						$p->appendChild($rightnode);
					} else {
						my $insnode = $rightnode->ownerDocument->createElement('inserted');
						$rightnode->replaceNode($insnode);
						$insnode->appendChild($rightnode);
					}
					
					# No more to process.
					$newstring = '';

				} else {
					# This change goes at least as far as this text node. Try to wrap higher structure
					# with an inserted node, so long as the higher structure doesn't extend past the
					# inserted text.
					while ($rightnode->parentNode
						&& $rightnode->parentNode->firstChild->isSameNode($rightnode)
						&& length($rightnode->parentNode->textContent) <= length($newstring)) {
						$rightnode = $rightnode->parentNode;
					}
					
					# If this is to the right of an insertion we've already processed,
					# include the node to the left.
					if ($rightnode->previousSibling && $rightnode->previousSibling->nodeName eq 'inserted') {
						my $p = $rightnode->previousSibling;
						$rightnode->unbindNode;
						$p->appendChild($rightnode);
					} else {
						# Wrap the node.
						my $insnode = $rightnode->ownerDocument->createElement('inserted');
						$rightnode->replaceNode($insnode);
						$insnode->appendChild($rightnode);
					}

					# Advance past whatever we processed. Move the character position.
					$newstart += length($rightnode->textContent);
					
					# And chop off what we processed of $newstring.
					$newstring = substr($newstring, length($rightnode->textContent));
					
					# And find whatever node we're positioned at now.
					for (my $i = $newstart; $i >= 0; $i--) {
						$rightnode = $nodeStart2{$i};
						$rightoffset = $newstart - $i;
						if (defined($rightnode)) { last; }
					}
					
					# And split that node if we're in the middle of it.
					($rightnode_dummy, $rightnode) = SplitNode($rightnode, $rightoffset, $newstart, \%nodeStart2);
				}
			}
		}
	}

	# Process any correspondences after the last change set.
	@last_corresp = ProcessCorrespondences(@last_corresp, $text1length, $text2length, \%nodeStart1, \%nodeStart2, 0, 0);
	
	# Remove empty node filler tags.
	foreach my $n ($file2->findnodes('//' . $empty_node_filler_tag)) {
		$n->unbindNode();
	}
	
	# Merge almost-consecutive change nodes sparated only by white space
	foreach my $n ($file2->findnodes('//changed')) {
		if (!defined($n->parentNode)) { next; } # node was removed
		while (defined($n->nextSibling) && ref($n->nextSibling) eq 'XML::LibXML::Text' && $n->nextSibling->nodeValue !~ /\S/
			&& defined($n->nextSibling->nextSibling) && $n->nextSibling->nextSibling->nodeName eq 'changed') {
			foreach my $ft ('from', 'to') {
				my ($a) = $n->findnodes("changed-$ft");
				$a->appendText($n->nextSibling->nodeValue);
				my ($b) = $n->nextSibling->nextSibling->findnodes("changed-$ft");
				$a->appendText($b->textContent);
			}
			$n->parentNode->removeChild($n->nextSibling);
			$n->parentNode->removeChild($n->nextSibling);
		}
	}

	# label every inserted/removed/changed node with a change sequence number
	my $seq = 0;
	foreach my $n ($file2->findnodes('//inserted|//removed|//changed')) {
		$n->setAttribute("sequence", ++$seq);
	}
	
	$file2->documentElement->setAttribute("difference-size-chars", $diffsize);
	$file2->documentElement->setAttribute("percent-change", int(100 * $diffsize / $diffdenominator));

	$file2->documentElement->setAttribute("total-changes", $seq);

	return $file2;
}

sub SerializeDocument {
	my $node = shift;
	my $start = shift;
	
	if (ref($node) eq 'XML::LibXML::Text') {
		return ($node->nodeValue, $start+length($node->nodeValue), $start, $node);
	} else {
		my $text;
		my @nodeStarts;
		foreach my $n ($node->childNodes) {
			my ($ntext, $nstart, @nnodeStarts) = SerializeDocument($n, $start);
			if ($ntext eq '') { next; }
			$text .= $ntext;
			push @nodeStarts, @nnodeStarts;
			$start = $nstart;
		}
		return ($text, $start, @nodeStarts);
	}
}

sub MakeWordList {
	my $text = shift;

	# Split the text on various delimiters, but keep the delimiters
	# as words themselves because we want every character included
	# in the diff.
	my @words = split(/([\s\n\r\.`'"\-]+)/, $text);
	
	# We don't want to leave frequent words on lines by themselves
	# because when a bill has many changes, we don't want the diff
	# to match these words in one part to their unrelated occurrences
	# elsewhere. Compute the frequency of each word and bigram:
	my $tot = scalar(@words);
	my %freq;
	for my $w (@words) { $freq{$w}++; }
	# Get the 40th percentile frequency.
	my @wf = sort({$freq{$a} <=> $freq{$b}} keys(%freq));
	my $thresh = $freq{$wf[scalar(@wf) * .95]};

	# Join words with following frequent words. We don't want
	# very long lines because if the two documents get shifted
	# then nothing will line up at all.
	@words = reverse(@words);
	my @w2;
	while (scalar(@words)) {
		my $x = pop(@words);
		while (scalar(@words) && length($x) < 25 && ($freq{$x} > $thresh || $freq{$words[-1]} > $thresh)) {
			$x .= pop(@words);
			if ($x =~ /([\.`'"\-\)]+)$/) { last; }
		}
		push @w2, $x;
	}
	@words = @w2;
	
	my @wordStarts = (0);
	for ($i = 1; $i <= scalar(@words); $i++) {
		$wordStarts[$i] = $wordStarts[$i-1] + length($words[$i-1]);
	}
	return ([@words], [@wordStarts]);
}

sub isWSBefore {
	my $node = shift;
	if (!defined($node->previousSibling)) { return 1; }
	if ($node->previousSibling->textContent =~ /\S/) { return 0; }
	return isWSBefore($node->previousSibling);
}

sub WriteDiffTextToFile {
	my $file = shift;
	open F, ">$file";
	binmode(F, ":utf8");
	while (scalar(@_)) {
		my $a = shift(@_);
		$a =~ s/[\r\n]/===EMBEDDED=NEWLINE===/g;
		$a =~ s/^ +//;  # don't let changes in whitespace
		$a =~ s/ +$//;  # have a big effect
		$a =~ s/ +/ /;
		print F "$a\n";
	}
	close F;
}

sub max {
	if ($_[0] > $_[1]) { return $_[0]; }
	return $_[1];
}

sub trim {
	my $x = shift;
	$x =~ s/^\s+//;
	$x =~ s/\s+$//;
	return $x;
}

sub SplitNode {
	# Splits a node, returns the parts, and updates the nodeStart hash.
	my ($node, $offset, $offsetpos, $nodeStart) = @_;

	if ($offset == 0) {
		return (undef, $node);
	}

	if ($offset == length($node->textContent)) {
		return ($node, undef);
	}
	
	my $a = $node->ownerDocument->createTextNode(substr($node->textContent, 0, $offset));
	my $b = $node->ownerDocument->createTextNode(substr($node->textContent, $offset));
	$node->replaceNode($a);
	$a->parentNode->insertAfter($b, $a);
	$$nodeStart{$offsetpos - $offset} = $a;
	$$nodeStart{$offsetpos} = $b;
	return ($a, $b);
}
