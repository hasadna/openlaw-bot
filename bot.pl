#!/usr/bin/perl -w

use strict;
no strict 'refs';
use English;
use Encode;
use MediaWiki::Bot;
# use IPC::Run 'run','new_chunker';
use IPC::Open2;

binmode STDOUT, ":utf8";

my %credentials = load_credentials('wiki_credentials.txt');
my $bot = MediaWiki::Bot->new({
	host       => 'he.wikisource.org',
	login_data => \%credentials,
	debug      => 1,
});

my $cat = decode_utf8('קטגוריה:בוט חוקים');
my @pages = $bot->get_pages_in_category($cat); 

foreach my $page_dst (@pages) {
	my $text;
	my $page_src = $page_dst . decode_utf8("/מקור");
	
	my @hist_s = $bot->get_history($page_src);
	my @hist_t = $bot->get_history($page_dst);
	
	my $revid_s = $hist_s[0]->{revid};
	my $revid_t = $hist_t[0]->{comment};
	my $comment = $hist_s[0]->{comment};
	$revid_t =~ s/^\[(\d+)\]/$1/ || ($revid_t = 0);
	print "REVID = $revid_s | $revid_t\n";
	
	foreach my $rec (@hist_s) {
		print "REVID = $rec->{revid} TIMESTAMP = $rec->{timestamp_date} $rec->{timestamp_time} \"$rec->{comment}\"\n";
	}
	
	if ($revid_t>=$revid_s) {
		print "Skipping.\n";
		next;
	}
	
	$text = $bot->get_text($page_src,$revid_s);
	print "SOURCE = \n$text";
	$text = ConvertText($text);
	$comment = ($comment ? "[$revid_s] $comment" : "[$revid_s]");
	# $bot->edit($page_dst,$text,"$comment");
	
	my $id1 = $bot->get_id($page_dst);
	my $id2 = $bot->get_id($page_src);
	print "PAGE = $page_dst, Comment = \"$comment\"\n";
	print "TEXT = \n$text\n";
}

exit 0;

my $title = decode_utf8('משתמש:Fuzzy');
my $pageid = $bot->get_id($title) || "";
my $text = $bot->get_text($title) || "";
print "TITLE = $title.\n";
print "ID = $pageid.\n";
print "CONTENT = \n$text\n";

1;

sub ConvertText {
	my ($tin, $tout);
	my @cmd1 = ('./syntax-wiki.pl');
	my @cmd2 = ('./format-wiki2.pl');
	$tin = shift;
	# run \@cmd1, \$tin, '|', \@cmd2, \$tout;
	
	my $pid = open2($tout, $tin, './syntax-wiki.pl');
	waitpid($pid, 0);
	
	$tout = decode_utf8($tout);
	$tout .= decode_utf8("\n[[קטגוריה:בוט חוקים]]\n");
	return $tout;
}

sub load_credentials {
	my %obj;
	$_ = shift;
	open(my $FIN,$_) || die "Cannot open file \"$_\"!\n";
 	while (<$FIN>) {
 		if (m/\s*(\w+)\s*=\s*(\w+)\s*/) {
 			$obj{$1} = $2;
 		}
 	}
 	close($FIN);
 	return %obj;
}
