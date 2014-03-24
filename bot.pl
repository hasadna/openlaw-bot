#!/usr/bin/perl -w

use strict;
no strict 'refs';
use English;
use Encode;
use MediaWiki::Bot;
use IPC::Run 'run';
use Getopt::Long;
use utf8;

binmode STDOUT, ":utf8";

my @pages = ();
my ($verbose, $dryrun, $force,$print,$onlycheck);
my $outfile;
$dryrun = 1;
GetOptions(
	"force" => \$force, 
	"check" => \$onlycheck,
	"dryrun" => \$dryrun,
	"verbose" => \$verbose,
#	"OUTPUT=s" => sub { $print = 1; open(STDOUT, ">_[1]"); },
	"output" => \$print,
	"help|?" => \&HelpMessage,
) or die("Error in command line arguments\n");

@pages = map {decode_utf8(@ARGV)} @pages;

my %credentials = load_credentials('wiki_botconf.txt');
my $host = ( $credentials{host} || 'he.wikisource.org' );
print "HOST $host\n";
my $bot = MediaWiki::Bot->new(
	{
		host       => $host,
		login_data => \%credentials,
		debug      => 1,
	}
);
print "USER $credentials{username}\n";

my $cat = decode_utf8('קטגוריה:בוט חוקים');
@pages = $bot->get_pages_in_category($cat) unless (@pages);

my $count = 1;

foreach my $page_dst (@pages) {
	my $text;
	$page_dst =~ s/ /_/g;
	my $page_src = $page_dst . decode_utf8("/מקור");
	print "PAGE \"$page_dst\": ";
	
	my @hist_s = $bot->get_history($page_src);
	my @hist_t = $bot->get_history($page_dst);
	
	my $revid_s = $hist_s[0]->{revid};
	my $revid_t = 0;
	my $comment = $hist_s[0]->{comment};
	my $rec     = undef;
	
	foreach my $rec (@hist_t) {
		last if ($revid_t);
		$revid_t = $rec->{comment};
		$revid_t =~ s/^ *(?:\[(\d+)\]|(\d+)).*/$1/ || ( $revid_t = 0 );
	}
	
	if ($revid_t >= $revid_s) {
		if ($force) {
			print "$revid_s = $revid_t, Running anyway (-force).\n";
		} else {
			print "$revid_s = $revid_t, Skipping.\n";
			next;
		}
	} else {
		print "$revid_s > $revid_t\n";
	}

	next if ($onlycheck);
	
#	foreach my $rec (@hist_s) {
#		print "REVID = $rec->{revid} TIMESTAMP = $rec->{timestamp_date} $rec->{timestamp_time} \"$rec->{comment}\"\n";
#	}
	# print "SOURCE = \n$text";

	$text = $bot->get_text($page_src, $revid_s);
	$text = RunParsers($text);
	$comment = ( $comment ? "[$revid_s] $comment" : "[$revid_s]" );
	
	print STDOUT "$text\n" if ($print);
	$bot->edit($page_dst,$text,"$comment") unless ($dryrun);
	
#	my $id1 = $bot->get_id($page_dst);
#	my $id2 = $bot->get_id($page_src);
#	print "PAGE = $page_dst, Comment = \"$comment\"\n";
	
	# print "TEXT = \n$text\n";
	last unless --$count;
}

exit 0;
1;

sub RunParsers {
	my ( $str1, $str2, $str3 );
	my @cmd1 = ('./syntax-wiki.pl');
	my @cmd2 = ('./format-wiki.pl');
	$str1 = shift;

	run \@cmd1, \$str1, \$str2, *STDERR;
	run \@cmd2, \$str2, \$str3, *STDERR;
	$str3 = decode_utf8($str3);
	$str3 .= decode_utf8("\n[[קטגוריה:בוט חוקים]]\n");
	return $str3;
}

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

sub HelpMessage {
	print <<EOP;
USAGE: bot.pl [-h] [-d] [-f] [-l LOG] [-o] [-O OUTPUT] [-s] [-v]
              [TITLE [TITLE ...]]

Process law-source files to wiki-source.

Optional arguments:
  TITLE                 Wiki titles to fetch by the bot

Optional flags:
  -h, -?, --help         Show this help message and exit
  -c, --check            Lists wiki files with no commit
  -d, --dry-run          Run the process with no commit
  -f, --force            Force changing contents of destination
  -l LOG, --log LOG      Set a custom log file
  -o, --output           Output the final format to stdout
  -O FILE, --OUTPUT FILE Output the final format to file FILE
  -v, --verbose          Output full process log to stdout
  -s, --silent           Do not output the log info to stdout
EOP
	exit 0;
}
