#!/usr/bin/perl -w

use strict;
no strict 'refs';
no if ($]>=5.018), warnings => 'experimental';
use English;
use utf8;
use Data::Dumper;
use HTML::Parser;
use HTML::TreeBuilder::XPath;
use IO::HTML;
use Getopt::Long;


my $what = 0;
GetOptions(
	"dump" => sub { $what = 0 },
	"print" => sub { $what = 1 },
	"short" => sub { $what = 2 },
	"url" => sub { $what = 3 },
) or die $!;

my $page = $ARGV[0];
my $id;
my ($tree, @trees);
my (@table, @lol);
my $law_name;

my $primary_prefix = 'http://main.knesset.gov.il/Activity/Legislation/Laws/Pages/LawPrimary.aspx?lawitemid=';
my $secondary_prefix = 'http://main.knesset.gov.il/Activity/Legislation/Laws/Pages/LawSecondary.aspx?lawitemid=';

$page = $primary_prefix.$page if ($page =~ /^\d+$/);

binmode STDOUT, ":utf8";
binmode STDERR, ":utf8";

@lol = get_primary_page($page);

# # Sort array in lexicographical order of [booklet, page, lawid].
# @lol = sort { $a->[2] <=> $b->[2] || $a->[3] <=> $b->[3] || $a->[5] <=> $b->[5] } @lol;
# Sort array in lexicographical order of [booklet, page, NAME] (lawid is not monotonic).
# @lol = grep { $_->[2] =~ /\d+/ } @lol;
# @lol = sort { $a->[2] <=> $b->[2] || $a->[3] <=> $b->[3] || $a->[0] cmp $b->[0] } @lol;
@lol = reverse @lol;
@lol = sort { compare_law($a,$b) } @lol;

if ($what>1) {
	print "<מאגר $id תיקון $lol[-1][5]>\n\n";
	print "<מקור>\n";
}

my $str = '';
foreach my $list (@lol) {
	$str .= print_fix(@$list) if ($what>=1);
	$str .= print_line(@$list) if ($what==0);
}

$str .= print_fix() if ($what>=1);
print $str;

exit 0;

#-------------------------------------------------------------------------------

sub compare_law {
	my ($a, $b) = @_;
	my $a_date = $a->[4] =~ s/.*?(\d{1,2})(.)(\d{1,2})\2(\d{4}).*?/sprintf("%04d%02d%02d",$4,$3,$1)/re;
	my $b_date = $b->[4] =~ s/.*?(\d{1,2})(.)(\d{1,2})\2(\d{4}).*?/sprintf("%04d%02d%02d",$4,$3,$1)/re;
	my $res = 0;
	
	$res = -1 if (!$a_date || !$b_date); # Keep order if no date is given
	
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

my ($last_type, $last_year, $last_id);
# my $law_name;
my $first_run;

sub print_line {
#	pop @_;
	return join('|',@_) . "\n";
}

sub print_fix {
	$first_run = (!defined($first_run));
	my ($name, $type, $booklet, $page, $date, $lawid, $url) = @_;
	my $year = ''; my $type2;
	my $str = '';
	
	if (!defined($name)) {
		$str = ".\n" if (!$first_run);
		return $str;
	}
	
#	return if ($lawid ne '' && $last_id && $lawid eq $last_id);
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
	$name =~ s/^(?:חוק לתיקון |תיקון ל|)(\S.*?) \((תי?קון .*?)\)(.*)/$2 $3 ל$1/;
	$name =~ s/ *ל$law_name//;
	$name =~ s/ *(.*?) */$1/;
	$name =~ s/ {2,}/ /g;
	
	if ($url) {
		$url =~ s/.*?\/(\d+)_lsr_(\d+).pdf/$1:$2/;
		$url =~ s/.*?\/(\d+)_lsnv_(\d+).pdf/nv:$1:$2/;
		$url =~ s/.*?\/(\d+)_lsr_ec_(\d+).pdf/ec:$1:$2/;
		$url ||= $booklet if ($name ne 'ת"ט');
	}
	
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
	$str .= "|$url" if ($url and $what>=2);
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
	# print STDERR "MMDD = $mmdd; PAGE = $page; threshold = " . (100 + ($year-5700)*2) . "\n";
	$year++ if (($mmdd > "0900" and $mmdd <= "1015" and $page<100 + ($year-5700)*2) or ($mmdd > "1015"));
	$year =~ /(\d)(\d)(\d)(\d)$/;
	$year = (qw|- ק ר ש ת תק תר תש תת תתק|)[$2] . (qw|- י כ ל מ נ ס ע פ צ|)[$3] . (qw|- א ב ג ד ה ו ז ח ט|)[$4];
	$year =~ s/-//g;
	$year =~ s/י([הו])/"ט" . chr(ord($1)+1)/e;  # Handle טו and טז.
	$year =~ s/([כמנפצ])$/chr(ord($1)-1)/e;     # Ending-form is one char before regular-form.
	$year =~ s/(?=.$)/"/;
	return $year;
}

sub trim {
	my $_ = shift // '';
	s/^[ \t\xA0\n]*(.*?)[ \t\xA0\n]*$/$1/s;
	return $_;
}

sub decode_url {
	my $_ = shift;
	s/%([0-9A-Fa-f]{2})/pack('H2',$1)/ge;
	return $_;
}

sub law_name {
	my $_ = shift;
	s/^[ \n]*(.*?)[ \n]*$/$1/;
	s/, (ה?תש.?".[-–])?\d{4}//;
	s/ *[\[\(](נוסח משולב|נוסח חדש|לא בתוקף)[\]\)]//g;
	# print "Law is \"$law_name\"\n";
	return $_;
}

sub get_primary_page {
	my $page = shift;
	my $count = 0;
#	my $id;
	my ($tree, @trees);
	my (@table, @lol);
	
	$page = $primary_prefix.$page unless ($page =~ /^https?:/);
	
	print STDERR "Reading pages... ";
	while ($page) {
		print STDERR "+";
		$count++;
		$tree = HTML::TreeBuilder::XPath->new_from_url($page);
		push @trees, $tree;
		
		my @loc_table = $tree->findnodes('//table[contains(@class, "rgMasterTable")]//tr');
		
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
	print STDERR "\n";
	if (!scalar(@table)) {
		print STDERR "No data.\n";
		$_->delete() for (@trees);
		return [];
	}

	my $full_name = trim($tree->findvalue('//td[contains(@class,"LawPrimaryTitleBkgWhite")]')) ||
		trim($tree->findvalue('//div[@class="LawPrimaryTitleDiv"]/h3'));
	$law_name = law_name($full_name);
	# print "Law $id \"$law_name\"\n";
	
	my $count2 = 0;
	
	foreach my $node (@table) {
		my @list = $node->findnodes('td');
		shift @list;
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
			print STDERR "Additional...    " unless($count2);
			print STDERR "+"; $count2++;
			my @list2 = get_secondary_entry($lawid);
			if ($list2[3]) {
				$url = pop @list2;
				$list2[3] = $list[3] if ($list[3]);
				@list = @list2;
			}
		}
		
		push @list, $lawid, $url; #, scalar(@lol);
		grep(s/^[ \t\xA0]*(.*?)[ \t\xA0]*$/$1/g, @list);
		push @lol, [@list];
	}
	
	print STDERR "\n" if ($count2>0);
	$_->delete() for (@trees);
	return @lol;
}

sub get_secondary_entry {
	my $page = shift;
	my $id;
	my $tree;
	my (@table, @lol);
	my @entry;
	
	$page = $secondary_prefix.$page unless ($page =~ /^https?:/);
	
	# print "Reading HTML file $page...\n";
	$tree = HTML::TreeBuilder::XPath->new_from_url($page);
	
	my $law_name = law_name($tree->findvalue('//td[contains(@class,"LawPrimaryTitleBkgWhite")]'));
	$law_name =~ s/^[ \n]*(.*?)[ \n]*$/$1/;
	$law_name =~ s/, ([א-ת"]*-)?\d{4}//;
	$law_name =~ s/ *[\[\(](נוסח משולב|נוסח חדש|לא בתוקף)[\]\)]//g;
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
#	print STDERR "Entry is " . print_line(@entry);
	
	grep(s/^[ \t\xA0]*(.*?)[ \t\xA0]*$/$1/, @entry);
	$tree->delete();
	return @entry;
}
