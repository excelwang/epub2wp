#use Lingua::Han::PinYin;
use DBI;
#use Encode;
#use utf8;
#my $h2p = Lingua::Han::PinYin->new();
#epub文件地址，是否生成单篇文章
#die("Usage: [-s] <epub file path>\n\t -s means generate single post.\n") if( $ARGV[-1] ne "-s" || defined($epub_ori)==0);
#my $cmd_single="-s";
my $dbh = DBI->connect("DBI:mysql:wp_kanlr:localhost;mysql_socket=/opt/lampp/var/mysql/mysql.sock","kanlr","90onw1ndK");
$dbh->do("SET NAMES UTF8");
my $page_url= "24shi-".time;
my $page_text= "";
my $page_title= "二十四史";
foreach $epub_ori(@ARGV){
	my $wordpress_path="/opt/lampp/htdocs/kanlr";
	system("unzip -oq $epub_ori -d ext-$epub_ori-d;");
	my $base_path="ext-$epub_ori-d/OEBPS";
	#1. 分析toc.ncx，获取书籍元数据和书籍目录
	my $toc_file="$base_path/toc.ncx";
	my $opf_file="$base_path/content.opf";
	my $title="";
	my $index="";
	my %book_urls={};
	#binmode(TOC,':encoding(utf8)');
	open(TOC,$toc_file)||die("original epub toc file:$toc_file not exists!\n");
	$/=undef;
	my @lines=<TOC>;
	foreach(@lines){
		# eval {my $str2 = $_; Encode::decode("gbk", $str2, 1)};
		# print "not gbk: $@/n" if $@;

		# eval {my $str2 = $_; Encode::decode("utf8", $str2, 1)};
		# print "not utf8: $@/n" if $@;

		# eval {my $str2 = $_; Encode::decode("big5", $str2, 1)};
		# print "not big5: $@/n" if $@;
		#Encode::_utf8_on($_);
		#$_ = encode("utf8",decode("gbk",$_));
		#$_ = encode_utf8(decode("gbk",$_));
		#print $_;
		s/\n//g;
		/<navMap>(.*)<\/navMap>/ ||die("original epub toc: $epub_ori error!\n");
		$index=$1;
		$index=~s/\s*<navPoint[^>]*>\s*<navLabel>\s*<text>([^<]*)<\/text>\s*<\/navLabel>\s*<content src="([^"]*)"\s*\/>/<div class="epub-toc"><a href="\2">\1<\/a>/g;
		$index=~s/\s*<\/navPoint>/<\/div>\n/g;
	}
	$/ = "\n";
	close(TOC);
	open(OPF,$opf_file)||die("original epub toc file:$opf_file not exists!\n");
	$/=undef;
	my @lines=<OPF>;
	foreach(@lines){
		s/\n//g;
		#$_ = encode_utf8(decode("gbk",$_));
		/<dc:title>(.*?)<\/dc:title>/ ||die("original epub opf title: $epub_ori error!\n");
		$title=$1;
	}
	$/ = "\n";
	close(OPF);
	#2. 分析、写入书籍章节
	my @htmls= $index=~/href="(.*?.x?html?)/g;
	my %htmls_unique =();
	my $i=0;
	foreach my $html (@htmls){
	  $htmls_unique{$html}=$i++;
	}
	@htmls = sort { $htmls_unique{$a} <=> $htmls_unique{$b} } keys %htmls_unique;
	$i=0;
	#url变为：书名pinyin-时间秒数-章节数
	#$book_url= $h2p->han2pinyin($title)."-".time;
	$book_url= time;
	#处理图片
	$pic_path="$wordpress_path/img/$book_url";
	system("mkdir -p $pic_path;mv $base_path/Images/* $pic_path/");
	my @chapters=();
	my $fulltext="";
	foreach my $html (@htmls){
		my $chaper_url="$book_url-$i";
		my $chaper_text="";
		$index=~/$html\s*">(.*)<\/a>/;
		my $chapter_title="$title $1";
		#binmode(HTML,':encoding(utf8)');
		open(HTML,"$base_path/$html")||die("original epub text file:$base_path/$html not exists!\n");
		$/=undef;
		my @lines=<HTML>;
		foreach(@lines){
			#$_ = encode_utf8(decode("gbk",$_));
			#Encode::_utf8_on($_);
			#$_ = encode("utf8",decode("gbk",$_));
			s/\n//g;
			s/src="..\/Images/src="img\/$book_url/g;
			s/^.*?<body>\s*//;
			s/\s*<\/body>.*$//;
			$chaper_text.=$_;
		}
		$/ = "\n";
		close(HTML);
		if($cmd_single){
			$fulltext.=$chaper_text;
		}else{
			push @chapters,$chaper_url;
			push @chapters,$chapter_title;
			push @chapters,$chaper_text;
			$index=~s/$html/$book_url-$i/g;
			++$i;
		}
	}
	$index=$fulltext if($cmd_single);
	my $auther_id="1";
	my $doc_pre = $dbh->prepare("INSERT INTO `wp_posts` (`post_author`, `post_date`, `post_date_gmt`, `post_content`, `post_title`, `post_excerpt`, `post_status`, `comment_status`, `ping_status`, `post_password`, `post_name`, `to_ping`, `pinged`,`post_content_filtered`,`post_parent`,`guid`, `menu_order`, `post_type`, `post_mime_type`, `comment_count`) VALUES ($auther_id,now(),now(),?,?, '', 'publish', 'closed', 'open', '',?, '', '', '',?,'http://kanlr.com/?p=-1', '0', 'post', '', '0');");
	my $row_num = $doc_pre->execute($index,$title,$book_url,'0');#插入书籍索引页
	$row_num || die "insert error: chapter $chaper_url";
	my $id_pre=$dbh->prepare("select max(ID) from `wp_posts`");
	$id_pre->execute();
	my($parent_id)=$id_pre->fetchrow_array();
	$id_pre->finish();
	while((my $chaper_url=shift(@chapters))&&(my $chapter_title=shift(@chapters))&&(my $chaper_text=shift(@chapters))){
		my $row_num = $doc_pre->execute($chaper_text,$chapter_title,$chaper_url,$parent_id);
		$row_num || die "insert error: chapter $chaper_url";
		$id_pre->execute();
		($parent_id)=$id_pre->fetchrow_array() if($parent_id==0);
		#print "url:$chaper_url; title:$chapter_title; text:$chaper_text\n";
	}
	$doc_pre->finish();
	$cmd_single="";
	$page_text.="<div class=\"page-toc\"><a href=\"/$book_url\">$title</a></div>";
}
my $page_pre = $dbh->prepare("INSERT INTO `wp_posts` (`post_author`, `post_date`, `post_date_gmt`, `post_content`, `post_title`, `post_excerpt`, `post_status`, `comment_status`, `ping_status`, `post_password`, `post_name`, `to_ping`, `pinged`, `post_modified`, `post_modified_gmt`, `post_content_filtered`, `post_parent`, `guid`, `menu_order`, `post_type`, `post_mime_type`, `comment_count`) VALUES ('1', now(),now(),?,?,'', 'publish', 'closed', 'open', '',?, '', '',now(),now(), '', '0', 'http://kanlr.com/?page_id=-2', '0', 'page', '', '0');");
my $row_num = $page_pre->execute($page_text,$page_title,$page_url);
$row_num || die "insert error: page $page_url";
$page_pre->finish();
$dbh->disconnect;#断开数据库连接
# `rm -r converted-$epub_ori.epub`;
# system("rm -r converted-$epub_ori");
# mkdir("converted-$epub_ori");
# mkdir("converted-$epub_ori/OEBPS");
# mkdir("converted-$epub_ori/OEBPS/Styles");
# mkdir("converted-$epub_ori/OEBPS/Text");
# system("cp tamplete-epub/OEBPS/Styles/*css converted-$epub_ori/OEBPS/Styles/");

# $/=undef;
# open(OPF,"OPS/content.opf");
# @lines=<OPF>;
# $/ = "\n";
# close(OPF);
# foreach(@lines){s/\n//g};
# my $info="";
# my $pages1="";
# my $pages2="";
# foreach(@lines){
	# /<dc:title>(.*)<\/dc:identifier>.*text\/css"\s\/>(.*)<item\sid="donate".*"readme"\s\/>(.*)<itemref\sidref="donate"/ || die("original epub opf: $epub_ori error!\n");
	# $info=$1;
	# $pages1=$2;
	# $pages2=$3;
	# $info=~s/.*\s([^\s]*)\s.*<\/dc:title>/\1<\/dc:title>/g;
	# $pages1=~s/href="/href="Text\//g;
# }

# $/=undef;
# open(CNT_TPL,"tamplete-epub/OEBPS/content.opf");
# open(CNT_C,">converted-$epub_ori/OEBPS/content.opf");
# @lines=<CNT_TPL>;
# $/ = "\n";
# close(CNT_TPL);
# foreach(@lines){
	# s/\$info/$info/;
	# s/\$pages1/$pages1/;
	# s/\$pages2/$pages2/;
	# print CNT_C;
# }
# close(CNT_C);

# system("rm  OPS/*ncx OPS/*opf");


# my $path="OPS";
# opendir(DIR,$path);
# @entries =grep (!/^\.\.?$/, readdir DIR);
# @entries=sort(@entries);
# closedir(DIR);
# $/=undef;
# open(HTML_TPL,"tamplete-epub/OEBPS/Text/tml.html");
# @lines=<HTML_TPL>;
# $/ = "\n";
# my $tml=$lines[0];
# close(HTML_TPL);

# $/=undef;
# open(TOC_TPL,"tamplete-epub/OEBPS/Text/TOC.xhtml");
# @lines=<TOC_TPL>;
# $/ = "\n";
# my $toc_tml=$lines[0];
# close(TOC_TPL);
# open(TOC_OUT,">>converted-$epub_ori/OEBPS/Text/TOC.xhtml");
# print TOC_OUT $toc_tml;
# my @juannames=();
# foreach (@entries) {
	# open(XHTML,"$path/$_");
	# open(XHTML_OUT,">converted-$epub_ori/OEBPS/Text/$_");
	# $/=undef;
	# @lines=<XHTML>;
	# foreach(@lines){s/\n//g};
	# $/ = "\n";
	# close(XHTML);
	# my $article="";
	# my $curfile=$_;
	# foreach(@lines){
		# s/^.*?uanname">(.+?)<\/span><a/<h2>\1<\/h2><a/;
		# push (@juannames,$1);
		# print TOC_OUT "<div class=\"sgc-toc-level-1\"><a href=\"../Text/$curfile\">$1</a></div>\n";
		# s/<a\s*id="[^"]+"><\/a>//g;
		# s/<\/span>\s*<br\s*\/>\s*<br\s*\/>\s*<span\s*class="byline">/<br\/>/g;
		# s/([(h2)(p)]>)\s*<br\s*\/>\s*<br\s*\/>\s*<span\s*class="byline">(.*?)<\/span>/\1\n<p class="author">\2/;
		# s/\s*<br\s*\/>\s*<br\s*\/>\s*/<\/p><p>/g;
		# s/<hr.*?<hr.*$/<\/p>/;
		# s/<div[^>]+>//g;
		# s/<\/div>//g;
		# my $qjkg="　";
		# s/>($qjkg)+</></g;
		# #s/>($qjkg)+/>/g;
		# s/\s+</</g;
		# s/>\s+/>/g;
		# s/p><p/p>\n<p/g;
		# s/<p><\/p>//g;
		# s/><span(\sclass="juanname">.*?)<\/span>/\1/g;
		# s/><span(\sclass="headname">.*?)<\/span>/\1/g;
		# s/<p>(.*?)<\/p>/<p><span class="vline">\1<\/span><\/p>/g;
		# s/<p(><span\sclass="vline">)<span\sclass="lg">(.*?)<\/span>(<\/span><\/p>)/<p class="poem"\1\2\3/g;
		# s/<p>(.*?\s+.*?)(<p\sclass="poem">)/<p class="beforePoem">\1\2/g;
		# $article.=$_;
	# }
	# my $vtml=$tml;
	# $vtml=~s/\$content/$article/;
	# print XHTML_OUT $vtml;
	# close(XHTML_OUT);
# }
# print TOC_OUT "<\/body></html>";
# close(TOC_OUT);
# my $i=0;
# my @items=split("</navPoint>",$navMap);
# for ($i..@juannames){
	# my $name=$juannames[$i];
	# $name=~s/<span.*?<\/span>//g;
	# $items[$i]=~s/(<navLabel>[^<]*<text>).*?(<\/text>[^<]*?<\/navLabel>)/\1$name\2/;
	# $i++;
# }
# $navMap=join("</navPoint>",@items);

# open(TOC_C,">converted-$epub_ori/OEBPS/toc.ncx");
# open(TOC_TEMPLETE,"tamplete-epub/OEBPS/toc.ncx");
# $/=undef;
# @lines=<TOC_TEMPLETE>;
# $/ = "\n";
# close(TOC_TEMPLETE);
# foreach(@lines){
	# s/\$head/$head/;
	# s/\$docTitle/$docTitle/;
	# $navMap=~s/(src=")(.*?)#.*?(")/\1Text\/\2\3/g;
	# s/\$navMap/$navMap/;
	# print TOC_C;
# }
# close(TOC_C);

# system("cp -r tamplete-epub/mimetype tamplete-epub/META-INF converted-$epub_ori");
# system("zip -rq converted-$epub_ori.epub converted-$epub_ori");
# system("rm -r OPS mimetype META-INF converted-$epub_ori");
