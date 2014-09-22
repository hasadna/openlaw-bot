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

# my %credentials = load_credentials('wiki_credentials.txt');
my %credentials = load_credentials('wiki_botconf.txt');
my $bot = MediaWiki::Bot->new({
	host       => 'he.wikisource.org',
	login_data => \%credentials,
	debug      => 1,
});

my $cat = decode_utf8('קטגוריה:בוט חוקים');
my @pages = $bot->get_pages_in_category($cat); 
my ($noticepage, $text);

foreach my $page (@pages) {
	next if ($page =~ /^משתמש:/);
	
	$noticepage = "Mediawiki:Editnotice-0-$page";
	$text = $bot->get_text($noticepage);
	print "PAGE '$page': ";
	if ($text) {
		print "OK, ";
	} else {
		print "adding, ";
		$bot->edit({
			page    => $noticepage,
			text    => decode_utf8("{{הודעת עריכה חוקים}}"),
			summary => "editnotice",
		});
	}
	$noticepage = "Mediawiki:Editnotice-116-$page";
	$text = $bot->get_text($noticepage);
	if ($text) {
		print "OK.\n";
	} else {
		print "adding.\n";
		$bot->edit({
			page    => $noticepage,
			text    => decode_utf8("{{הודעת עריכה חוקים}}"),
			summary => "editnotice",
		});
	}
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
