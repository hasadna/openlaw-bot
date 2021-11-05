#!/usr/bin/perl -w

use strict;
no strict 'refs';
no if ($]>=5.018), warnings => 'experimental';
use English;
use Encode;
use utf8;
use POSIX 'strftime';
use Data::Dumper;
use MediaWiki::Bot;
use Getopt::Long;
use HTML::Parser;
use HTML::TreeBuilder::XPath;
use IO::HTML;
use Storable;

use constant { true => 1, false => 0 };
use constant { recent_count => 5 };

binmode STDOUT, ":utf8";
binmode STDERR, ":utf8";

sub max ($$) { $_[$_[0] < $_[1]] }
sub min ($$) { $_[$_[0] > $_[1]] }

my $website = 'https://main.knesset.gov.il';
my $recent_page = $website . '/Activity/Legislation/Laws/Pages/LawReshumot.aspx?t=LawReshumot&st=LawReshumot';
my $primary_prefix = $website . '/Activity/Legislation/Laws/Pages/LawPrimary.aspx?lawitemid=';
my $secondary_prefix = $website . '/Activity/Legislation/Laws/Pages/LawSecondary.aspx?lawitemid=';
my $bill_prefix = $website . '/Activity/Legislation/Laws/Pages/LawBill.aspx?lawitemid=';

my $page;
my @pages = ();
my ($verbose, $dryrun, $dump, $interactive, $recent, $noglobaltodo, $history, $list_arg);
my $outfile;

$interactive = true;
$dryrun = true;

my @list;
my ($law_name, $alt_names, $full_name);
my %processed;
my $count = recent_count;

my @global_todo;

print "=== [RUNNING update-bot.pl @ ", POSIX::strftime("%F %T", localtime), "] ===\n";

GetOptions(
	"count=i" => \$count,
	"dryrun" => \$dryrun,
	"full" => \$history,
	"noglobal" => \$noglobaltodo,
	"recent=s" => \$count,
	"save" => \$dump,
	"verbose" => \$verbose,
	"write" => sub { $dryrun = false; },
	"help|?" => \&HelpMessage,
) or die("Error in command line arguments\n");

print "Note: Verbose mode (-v).\n" if $verbose;
print "Note: Using stored files (-s) if exist.\n" if $dump;
print "Note: Dryrun (-d), use (-w) to write wiki.\n" if $dryrun;
print "Note: Writing changes to wiki (-w).\n" unless $dryrun;

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

@list = grep /\#?\d+/, @ARGV;

if (scalar(@list)) {
	$count = scalar(@list);
	print "Got $count pages from ARGV.\n";
	map s/#//, @list;
	@pages = @list;
	$recent = false;
	$history = true;
} else {
	print "Reading update list.\n";
	if (0 and $dump and -f "main.dump") {
		@list = @{retrieve("main.dump")};
	} else {
		$page = $recent_page;
		$page .= "&pn=$1" if $count =~ s/(\d+):(\d+)/$2/;
		@list = get_primary_page($page,1);
		store \@list, "main.dump" if ($dump);
	}
	@pages = map {$_->[5]} @list;
	
	$recent = true;
}

# Check all secondary pages (amendments) for primary laws
while (my $id = shift @pages) {
	last if $recent and $count-- <= 0;
	my $any_change = 0;
	
	print "Reading secondary #$id ";
	if ($dump and -f "s$id.dump") {
		my $tt = retrieve("s$id.dump");
		@list = @{$tt->{list}};
		$law_name = $tt->{name};
	} else {
		@list = get_bill_page($id);
		my %tt = ('list' => \@list, 'name' => $law_name);
		store \%tt, "s$id.dump" if ($dump);
	}
	if ($law_name eq '???') {
		print "failed\n";
		@list = ($id);
	} else {
		print "'$law_name'\n";
		foreach (@list) {
			if ($_->[3] =~ /^[sSbB]/) {
				my $id2 = $_->[2];
				next if (defined $processed{$id2});
				print "    Adding secondary #$id2 '$_->[0]'.\n";
				unshift(@pages, $id2);
				$count++;
			}
		}
		$processed{$id} = $law_name;
		@list = grep {$_->[3] =~ /^[pP]/} @list;
		@list = map {$_->[2]} @list;
	}
	
	foreach my $id2 (@list) {
		if (defined $processed{$id2}) {
			$law_name = $processed{$id2};
			print "    Got primary #$id2 '$law_name', already processed.\n";
		} else {
			$any_change += (process_law($id2) // 0);
			$processed{$id2} = $law_name;
		}
	}
	$count = max(recent_count,$count) if $any_change;
}

unless ($noglobaltodo) {
	update_global_todo();
}

$bot->logout();

exit 0;
1;


#-----------------------------------------------------------------------------------------

sub load_credentials {
	my %obj;
	local $_ = shift;
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
	
	my @hist_s = $bot->get_history("מקור:$page");
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

sub trim {
	local $_ = shift // '';
	s/^[ \t\xA0\n]*(.*?)[ \t\xA0\n]*$/$1/s;
	return $_;
}

sub decode_url {
	local $_ = shift;
	s/%([0-9A-Fa-f]{2})/pack('H2',$1)/ge;
	return $_;
}

sub comp_str {
	my $a = shift // '';
	my $b = shift // '';
	$a =~ tr/־–—‒―\xAD\x96\x97/-/;
	$a =~ tr/״”“„‟″‶/"/;
	$a =~ tr/`׳’‘‚‛′‵/'/;
	$b =~ tr/־–—‒―\xAD\x96\x97/-/;
	$b =~ tr/״”“„‟″‶/"/;
	$b =~ tr/`׳’‘‚‛′‵/'/;
	return ($a eq $b);
}

#-------------------------------------------------------------------------------

sub sort_laws {
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
	
	$res ||= $a->[3] <=> $b->[3] if ($a->[3] =~ /^\d+$/ and $b->[3] =~ /^\d+$/);
	$res ||= $a->[0] cmp $b->[0];
	return $res;
}

#-------------------------------------------------------------------------------

sub law_name {
	local $_ = shift;
	s/^[ \n]*(.*?)[ \n]*$/$1/;
	s/''/"/g;
	s/, (ה?תש.?".[-–])?\d{4}//;
	s/ *[\[\(](נוסח משולב|נוסח חדש|לא בתוקף)[\]\)]//g;
	s/ *\[.*?\] *$//;
	return $_;
}

# @list = (name, series, booklet, page, date, lawid, url, count)
sub get_primary_page {
	my $page = shift;
	my $id;
	my $count = shift // ($history ? 10 : 2);
	my ($tree, @trees);
	my (@table, @lol);
	
	$page = $primary_prefix.$page unless ($page =~ /^https?:/);
	$id = ($page =~ /lawitemid=(\d+)$/) ? $1 : '';
	my $local = ($dump && -f "p$id.html");
	
	my $law_list = ($page =~ /LawReshumot/);
	
	while ($page && $count>0) {
		if ($local) {
			print ">> Reading HTML file p$id.html\n" if ($verbose);
			$tree = HTML::TreeBuilder::XPath->new_from_file(html_file("p$id.html"));
		} else {
			print ">> Loading HTML page $page\n" if ($verbose);
			$tree = HTML::TreeBuilder::XPath->new_from_url($page);
		}
		push @trees, $tree;
		
		my @loc_table = $tree->findnodes('//table[contains(@class, "rgMasterTable")]//tr');
		
		my $loc_id = $tree->findnodes('//form[@id = "aspnetForm"]')->[0];
		if (defined $loc_id) {
			($loc_id) = ($loc_id->attr('action') =~ m/lawitemid=(\d+)/);
			$id ||= $loc_id;
		}
		
		my $nextpage = $tree->findnodes('//td[@class = "LawBottomNav"]/a[contains(@id, "_aNextPage")]')->[0] || '';
		$nextpage &&= $nextpage->attr('href');
		if ($nextpage && !$local) {
			$page = "http://main.knesset.gov.il$nextpage";
		} else {
			$page = '';
		}
		
		# Remove first row and push into @table;
		shift @loc_table;
		@table = (@table, @loc_table);
		$count--;
	}
	
	$full_name = trim($tree->findvalue('//td[contains(@class,"LawPrimaryTitleBkgWhite")]')) || 
		trim($tree->findvalue('//div[@class="LawPrimaryTitleDiv"]/h3')) || 
		trim($tree->findvalue('//h3[@class="LawBrownTitleH3"]')) || '???';
	$law_name = law_name($full_name);
	# print "Law $id \"$law_name\"\n";
	
	if (!scalar(@table)) {
		# print "No data.\n";
		$_->delete() for (@trees);
		return ();
	}
	
	foreach my $node (@table) {
		my @list = $node->findnodes('td');
		shift @list;
		shift @list if ($law_list);
		next unless (scalar(@list)>3);
		my $url = pop @list;
		my $lawid = $list[0]->findnodes('a')->[0];
		$lawid &&= $lawid->attr('href'); $lawid ||= '';
		$lawid = $1 if ($lawid =~ m/lawitemid=(\d+)/);
		map { $_ = trim($_->as_text()); } @list;
		
		$url = $url->findnodes('a')->[0];
		$url &&= $url->attr('href'); $url ||= '';
		$url = decode_url($url);
		$url =~ s|/?\\|/|g;
		$url =~ s/\.PDF$/.pdf/;
		
		if (!$list[3] || $list[1] eq 'דיני מדינת ישראל' || $url eq '') {
			my @list2 = get_secondary_entry($lawid);
			if ($list2[3]) {
				$url = pop @list2;
				$list2[3] = $list[3] if ($list[3]);
				@list = @list2;
			}
		}
		push @list, $lawid, $url, scalar(@lol);
		grep(s/^[ \t\xA0]*(.*?)[ \t\xA0]*$/$1/g, @list);
		# print "GOT |" . join('|', @list) . "|\n";
		push @lol, [@list];
	}
	
	$_->delete() for (@trees);
	return @lol;
}

# @list = (name, date, lawid, type, count)
sub get_secondary_page {
	my $page = shift;
	my $id;
	my ($tree, @trees);
	my (@table, @lol);
	
	$page = $secondary_prefix.$page unless ($page =~ /^https?:/);
	$id = ($page =~ /lawitemid=(\d+)$/) ? $1 : '';
	my $local = ($dump && -f "s$id.html");
	
	while ($page) {
		if ($local) {
			print ">> Reading HTML file s$id.html\n" if ($verbose);
			$tree = HTML::TreeBuilder::XPath->new_from_file(html_file("s$id.html"));
		} else {
			print ">> Loading HTML page $page\n" if ($verbose);
			$tree = HTML::TreeBuilder::XPath->new_from_url($page);
		}
		push @trees, $tree;
		
		my @loc_table = $tree->findnodes('//table[contains(@class, "rgMasterTable")]//tr');
		# print STDERR $loc_table[0]->dump();
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
		
		@table = (@table, @loc_table);
	}
	
	$law_name = trim($tree->findvalue('//div[@class="LawBillTitleDiv"]//h2[@class="LawDarkBrownTitleH2"]')) || 
		trim($tree->findvalue('//td[contains(@class,"LawPrimaryTitleBkgWhite")]')) || '???';
	$law_name = law_name($law_name);
	# print "Law $id \"$law_name\"\n";
	
	if (!scalar(@table)) {
		# print "No data.\n";
		$_->delete() for (@trees);
		return ();
	}
	
	foreach my $node (@table) {
		my @list = $node->findnodes('td');
		next unless scalar(@list);
		my $lawid = $list[0]->findnodes('a')->[0];
		$lawid &&= $lawid->attr('href'); $lawid ||= '';
		$lawid =~ m/Law(Primary|Secondary|Bill)\.aspx\?.*lawitemid[=](\d+)/;
		my $type = $1 // ''; $lawid = $2 // '';
		map { $_ = $_->as_text(); } @list;
		push @list, $lawid, lc(substr($type,0,1)), scalar(@lol);
		grep(s/^[ \t\xA0]*(.*?)[ \t\xA0]*$/$1/g, @list);
		push @lol, [@list];
	}
	$_->delete() for (@trees);
	return @lol;
}

sub get_bill_page {
	my $page = shift;
	my $id;
	my ($tree, @trees);
	my (@table, @lol);
	
	$page = $bill_prefix.$page unless ($page =~ /^https?:/);
	$id = ($page =~ /lawitemid=(\d+)$/) ? $1 : '';
	my $local = ($dump && -f "b$id.html");
	
	if ($local) {
		print ">> Reading HTML file b$id.html\n" if ($verbose);
		$tree = HTML::TreeBuilder::XPath->new_from_file(html_file("b$id.html"));
	} else {
		print ">> Loading HTML page $page\n" if ($verbose);
		$tree = HTML::TreeBuilder::XPath->new_from_url($page);
	}
	
	@table = $tree->findnodes('//table[contains(@class, "LawBillGridCls")]//tr');
	
	my $loc_id = $tree->findnodes('//form[@id = "aspnetForm"]')->[0];
	if (defined $loc_id) {
		($loc_id) = ($loc_id->attr('action') =~ m/lawitemid=(\d+)/);
		$id ||= $loc_id;
	}
	
	$law_name = trim($tree->findvalue('//div[@class="LawBillTitleDiv"]//h2[@class="LawDarkBrownTitleH2"]')) || 
		trim($tree->findvalue('//td[contains(@class,"LawPrimaryTitleBkgWhite")]')) || '???';
	$law_name = law_name($law_name);
	# print "Law $id \"$law_name\"\n";
	
	if (!scalar(@table)) {
		# print "No data.\n";
		$tree->delete();
		return get_secondary_page($id);
	}
	
	foreach my $node (@table) {
		my @list = $node->findnodes('td');
		next unless scalar(@list);
		my $lawid = $list[0]->findnodes('a')->[0];
		$lawid &&= $lawid->attr('href'); $lawid ||= '';
		$lawid =~ m/Law(Primary|Secondary|Bill)\.aspx\?.*lawitemid[=](\d+)/;
		my $type = $1 // ''; $lawid = $2 // '';
		map { $_ = $_->as_text(); } @list;
		@list = ( $list[0], $list[2], $lawid, lc(substr($type,0,1)), scalar(@lol));
		grep(s/^[ \t\xA0]*(.*?)[ \t\xA0]*$/$1/g, @list);
		push @lol, [@list];
	}
	
	$tree->delete();
	return @lol;
}

sub get_secondary_entry {
	my $page = shift;
	my $id;
	my $tree;
	my (@table, @lol);
	my @entry;
	
	$page = $secondary_prefix.$page unless ($page =~ /^https?:/);
	$tree = HTML::TreeBuilder::XPath->new_from_url($page);
	
	# my $law_name = law_name($tree->findvalue('//div[@class="LawBillTitleDiv"]//h2[@class="LawDarkBrownTitleH2"]'));
	my $law_name = law_name($tree->findvalue('//td[contains(@class,"LawPrimaryTitleBkgWhite")]'));
	# print "Law $id \"$law_name\"\n";
	
	@table = $tree->findnodes('//table[@id = "tblMainProp"]//td');
	
	my $url = $table[7]->findnodes('a')->[0];
	$url &&= $url->attr('href'); $url ||= '';
	$url = decode_url($url);
	$url =~ s|/?\\|/|g;
	$url =~ s/\.PDF$/.pdf/;
	
	$entry[0] = trim($law_name);
	$entry[1] = trim($table[4]->findvalue('div[1]/div[2]'));
	$entry[2] = trim($table[5]->findvalue('div[1]/div[2]'));
	$entry[3] = trim($table[6]->findvalue('div[1]/div[2]'));
	$entry[4] = trim($table[3]->findvalue('div[1]/div[2]'));
	$entry[5] = $url;
	# print join('|',@entry), "\n";
	
	grep(s/^[ \t\xA0]*(.*?)[ \t\xA0]*$/$1/, @entry);
	$tree->delete();
	return @entry;
}

#-------------------------------------------------------------------------------

sub print_line {
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
#	return if ($lawid ne '' && $last_id && $lawid eq $last_id);
	$last_id = $lawid if ($lawid);
	
	$type =~ s/ה?(.)\S+ ?/$1/g; $type =~ s/(?=.$)/"/;
	$type2 = "תוס' $1" if ($booklet =~ s/תוס(?:'|פת) (\S+) *//);
	$type2 = "כרך $1 פרק $2" if ($booklet =~ s/כרך (\S+?) ?- ?(\S+) *//);
	
	$name =~ s/''/"/g;
	$name =~ s/,? *ה?(תש.?".)[-–]\d{4}// and $year = $1;
	$year = poorman_hebrewyear($date,$page);
	
	$law_name = '' if ($law_name eq '???');
	
	my $law_re = $law_name;
	$law_re .= "|$alt_names" if ($alt_names);
	$law_re =~ s/\\?([()\\])/\\$1/g;
	$law_re = "(?:$law_re)";
	
	$name =~ s/^הצעת חוק/חוק/;
	$name =~ s/ {2,}/ /g;
	$name =~ s/ *\(חוק מקורי\)//;
	$name =~ s/החוק המקורי/$law_name/;
	# $law_name = ($name =~ s/ *\[.*?\]//gr) if ($first_run);
	$name =~ s/\bמס\. $/מס' /;
	$name =~ s/ (ב|של |ל)$law_re$//;
	$name =~ s/^תיקו(ן|ני) טעו(יו|)ת.*/ת"ט/;
	$name =~ s/\((מס' \d\S*?)\)/(תיקון $1)/;
	$name =~ s/^(?:חוק לתיקון )?$law_re \((.*?)\)/ $1/;
	$name =~ s/חוק לתיקון פקודת/תיקון לפקודת/;
	$name =~ s/^(?:חוק לתיקון |תיקון ל|)(\S.*?) \((תי?קון .*?)\)(.*)/$2 $3 ל$1/;
	$name =~ s/^(\S+) +$law_re/$1/;
	$name =~ s/ *(.*?) */$1/;
	$name =~ s/ {2,}/ /g;
	
	$url =~ s/.*?\/(\d+)_lsr_(\d+).pdf/$1:$2/;
	# $url =~ s/.*?\/(\d+)_lsnv_(\d+).pdf/nv:$1:$2/;
	# $url =~ s/.*?\/(\d+)_lsr_ec_(\d+).pdf/ec:$1:$2/;
	$url =~ s/.*?\/(\d+)_lsr?_?([a-z]{2})_(\d+).pdf/$2:$1:$3/;
	# $url ||= $booklet if ($name ne 'ת"ט');
	
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

#-----------------------------------------------------------------------------------------

sub process_law {
	my $id = shift;
	my $last = 0;
	my $page = $primary_prefix.$id;
	my $new = 0;
	
	my ($src_page, $text, $todo);
	
	my @list;
	
	if ($dump and -f "p$id.dump") {
		my $tt = retrieve("p$id.dump");
		@list = @{$tt->{list}};
		$law_name = $full_name = $tt->{name};
	} else {
		@list = get_primary_page($page);
		my %tt = ('list' => \@list, 'name' => $law_name);
		store \%tt, "p$id.dump" if ($dump);
	}
	
	print "    Got primary #$id '$full_name'.\n";
	
	$src_page = "מקור:$law_name";
	# $src_page =~ s/ /_/g;
	$text = $bot->get_text($src_page);
	unless (@list) {
		print "\tFailed to fetch data.\n";
		return 0;
	}
	if (!$text) {
		$text = $bot->get_text($law_name);
		if (!$text && scalar(@list)<=2) {
			print "\tPage '$law_name' not found, new law.\n";
			$text = "";
			$new = 1;
		}
		elsif (!$text) {
			print "\tPage '$law_name' not found.\n";
			return 0;
		}
		elsif ($text =~ /#(?:הפניה|Redirect) \[\[(?:מקור:|)(.*?)\]\]/) {
			print "\tRedirection '$law_name' to '$1'.\n";
			$law_name = $1;
			$src_page = "מקור:$law_name";
			$text = $bot->get_text($src_page);
			if (!$text) {
				print "\tPage '$src_page' not found.\n";
				return 0;
			}
		} else {
			print "\tPage '$law_name' found, but page '$src_page' does not exist.\n";
			return 0;
		}
	}
	if ($text =~ /#(?:הפניה|Redirect) \[\[(?:מקור:|)(.*?)\]\]/) {
		print "\tRedirection '$law_name' to '$1'.\n";
		$law_name = $1;
		$src_page = "מקור:$law_name";
		$text = $bot->get_text($src_page);
	}
	
	my $text_org = $text;
	
	print "\tPage '$src_page' found, size ", length($text), ".\n" unless ($new);
	
	$alt_names = join('|', $text =~ /^<שם(?: קודם)?>[ \n]*(.*?)(?:, *(?:ה?תש.?["״].[\-־–])?\d{4})? *(?:\(תיקון:.*?\) *)?$/mg);
	print "\tLaw name(s) is '$alt_names'\n";
	$alt_names =~ s/([()])/\\$1/g;
	
	$text =~ s/^ +//s;
	$text =~ s/^= *([^\n]*?) *= *\n/<שם> $1\n/s;
	$text =~ s/^<שם>[ \n]+(.*?) *\n/<שם> $1\n/s;
	
	print "\tChecking page: ";
	if ($new) {
		$last = 0;
		$text = "<שם> $full_name\n\n";
		$text .= "<מאגר $id תיקון 0>\n\n";
		$text .= "<מקור> <!-- חוק חדש -->\n\n";
	} elsif ($text !~ /<מאגר[ א-ת]* (\d+)(?: *(?|תי?קון|עדכון) *(\d+)|) *>/ || !defined $1) {
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
	($last_type, $last_year, $last_id, $first_run) = undef;
	my ($partial, $prev) = '';
	
	@list = reverse @list;
	@list = sort { sort_laws($a,$b) } @list;
	
	for ($i=0, $partial = $prev = ''; $i<@list; $i++) {
		$partial .= print_fix(@{$list[$i]}) // '';
		$prev .= $partial and $partial = '' if ($list[$i]->[5] eq $last);
	}
	$i = $list[-1][5];
	if ($partial) {
		$partial .= '.';
		print "\t\tPartial string: $partial\n";
	}
	
	unless ($i) {
		print "\tERROR: UPDATE not found (something is wrong)... Skipping.\n";
		return 0;
	}
	
	if ($text =~ /^(.*?)\n+(<מקור>.*?)\n\n(.*?)$/s || $text =~ /^(.*?)\n+(<מקור>.*?)\n*()$/s) {
		# Decompose and recompose text.
		my $pre = $1; my $post = $3; $text = $2;
		while ($post =~ s/^([^\n]{0,20}\(\(.*?)\n\n//) { $text .= "\n\n$1"; }
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
	
	$text =~ s/<מאגר.*>\s*/<מאגר $id תיקון $i>\n\n/;
	
	if ($text eq $text_org) {
		print "\tNo change.\n";
		return 0;
	}
	
	print "\tLast update: <מאגר $id תיקון $i>\n";
	
	if (false && $dryrun && $verbose) {
		$text =~ /^(.{0,1000})/s;
		print "SOURCE TEXT: >>>>\n$1<<<<\n";
	}
	
	my $count = () = ($todo =~ /^\*+ /mg);
	
	# Page was modified, update WIKI
	# $src_page = "מקור:$law_name";
	my $talk_page = "שיחה:$law_name";
	my $todo_page = "שיחה:$law_name/מטלות";
	
	my $summary = ($count==1 ? "בוט: עדכון לחוק" : "בוט: $count עדכונים לחוק");
	$summary = 'בוט: קישורים' if $count==0;
	$summary = 'בוט: חוק חדש' if $new;
	print "\tUpdating page with summary \"$summary\"\n";
	$bot->edit({
		page => $src_page, text => $text, summary => $summary,
		bot => 1, minor => 1,
	}) if !$dryrun;
		
	if ($new) {
		$todo .= "* הוספת חוק חדש [[משתמש:OpenLawBot/הוספה|לבוט]]\n";
		$count++;
	}
	
	if ($count>0) {
		$text = $bot->get_text($todo_page);
		if ($text) {
			$text =~ s/\n+$//s;
			$text .= "\n$todo";
		} else {
			$text = "<noinclude>{{מטלות}}</noinclude>\n$todo";
		}
		print "TODO TEXT: >>>>\n$text<<<<\n" if ($dryrun && $verbose);
		unless ($dryrun) {
			$bot->edit({
				page => $todo_page, text => $text, summary => $summary,
				bot => 1, minor => 1,
			});
			
			$text = $bot->get_text($talk_page) // "";
			unless ($text && $text =~ /\{\{(מטלות|משימות)\}\}/) {
				$text = "{{מטלות}}\n\n$text";
				$bot->edit({
					page => $talk_page, text => $text, summary => "תבנית מטלות",
					bot => 1, minor => 1,
				});
			}
			$bot->purge_page($todo_page);
			$bot->purge_page($talk_page);
		}
	}
	
	# Push [$lawname,$count] at front
	unshift @global_todo, $law_name, $count if ($count>0);
	
	return 1;
}


sub update_makor {
	my ($text, $old, $new) = @_;
	my $i = 0;
	my (@uuu, $u, $p, $n);
	my $text2;
	my $str2 = $old.$new;
	my $text_org = $text;
	
	my @urls;
	
	while ($str2 =~ /\(\(([^|]*)\|([^|]*?)(?|\|([a-z]*:?\d[\d:_]+)|())\)\)([.,;]?)/g) {
		# print "\t\tDecode, got (($1|$2|$3)).\n" if ($verbose);
		push @urls, [$1, $2, $3, $4];
	}
	
	if (!scalar(@urls)) {
		return ($text, '');
	}
	
	my $trynext = 0;
	
	if ($history) {
		for ($i = 0; $i < @urls; $i++) {
			$p = $urls[$i][0]; $n = $urls[$i][1]; $u = $urls[$i][2] // '';
			if ($text =~ /\|$u\)\)/) {
				pos($text) = $+[0]; # $text =~ m/\|$u\)\)/g;
				while ($str2 =~ s/^.*?\|$u\)\)//s) {};
				$trynext = 0;
				next;
			}
			$text =~ m/\G[^\n]*?(\(\(.*?\)\))(?!\))/gc || next;
			my $lastpos = $-[1];
			my $text2 = $1;
			$text2 =~ /^\(\(([^|]*)\|([^|]*)\|?([^)|]*)\)\)$/ || next;
			# print "\t\tGot (($p|$n|$u)) and $text2.\n" if ($verbose);
			if (comp_str($1, $p) || comp_str($2, $n)) {
				$trynext = 0;
				if (!$u) {
					# print "\t\tNo URL, next please.\n" if ($verbose);
					$str2 =~ s/^.*?\)\)//s;
					next;
				}
				$text2 = "(($p|$2|$u))";
				if (comp_str($1, $p)) {
					print "\t\tReplacing '$3' with '$u'\n";
				} else {
					print "\t\tReplacing '$3' with '$u'\n";
					# print "\t\tReplacing '$1' with '$p' and '$3' with '$u'\n";
					$p = $1;
				}
				$str2 =~ s/^.*?\|$u\)\)//s;
				pos($text) = $lastpos;
				$text =~ s/\G(\(\(.*?\)\))(?!\))/$text2/;
				# Rewind and find next:
				pos($text) = $lastpos; $text =~ m/\(\(.*?\)\)(?!\))/g;
			} else {
				if (!$trynext) {
					# Retry next position
					$trynext = $lastpos;
					$i--;
				} else {
					# We already tried next position, and failed.
					pos($text) = $trynext; $text =~ m/\(\(.*?\)\)(?!\))/g;
				}
			}
		}
		# restore str2
		$str2 = $old.$new;
	}
	
	for ($i = @urls-1; $i>=0; $i--) {
		$u = $urls[$i][2] || next;
		if ($text =~ /\|$u\)\)/) {
			pos($text) = $+[0]; # $text =~ m/\|$u\)\)/g;
			while ($str2 =~ s/^.*?\|$u\)\)//s) {};
			last;
		}
	}
	$text =~ m/<מקור>[ \n]*/g if ($i<0); # No URL match found, start from zero.
	$i++; $trynext = 0;
	for (; $i < @urls; $i++) {
		$p = $urls[$i][0]; $n = $urls[$i][1]; $u = $urls[$i][2] // '';
		$text =~ m/\G[^\n]*?(\(\(.*?\)\))(?!\))/gc || last;
		my $lastpos = $-[1];
		my $text2 = $1;
		$text2 =~ /^\(\(([^|]*)\|([^|]*)\|?([^)|]*)\)\)$/ || last;
		print "\t\tGot (($p|$n)) and $text2.\n" if ($verbose);
		if ($1 eq $p || $2 eq $n) {
			$trynext = 0;
			if (!$u) {
				print "\t\tNo URL, next please.\n" if ($verbose);
				$str2 =~ s/^.*?\)\)//s;
				next;
			}
			$text2 = "(($p|$2|$u))";
			if ($1 eq $p) {
				print "\t\tReplacing '$3' with '$u'\n";
			} else {
				print "\t\tReplacing '$1' with '$p' and '$3' with '$u'\n";
			}
			$str2 =~ s/^.*?\|$u\)\)//s;
			# $text =~ m/(.{10})\G(.{0,10})/;
			# print "\t\tPOS is ", pos($text), "; Now at ... $1 <-G-> $2 ...\n";
			pos($text) = $lastpos;
			$text =~ s/\G(\(\(.*?\)\))(?!\))/$text2/;
			# Rewind and find next:
			pos($text) = $lastpos; $text =~ m/\(\(.*?\)\)(?!\))/g;
			# $text =~ m/(.{10})\G(.{0,10})/;
			# print "\t\tPOS is ", pos($text), "; Now at ... $1 <-G-> $2 ...\n";
		} else {
			if (!$trynext) {
				# Retry next position
				$trynext = $lastpos;
				$i--;
			} else {
				# We already tried next position, and failed.
				pos($text) = $trynext; $text =~ m/\(\(.*?\)\)(?!\))/g;
				last;
			}
		}
	}
	
	$text =~ m/\G[ .,;]*/gc;
	
	$text =~ m/(.{0,20})\G(.{0,20})/;
	print "\t\tPOS is ", pos($text), "; Now at ... $1<-G->$2 ...\n";
	
	($text2) = ($text =~ /^(.*)\G/s);
	
	my $comment = 0;
	$comment = ($1 eq '<!--') while ($text2 =~ m/(<!--|-->)/g);
	
	if ($str2 =~ /\(\(/) {
		if ($comment) {
			$text =~ s/[.,;]? *\G */ $str2 /;
		} else {
			$text =~ s/ *\G */ <!-- $str2 --> /;
		}
		$text =~ s/ +$//gm;
	}
	
	$str2 = makor_to_todo($str2);
	
	if (false && $dryrun && $verbose && $text ne $text_org) {
		print "\t\$text is \n$text\n";
		print "\t\$str2 is \n$str2";
	}
	return ($text, $str2);
}

sub makor_to_todo {
	my $todo = shift;  # input str
	my $count = shift; # maximal number of items
	my @todo = ($todo =~ /(\(\(.*?\)\))/g);
	map s/\(\(([^|]*)\|([^|]*)\|(\d+):(\d+)\)\)/* {{חוק-תיקון|$2|http:\/\/fs.knesset.gov.il\/$3\/law\/$3_lsr_$4.pdf}}\n/ || 
		s/\(\(([^|]*)\|([^|]*)\|?(.*?)\)\)/* {{חוק-תיקון|$2}}\n/ || 
		s/.*//, @todo;
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
		if ($text =~ /^[ *]*\[\[שיחה:$name(?:\|[^\[\]]*|)\]\] {{מוקטן\|(\d+)}}/mg) {
			pos($text) = $-[0];
			$count += $1 // 0;
			$text =~ s/\G.*\n?/* [[שיחה:$name|]] {{מוקטן|$count}}\n/m;
		} else {
			$text .= "* [[שיחה:$name|]] {{מוקטן|$count}}\n";
		}
	}
	$text =~ s/\n\n/\n/g;
	$text .= "</div>\n";
	
	return if ($laws == 0 || $total == 0);
	
	my $summary = "הוספת " . ($total>1 ? "$total עדכונים" : "עדכון אחד") . ($laws>1 ? " ב-$laws חוקים" : " בחוק אחד");
	
	if ($dryrun) {
		print "Global todo list ($summary).\n";
	} else {
		$bot->edit({
			page => $page, text => $text, summary => $summary,
			bot => 1, minor => 1,
		});
		$bot->purge_page($page);
		$bot->purge_page('ויקיטקסט:ספר החוקים הפתוח');
	}
}
