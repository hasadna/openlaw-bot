#!/usr/bin/perl -w

use strict;
no strict 'refs';
use English;
use Encode;
use MediaWiki::Bot;
# use IPC::Run 'run','new_chunker';
use IPC::Open2;
use utf8;

binmode STDOUT, ":utf8";

# INCLUDE = {{הודעת עריכה חוקים}}

my %credentials = load_credentials('wiki_credentials.txt');
my $bot = MediaWiki::Bot->new({
	host       => 'he.wikisource.org',
	login_data => \%credentials,
	debug      => 1,
});

my $cat = decode_utf8('קטגוריה:בוט חוקים');
my @pages = $bot->get_pages_in_category($cat); 

foreach my $page (@pages) {
	next if ($page =~ /^משתמש:/);
	my $noticepage = "Mediawiki:Editnotice-0-$page";

	my $text = $bot->get_text($noticepage);
	if ($text) {
		print "PAGE '$noticepage' contains '$text'.\n";
		next;
	}
	print "PAGE '$noticepage' is empty.\n";
	$text = decode_utf8("{{הודעת עריכה חוקים}}");

    $bot->edit({
        page    => $noticepage,
        text    => $text,
        summary => "editnotice",
    });
	# last;
}

exit 0;

1;

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
