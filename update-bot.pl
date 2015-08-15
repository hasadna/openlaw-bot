#!/usr/bin/perl -w

use strict;
no strict 'refs';
no if ($]>=5.018), warnings => 'experimental';
use English;
use Encode;
use utf8;
# use Array::Utils;
use Data::Dumper;
use MediaWiki::Bot;
use IPC::Run 'run';
use Getopt::Long;
use HTML::Parser;
use HTML::TreeBuilder::XPath;
use IO::HTML;
use Storable;

binmode STDOUT, ":utf8";
binmode STDERR, ":utf8";

my $page;
my @pages = ();
my ($verbose, $dryrun, $dump, $interactive, $recent, $noglobaltodo);
my $outfile;

$interactive = 1;
$dryrun = 1;

my @list;
my $law_name;
my %processed;
my $count = 2;

my @global_todo;

GetOptions(
	"dryrun" => \$dryrun,
	"write" => sub { $dryrun = 0; },
	"save" => \$dump,
	"verbose" => \$verbose,
	"recent=i" => \$count,
	"count=i" => \$count,
	"noglobal" => \$noglobaltodo,
	"help|?" => \&HelpMessage,
) or die("Error in command line arguments\n");

my %credentials = load_credentials('wiki_botconf.txt');
my $host = ( $credentials{host} || 'he.wikisource.org' );
print "HOST $host USER $credentials{username}\n";
my $bot = MediaWiki::Bot->new({
	host       => $host,
	agent      => sprintf('PerlWikiBot/%s',MediaWiki::Bot->VERSION),
	login_data => \%credentials,
	assert     => 'bot',
	protocol   => 'https',
	debug      => ($verbose?2:0),
}) or die "Error login...\n";


print "Note: Using stored files (-s) if exist.\n" if $dump;
print "Note: Dryrun (-d), use (-w) to write wiki.\n" if $dryrun;
print "Note: Writing changes to wiki (-w).\n" unless $dryrun;

@list = grep /\#?\d+/, @ARGV;

if (scalar(@list)) {
	$count = scalar(@list);
	print "Got $count pages from ARGV.\n";
	map s/#//, @list;
	@pages = @list;
} else {
	print "Reading update list.\n";
	if ($dump and -f "main.dump") {
		@list = @{retrieve("main.dump")};
	} else {
		$page = 'http://main.knesset.gov.il/Activity/Legislation/Laws/Pages/LawReshumot.aspx?t=LawReshumot&st=LawReshumot';
		@list = get_primary_page($page,1);
		store \@list, "main.dump" if ($dump);
	}
	@pages = map {$_->[5]} @list;
}

# Check all secondary pages (amendments) for primary laws
foreach my $id (@pages) {
	last unless $count--;
	my $any_change = 0;
	if ($id>2000000) {
		@list = ($id);
	} else {
		print "Reading secondary #$id ";
		if ($dump and -f "$id.dump") {
			my $tt = retrieve("$id.dump");
			@list = @{$tt->{list}};
			$law_name = $tt->{name};
		} else {
			$page = "http://main.knesset.gov.il/Activity/Legislation/Laws/Pages/LawSecondary.aspx?lawitemid=$id";
			@list = get_secondary_page($page);
			my %tt = ('list' => \@list, 'name' => $law_name);
			store \%tt, "$id.dump" if ($dump);
		}
		print "'$law_name'\n";
		@list = grep {$_->[3] =~ /^[pP]/} @list;
		@list = map {$_->[2]} @list;
	}
	
	foreach my $id2 (@list) {
		if (defined $processed{$id2}) {
			print "    Got primary #$id2 '$law_name', already processed.\n";
		} else {
			$any_change += (process_law($id2) // 0);
			$processed{$id2} = $law_name;
		}
	}
	# print_line(@$_) for @list;
	$count++ if $any_change;
}

update_global_todo() unless $noglobaltodo;

# $page = 'http://main.knesset.gov.il/Activity/Legislation/Laws/Pages/LawSecondary.aspx?lawitemid=565194';
# $page = 'http://main.knesset.gov.il/Activity/Legislation/Laws/Pages/LawSecondary.aspx?lawitemid=552728';

$bot->logout();

exit 0;
1;


#-----------------------------------------------------------------------------------------


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

sub get_revid {
	my $bot = shift;
	my $page = shift;
	$page = $page->{title} if (ref($page) eq 'HASH');
	
	$page =~ s/^\s*(?:מקור:)?(.*?)\s*$/$1/s;
	$page =~ s/ /_/g;
	
	my @hist_s = $bot->get_history(decode_utf8("מקור:") . $page);
	my @hist_t = $bot->get_history($page);
	
	return (0,0,undef) unless (scalar(@hist_s));
	
	my $revid_s = $hist_s[0]->{revid};
	my $revid_t = 0;
	my $comment = $hist_s[0]->{comment};
	
	foreach my $rec (@hist_t) {
		last if ($revid_t);
		$revid_t = $rec->{comment};
		$revid_t =~ s/^ *(?:\[(\d+)\]|(\d+)).*/$1/ || ( $revid_t = 0 );
	}
	
	return ($revid_s,$revid_t,$comment);
}


sub HelpMessage {
	print <<EOP;
USAGE: update-bot.pl [-h] ...

Check recent updates at the Knesset website, and update wiki.

Optional arguments:
  TITLE                 Wiki titles to fetch by the bot
  -                     Enter interacitve mode

Optional flags:
  -h, -?, --help         Show this help message and exit
  -d, --dry-run          Run the bot without commit
  -w, --write            Bot can write changes to wiki
  -c [#], --count [#]    Check [#] latest changes
  -v, --verbose          Output full process log to stdout
EOP
#  -O FILE, --OUTPUT FILE Output the final format to file FILE
	exit 0;
}

#-------------------------------------------------------------------------------

sub compare_law {
	my ($a, $b) = @_;
	my $a_date = $a->[4] =~ s/.*?(\d{1,2})(.)(\d{1,2})\2(\d{4}).*?/sprintf("%04d%02d%02d",$4,$3,$1)/re;
	my $b_date = $b->[4] =~ s/.*?(\d{1,2})(.)(\d{1,2})\2(\d{4}).*?/sprintf("%04d%02d%02d",$4,$3,$1)/re;
	my $res = 0;
	
	$res = -1 if (!$a_date || !$b_date); # Keep order if not date is given
	
	if ($a->[2] =~ /^\d+$/ && $b->[2] =~ /^\d+$/) {
		$res ||= $a->[2] <=> $b->[2];
	} else {
		$res ||= ($a_date || 0) <=> ($b_date || 0);
	}
	
	$res ||= ($a->[3] =~ /^\d+$/ <=> $b->[3] =~ /^\d+$/) || $a->[3] <=> $b->[3];
	$res ||= $a->[0] cmp $b->[0];
	return $res;
}

#-------------------------------------------------------------------------------


sub get_primary_page {
	my $page = shift;
	my $count = shift // 2;
	my $id;
	my ($tree, @trees);
	my (@table, @lol);
	
	while ($page && $count>0) {
		# print "Reading HTML file...\n";
		$tree = HTML::TreeBuilder::XPath->new_from_url($page);
		push @trees, $tree;
		
		my @loc_table = $tree->findnodes('//table[@class = "rgMasterTable"]//tr');
		
		my $loc_id = $tree->findnodes('//form[@id = "aspnetForm"]')->[0];
		if (defined $loc_id) {
			($loc_id) = ($loc_id->attr('action') =~ m/lawitemid=(\d+)/);
			$id ||= $loc_id;
		}
		
		my $nextpage = $tree->findnodes('//td[@class = "LawBottomNav"]/a[contains(@id, "_aNextPage")]')->[0] || '';
		$nextpage &&= $nextpage->attr('href');
		if ($nextpage) {
			$page = "http://main.knesset.gov.il$nextpage";
		} else {
			$page = '';
		}
		
		# Remove first row and push into @table;
		shift @loc_table;
		@table = (@table, @loc_table);
		$count--;
	}
	
	if (!scalar(@table)) {
		print "No data.\n";
		$_->delete() for (@trees);
		return [];
	}

	$law_name = $tree->findvalue('//td[contains(@class,"LawPrimaryTitleBkgWhite")]');
	$law_name =~ s/^[ \n]*(.*?)[ \n]*$/$1/;
	$law_name =~ s/, ([א-ת"]*-)?\d{4}//;
	$law_name =~ s/ \[ה?תש.?".\]//;
	$law_name =~ s/ *[\[\(](נוסח משולב|נוסח חדש|לא בתוקף)[\]\)]//g;
	# print "Law $id \"$law_name\"\n";

	foreach my $node (@table) {
		my @list = $node->findnodes('td');
		shift @list;
		my $url = pop @list;
		my $lawid = $list[0]->findnodes('a')->[0];
		$lawid &&= $lawid->attr('href'); $lawid ||= '';
		$lawid = $1 if ($lawid =~ m/lawitemid=(\d+)/);
		map { $_ = $_->as_text(); } @list;
		$url = $url->findnodes('a')->[0];
		$url &&= $url->attr('href'); $url ||= '';
		$url = decode_url($url);
		$url =~ s|/?\\|/|g;
		$url =~ s/\.PDF$/.pdf/;
		push @list, $lawid, $url, scalar(@lol);
		grep(s/^[ \t\xA0]*(.*?)[ \t\xA0]*$/$1/g, @list);
		push @lol, [@list];
	}
	$_->delete() for (@trees);
	return @lol;
}


sub get_secondary_page {
	my $page = shift;
	my $id;
	my ($tree, @trees);
	my (@table, @lol);
	
	while ($page) {
		# print "Reading HTML file...\n";
		$tree = HTML::TreeBuilder::XPath->new_from_url($page);
		push @trees, $tree;
		
		my @loc_table = $tree->findnodes('//table[@class = "rgMasterTable"]//tr');
		
		my $loc_id = $tree->findnodes('//form[@id = "aspnetForm"]')->[0];
		if (defined $loc_id) {
			($loc_id) = ($loc_id->attr('action') =~ m/lawitemid=(\d+)/);
			$id ||= $loc_id;
		}
		
		my $nextpage = $tree->findnodes('//td[@class = "LawBottomNav"]/a[contains(@id, "_aNextPage")]')->[0] || '';
		$nextpage &&= $nextpage->attr('href');
		if ($nextpage) {
			$page = "http://main.knesset.gov.il$nextpage";
		} else {
			$page = '';
		}
		
		# Remove first row and push into @table;
		shift @loc_table;
		@table = (@table, @loc_table);
	}
	
	if (!scalar(@table)) {
		# print "No data.\n";
		$_->delete() for (@trees);
		return ();
	}
	
	$law_name = $tree->findvalue('//td[contains(@class,"LawPrimaryTitleBkgWhite")]');
	$law_name =~ s/^[ \n]*(.*?)[ \n]*$/$1/;
	$law_name =~ s/, ([א-ת"]*-)?\d{4}//;
	$law_name =~ s/ *[\[\(](נוסח משולב|נוסח חדש|לא בתוקף)[\]\)]//g;
	# print "Law $id \"$law_name\"\n";
	
	foreach my $node (@table) {
		my @list = $node->findnodes('td');
		# shift @list;
		my $lawid = $list[0]->findnodes('a')->[0];
		$lawid &&= $lawid->attr('href'); $lawid ||= '';
		$lawid =~ m/Law(Primary|Secondary)[.]aspx[?]lawitemid[=](\d+)/;
		my $type = $1 // '';
		$lawid = $2 // '';
		map { $_ = $_->as_text(); } @list;
		push @list, $lawid, lc(substr($type,0,1)), scalar(@lol);
		grep(s/^[ \t\xA0]*(.*?)[ \t\xA0]*$/$1/g, @list);
		push @lol, [@list];
	}
	$_->delete() for (@trees);
	return @lol;
}


sub print_line {
	pop @_;
	print join('|',@_) . "\n";
}


my ($last_type, $last_year, $last_id);
my $first_run;

sub print_fix {
	$first_run = (!defined($first_run));
	my ($name, $type, $booklet, $page, $date, $lawid, $url) = @_;
	my $year = ''; my $type2;
	my $str = '';
	
	return if (!defined($name));
	return if ($lawid ne '' && $last_id && $lawid eq $last_id);
	$last_id = $lawid if ($lawid);
	
	$type =~ s/ה?(.)\S+ ?/$1/g; $type =~ s/(?=.$)/"/;
	$type2 = "תוס' $1" if ($booklet =~ s/תוס(?:'|פת) (\S+) *//);
	$type2 = "כרך $1 פרק $2" if ($booklet =~ s/כרך (\S+?) ?- ?(\S+) *//);
	
	$name =~ s/,? *ה?(תש.?".)[-–]\d{4}// and $year = $1;
	$year = poorman_hebrewyear($date,$page);
	
	$name =~ s/ {2,}/ /g;
	$name =~ s/ *\(חוק מקורי\)//;
	# $law_name = ($name =~ s/ *\[.*?\]//gr) if ($first_run);
	
	$name =~ s/\bמס\. $/מס' /;
	$name =~ s/ (ב|של |)$law_name$//;
	$name =~ s/^תיקון טעות.*/ת"ט/;
	$name =~ s/\((מס' \d\S*?)\)/(תיקון $1)/;
	$name =~ s/^(?:חוק לתיקון |)$law_name \((.*?)\)/ $1/;
	$name =~ s/חוק לתיקון פקודת/תיקון לפקודת/;
	$name =~ s/^(?:חוק לתיקון |תיקון ל|)(\S.*?)\s\((תי?קון .*?)\)/$2 ל$1/;
	$name =~ s/ *(.*?) */$1/;
	
	$url =~ s/.*?\/(\d+)_lsr_(\d+).pdf/$1:$2/;
	$url ||= $booklet if ($name ne 'ת"ט');
	
	if ($last_type && $type eq $last_type) { $type = ''; } else { $last_type = $type; }
	if ($last_year && $year eq $last_year) { $year = '' if (!$type); } else { $last_year = $year; }
	
	$type =~ s/ער"מ/ע"ר/;
	
	$str .= ", " if (!$year);
	$str .= "; " if ($year and !$type);
	$str .= ".\n" if ($year and $type and !$first_run);
	
	$str .= "((";
	$str .= "$type " if ($type);
	$str .= "$year, " if ($year);
	$str .= "$type2, " if ($type2);
	$str .= "$page|$name";
	$str .= "|$url" if ($url);
	$str .= "))";
	return $str;
}


sub poorman_hebrewyear {
	my $date = shift;
	my $page = shift // 500;
	my $year = ''; my $mmdd = '';
	
	# Convert date to YYYYMMDD
	$page = 500 unless ($page =~ /^\d+$/);
	$date =~ s/.*?(\d{1,2})(.)(\d{1,2})\2(\d{4}).*?/sprintf("%04d%02d%02d",$4,$3,$1)/e || return '';
	$year = $4; $mmdd = substr($date,4,4);
	return $year if ($date < "19480514");
	$year += 3760;
	# Assume new year starts between YYYY0901 and YYYY1015
	# print "MMDD = $mmdd; PAGE = $page; threshold = " . (100 + ($year-5700)*2) . "\n";
	$year++ if (($mmdd > "0900" and $mmdd <= "1015" and $page<100 + ($year-5700)*2) or ($mmdd > "1015"));
	$year =~ /(\d)(\d)(\d)(\d)$/;
	$year = (qw|- ק ר ש ת תק תר תש תת תתק|)[$2] . (qw|- י כ ל מ נ ס ע פ צ|)[$3] . (qw|- א ב ג ד ה ו ז ח ט|)[$4];
	$year =~ s/-//g;
	$year =~ s/(י)([הו])/chr(ord($1)-1).chr(ord($1)+1)/e;  # Handle טו and טז.
	$year =~ s/([כמנפצ])$/chr(ord($1)-1)/e;                # Ending-form is one letter before regular-form.
	$year =~ s/(?=.$)/"/;
	return $year;
}

# sub hebrew_numeral {
# 	my $n = shift;
# 	my $noun = shift;
# 	my $gender = shift // 'ז';
# 	my $str = '';
# 	
# 	my @numerals_m = qw|אפס אחד שני שלושה ארבעה חמשה ששה שבעה שמונה תשעה עשרה|
# 	
# 	if (substr($gender,1) eq 'ז') {
# 		if 
# 		(qw|אפס אחד שני שלושה ארבעה חמשה ששה שבעה שמונה תשעה|)[int($n % 10)]
# 	
# 	} else {
# 	
# 	
# 	}
# }

sub decode_url {
	my $_ = shift;
	s/%([0-9A-Fa-f]{2})/pack('H2',$1)/ge;
	return $_;
}


#-----------------------------------------------------------------------------------------

sub process_law {
	my $id = shift;
	my $last = 0;
	my $page = "http://main.knesset.gov.il/Activity/Legislation/Laws/Pages/LawPrimary.aspx?lawitemid=$id";
	my ($src_page, $text, $todo);
	
	my @list;
	
	if ($dump and -f "$id.dump") {
		my $tt = retrieve("$id.dump");
		@list = @{$tt->{list}};
		$law_name = $tt->{name};
	} else {
		@list = get_primary_page($page);
		my %tt = ('list' => \@list, 'name' => $law_name);
		store \%tt, "$id.dump" if ($dump);
	}
	
	print "    Got primary #$id '$law_name'.\n";
	
	$src_page = "מקור:$law_name";
	# $src_page =~ s/ /_/g;
	$text = $bot->get_text($src_page);
	if (!$text) {
		$text = $bot->get_text($law_name);
		if (!$text) {
			print "\tPage '$law_name' not found.\n";
			return 0;
		}
		if ($text =~ /#(?:הפניה|Redirect) \[\[(.*?)\]\]/) {
			print "\tRedirection '$law_name' to '$1'.\n";
			$law_name = $1;
		} else {
			print "\tPage '$law_name' found, but page '$src_page' does not exist.\n";
			return 0;
		}
		$src_page = "מקור:$law_name";
		$text = $bot->get_text($src_page);
		if (!$text) {
			print "\tPage '$src_page' not found.\n";
			return 0;
		}
	}
	
	my $text_org = $text;
	
	print "\tPage '$src_page' found, size " . length($text) . ".\n";
	
	$text =~ s/^ +//s;
	$text =~ s/^= *([^\n]*?) *= *\n/<שם> $1\n/s;
	$text =~ s/^<שם>[ \n]+(.*?) *\n/<שם> $1\n/s;
	
	print "\tChecking page: ";
	if ($text !~ /<מאגר[ א-ת]* (\d+)(?: *תי?קון *(\d+)|) *>/ || !defined $1) {
		print "\tID is $id; no last update [0].\n";
		$last = 0;
		$text =~ /<שם>.+?\n+/g;
		$text =~ s/\G/<מאגר $id תיקון 0>\n\n/;
	} elsif ($id ne $1) {
		print "\tERROR: ID mismatch ($id <> $1)!\n";
		return 0;
	} else {
		print "ID is $id == $1; last update $2\n";
		$last = $2;
	}
	my $i; 
# 	print "\tLaw length is " . scalar(@list) . "; countdown:";
# 	for ($i=0; $i<@list; $i++) {
# 		print " $list[$i]->[5]";
# 		last if ($list[$i]->[5] eq $last);
# 	}
# 	print (($i==0) ? " (none)\n" : ", that is, $i update(s)\n");
	
	($last_type, $last_year, $last_id, $first_run) = undef;
	my ($partial, $prev) = '';
	
	@list = reverse @list;
	@list = sort { compare_law($a,$b) } @list;
	
	for ($i=0, $partial = $prev = ''; $i<@list; $i++) {
		$partial .= print_fix(@{$list[$i]}) // '';
		$prev = $partial and $partial = '' if ($list[$i]->[5] eq $last);
	}
	$i = $list[-1][5];
	if ($partial) {
		$partial .= '.';
		print "\t\tPartial string: $partial\n";
	}
	
	if ($text =~ /^(.*?)\n+(<מקור>.*?)\n\n(.*?)$/s) {
		# Decompose and recompose text.
		my $pre = $1; my $post = $3; $text = $2;
		while ($post =~ s/^(\(\(.*?)\n\n//) { $text .= "\n\n$1"; }
		($text, $todo) = update_makor($text, $prev, $partial);
		$text = "$pre\n\n$text\n\n$post";
	} else {
		# No <מקור>, strange indeed, let's add it.
		print "\tNo <מקור> found in source, adding section.\n";
		$todo = makor_to_todo($partial,3);
		$todo =~ s/^\* /** /gm;
		$todo = "* ייתכן שהחוק אינו מעודכן, לעדכונים האחרונים:\n$todo";
		$text =~ /^\s*<מאגר .*?\n\n?/gm || $text =~ /^\s*<שם>.*?\n\n?/gm || $text =~ /\n\n/gs;
		$text =~ s/\G/<מקור>\n$prev$partial\n\n/;
	}
	
	$text =~ s/<מאגר.*>[ \n]*/<מאגר $id תיקון $i>\n\n/;
	
	if ($text eq $text_org) {
		print "\tNo change.\n";
		return 0;
	}
	
	print "\tLast update: <מאגר $id תיקון $i>\n";
	
	my $count = () = ($todo =~ /^\*+ /mg);
	
	# Page was modified, update WIKI
	$src_page = "מקור:$law_name";
	my $talk_page = "שיחה:$law_name";
	my $todo_page = "שיחה:$law_name/מטלות";
	
	my $summary = ($count==1 ? "בוט: עדכון לחוק" : "בוט: $count עדכונים לחוק");
	$summary = 'בוט: קישורים' if $count==0;
	print "\tUpdating page with summary \"$summary\"\n";
	$bot->edit({
		page      => $src_page,
		text      => $text,
		summary   => $summary,
		bot       => 1,
		minor     => 1,
	}) if !$dryrun;
	
	return if ($count==0);
	
	$text = $bot->get_text($todo_page);
	if ($text) {
		$text =~ s/\n+$//s;
		$text .= "\n$todo";
	} else {
		$text = "<noinclude>{{מטלות}}</noinclude>\n$todo";
	}
	
	$bot->edit({
		page      => $todo_page,
		text      => $text,
		summary   => $summary,
		bot       => 1,
		minor     => 1,
	}) if !$dryrun;
	
	$text = $bot->get_text($talk_page) // "";
	unless ($text && $text =~ /{{מטלות}}/) {
		$text = "{{מטלות}}\n\n$text";
		$bot->edit({
			page      => $talk_page,
			text      => $text,
			summary   => "תבנית מטלות",
			bot       => 1,
			minor     => 1,
		}) if !$dryrun;
	}
	
	# Push [$lawname,$count] at front
	unshift @global_todo, $law_name, $count;
	
	return 1;
}


sub update_makor {
	my ($text, $old, $new) = @_;
	my $i = 0;
	my (@uuu, $u);
	my $text2;
	my $str2 = $old.$new;
	
	my @urls;
	while ($str2 =~ /\(\(([^|]*?)\|([^|]*?)\|(\d+:\d+)\)\)([.,;]?)/g) {
		push @urls, [$1, $2, $3, $4];
	}
	
	if (!scalar(@urls)) {
		return ($text, '');
	}
	
	for ($i = @urls-1; $i>=0; $i--) {
		$u = $urls[$i][2];
		if ($text =~ /\|$u\)\)/) {
			pos($text) = $+[0]; # $text =~ m/\|$u\)\)/g;
			$str2 =~ s/^.*?\|$u\)\)//s;
			last;
		}
	}
	$i++;
	for (; $i < @urls; $i++) {
		$u = $urls[$i][2];
		$text =~ m/\G[^\n]*?(\(\(.*?\)\))(?!\))/g || last;
		my $text2 = $1;
		$text2 =~ /^\(\(([^|]*)\|([^|]*)\|?([^)|]*)\)\)$/ || last;
		if ($1 eq $urls[$i][0] || $2 eq $urls[$i][1]) {
			next if (!$u);
			$text2 = "(($1|$2|$u))";
			print "\t\tReplacing '$3' with '$u'\n";
			$str2 =~ s/^.*?\|$u\)\)//s;
			$text =~ s/\G(.*?)(\(\(.*?\)\))(?!\))/$1$text2/;
			# Rewind and find next:
			pos($text) = $-[0]; $text =~ m/\(\(.*?\)\)(?!\))/g;
		} else {
			last;
		}
	}
	
	$text =~ m/\G[ .,;]*/gc;
	# $text =~ m/\G.*/gmc;
	
	$text =~ m/(.{10})\G(.{0,10})/;
	print "\t\tPOS is " . pos($text) . "; Now at ... $1 <-G-> $2 ...\n";
	
	($text2) = ($text =~ /^(.*)\G/s);
	
	my $comment = 0;
	$comment = ($1 eq '<!--') while ($text2 =~ m/(<!--|-->)/g);
	
	if ($str2 =~ /\(\(/) {
		$str2 = "<!-- $str2 -->" unless $comment;
		$text =~ s/ *\G */ $str2 /;
	}
	
	$str2 = makor_to_todo($str2);
	
	print "\t\$text is \n$text\n" if $dryrun && $verbose;
	print "\t\$str2 is \n$str2" if $dryrun && $verbose;
	return ($text, $str2);
}

sub makor_to_todo {
	my $todo = shift;  # input str
	my $count = shift; # maximal number of items
	my @todo = ($todo =~ /(\(\(.*?\)\))/g);
	map s/\(\(([^|]*)\|([^|]*)\|(\d+):(\d+)\)\)/* {{חוק-תיקון|$2|http:\/\/fs.knesset.gov.il\/$3\/law\/$3_lsr_$4.pdf}}\n/ || s/.*//, @todo;
	splice(@todo, 0, -$count) if defined($count);
	$todo = join('', @todo);
	return $todo;
}


sub update_global_todo {
	my $page = 'ויקיטקסט:ספר החוקים הפתוח/משימות';
	my $text = $bot->get_text($page);
	my $total = 0;
	my $laws = 0;
	
	$text =~ s/[\n\s]*<\/div>[\n\s]*$//s;
	$text =~ s/$/\n/s;
	
	while (@global_todo) {
		my $name = shift @global_todo;
		my $count = shift @global_todo;
		$total += $count;
		$laws++;
		if ($text =~ /^[ *]*\[\[שיחה:$name(?:\|[^\[\]]*|)\]\](?: {{מוקטן\|(\d+)}})/g) {
			pos($text) = $-[0];
			$count += $2 // 0;
			$text =~ s/\G.*/* [[שיחה:$name|]] {{מוקטן|$count}}\n/m;
		} else {
			$text .= "* [[שיחה:$name|]] {{מוקטן|$count}}\n";
		}
	}
	$text .= "</div>\n";
	
	return if ($laws == 0 || $total == 0);
	
	my $summary = "הוספת ";
	$summary .= ($total>1 ? "$total עדכונים" : "עדכון אחד");
	$summary .= ($laws>1 ? " ב-$laws חוקים" : " בחוק אחד");
	
	if ($dryrun) {
		print "Global todo list ($summary):\n$text"
	} else {
		$bot->edit({
			page      => $page,
			text      => $text,
			summary   => $summary,
			bot       => 1,
			minor     => 1,
		});
	}
}

