#!/usr/bin/perl -w

use strict;
no strict 'refs';
use English;
use Data::Dumper;
use HTML::Parser;
use HTML::TreeBuilder::XPath;
use IO::HTML;

use utf8;

my $page = $ARGV[0];
my $id;
my $tree;
my @trees;
my @table;

binmode STDOUT, ":utf8";

if ($page =~ /^\d+$/) {
	$page = "http://main.knesset.gov.il/Activity/Legislation/Laws/Pages/LawPrimary.aspx?t=lawlaws&st=lawlaws&lawitemid=$page";
}

print STDERR "Converting page \"$page\".\n";

while ($page) {
	if (-f $page) {
		$tree = HTML::TreeBuilder::XPath->new_from_file(html_file($page));
	} else {
		$tree = HTML::TreeBuilder::XPath->new_from_url($page);
	}
	push @trees, $tree;
	
	my @loc_table = $tree->findnodes('//table[@class = "rgMasterTable"]//tr');
	
	my $loc_id = $tree->findnodes('//form[@name = "aspnetForm"]')->[0];
	($loc_id) = ($loc_id->attr('action') =~ m/lawitemid=(\d+)/);
	$id ||= $loc_id;
	
	my $nextpage = $tree->findnodes('//td[@class = "LawBottomNav"]/a[contains(@id, "_aNextPage")]')->[0] || '';
	$nextpage &&= $nextpage->attr('href');
	if ($nextpage) {
		print "Next page link '$nextpage'\n" if ($nextpage);
		$page = "http://main.knesset.gov.il$nextpage";
	} else {
		$page = '';
	}
	
	# Remove first row and push into @table;
	shift @loc_table;
	@table = (@table, @loc_table);
}

foreach my $node (reverse @table) {
    my @list = $node->findnodes('td');
    my $url = pop @list;
    shift @list;
    map { $_ = $_->as_text() . "  "; } @list;
    $url = $url->findnodes('a')->[0];
    $url &&= $url->attr('href'); $url ||= '';
    $url =~ s|/?\\|/|g;
    $url =~ s/\.PDF$/.pdf/;
    push @list, $url;
    grep(s/^[ \t\xA0]*(.*?)[ \t\xA0]*$/$1/g, @list);
    print_fix(@list);
}

for (@trees) { $_->delete(); }
exit 0;

#-------------------------------------------------------------------------------

sub print_fix {
	print STDOUT join("|",@_) . "\n";
}

