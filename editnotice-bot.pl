#!/usr/bin/perl -w

use strict;
no strict 'refs';
use English;
use Encode;
use utf8;
use MediaWiki::Bot;
use Data::Dumper;

binmode STDOUT, ":utf8";

my %credentials = load_credentials('wiki_botconf.txt');

my $host = ( $credentials{host} // 'he.wikisource.org' );
print "HOST $host USER $credentials{username}\n";
my $bot = MediaWiki::Bot->new({
	host       => $host,
	agent      => sprintf('PerlWikiBot/%s',MediaWiki::Bot->VERSION),
	login_data => \%credentials,
	assert     => 'bot',
	protocol   => 'https',
	debug      => 2,
}) or die "Error login...\n";

my $cat = 'קטגוריה:בוט חוקים';
my @pages = $bot->get_pages_in_category($cat); 
my ($noticepage, $text, $id);

foreach my $page (@pages) {
	next if ($page =~ /^משתמש:/);
	
	$noticepage = "Mediawiki:Editnotice-0-$page";
	$id = $bot->get_id($noticepage);
	$text = $bot->get_text($noticepage);
	print "PAGE '$page': ";
	if ($id) {
		print "DEL, ";
		$bot->delete($noticepage, 'מיותר');
	} else {
		print "NONE, ";
	}
	$noticepage = "Mediawiki:Editnotice-116-$page";
	$id = $bot->get_id($noticepage);
	$text = $bot->get_text($noticepage);
	if ($id) {
		print "DEL.\n";
		$bot->delete($noticepage, 'מיותר');
	} else {
		print "NONE.\n";
	}
}

exit 0;

1;

sub load_credentials {
	my %obj;
	my $_ = shift;
	open( my $FIN, $_ ) || die "Cannot open file \"$_\"!\n";
	while (<$FIN>) {
		if (m/^ *(.*?) *= *(.*?) *$/) {
			$obj{$1} = $2;
		}
	}
	close($FIN);
	return %obj;
}
