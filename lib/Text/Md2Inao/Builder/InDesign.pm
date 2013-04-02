## THIS MODULE IS STILL UNDER DEVELOPMENT
package Text::Md2Inao::Builder::InDesign;
use utf8;
use strict;
use warnings;

use Text::Md2Inao::Logger;
use Text::Md2Inao::Util;

use Text::Md2Inao::Builder;
use parent qw/Text::Md2Inao::Builder/;

case default => sub {
    my ($c, $h) = @_;
    $h->as_HTML('', '', {});
};

case text => sub {
    my ($c, $text) = @_;
    if ($text =~ m!\(注:! or $c->in_footnote) {
        $text = replace_note_parenthesis($c, $text, '注');
        $text =~ s!◆注/◆!<fnStart:><pstyle:注釈>!g;
        $text =~ s!◆/注◆!<fnEnd:><cstyle:>!g;
    }
    # 改行を取り除く
    $text =~ s/(\n|\r)//g;
    # キャプション
    if ($text =~ s!^●(.+?)::(.+)!●$1\t$2!) {
        $text =~ s!\[(.+)\]$!\n$1!;
    }
    # リストスタイル文字の変換
    $text = to_list_style($text);
    return $text;
};

case "h1" => sub {
    my ($c, $h) = @_;
    return sprintf "<ParaStyle:大見出し>%s\n", $h->as_trimmed_text;
};

case "h2" => sub {
    my ($c, $h) = @_;
    return sprintf "<ParaStyle:中見出し>%s\n", $h->as_trimmed_text;
};

case "h3" => sub {
    my ($c, $h) = @_;
    return sprintf "<ParaStyle:小見出し>%s\n", $h->as_trimmed_text;
};

case "h4" => sub {
    my ($c, $h) = @_;
    return sprintf "<ParaStyle:コラムタイトル>%s\n", $h->as_trimmed_text;
};

case "h5" => sub {
    my ($c, $h) = @_;
    return sprintf "<ParaStyle:コラム小見出し>%s\n", $h->as_trimmed_text;
};

case "strong" => sub {
    my ($c, $h) = @_;
    return sprintf "<CharStyle:太字>%s<CharStyle:>", $h->as_trimmed_text;
};

case "em" => sub {
    my ($c, $h) = @_;
    my $ret;
    $ret .= $c->use_special_italic ? '<CharStyle:イタリック（変形斜体）>' : '<CharStyle:イタリック（変形斜体）>';
    $ret .= $h->as_trimmed_text;
    $ret .= '<CharStyle:>';
    return $ret;
};

case "code" => sub {
    my ($c, $h) = @_;
    return sprintf "<CharStyle:コマンド>%s<CharStyle:>", $h->as_trimmed_text;
};

case p => sub {
    my ($c, $h) = @_;
    my $text = $c->parse_element($h);
    if ($text !~ /^[\s　]+$/) {
        my $label = $c->in_column ? 'コラム本文' : '本文';
        return sprintf "<ParaStyle:%s>%s\n", $label, $text;
    }
};

## FIXME: https://github.com/inao/idtagreplacer/blob/master/sample/tagconf.xml の自由置換設定を反映させる必要
case kbd => sub {
    my ($c, $h) = @_;
    sprintf "<cFont:Key Mother>%s<cFont:>" ,$h->as_trimmed_text;
};

case span => sub {
    my ($c, $h) = @_;
    if ($h->attr('class') eq 'red') {
        return sprintf "<CharStyle:赤字>%s<CharStyle:>", $h->as_trimmed_text;
    }
    elsif ($h->attr('class') eq 'ruby') {
        my $ruby = $h->as_trimmed_text;
        $ruby =~ s!(.+)\((.+)\)!<cr:1><crstr:$2><cmojir:0>$1<cr:><crstr:><cmojir:>!;
        return $ruby;
    }
    elsif ($h->attr('class') eq 'symbol') {
        return sprintf "◆%s◆",$h->as_trimmed_text;
    }
    else {
        return fallback_to_html($h);
    }
};

case blockquote => sub {
    my ($c, $h) = @_;
    $c->in_quote_block(1);
    my $blockquote = '';
    for ($h->content_list) {
        $blockquote .= $c->parse_element($_);
    }
    $blockquote =~ s/(\s)//g;
    $c->in_quote_block(0);

    return <<EOF;
<ParaStyle:引用>
<ParaStyle:引用>$blockquote
EOF
};

case div => sub {
    my ($c,  $h) = @_;

    if ($h->attr('class') eq 'column') {
        $c->in_column(1);

        # HTMLとして取得してcolumn自信のdivタグを削除
        my $html = $h->as_HTML('');
        $html =~ s/^<div.+?>//;
        $html =~ s/<\/div>$//;

        my $column = $c->parse($html);
        $c->in_column(0);
        return sprintf "<ParaStyle:コラム本文>\n%s", $column;
    } else {
        return fallback_to_html($h);
    }
};

case ul => sub {
    my ($c, $h) = @_;
    if ($c->in_list) {
        ## FIXME: 仕様確認中
        my $ret = "\n";
        for ($h->content_list) {
            if ($_->tag eq 'li') {
                $ret .= sprintf "＊・%s\n", $c->parse_element($_);
            }
        }
        chomp $ret;
        return $ret;
    } else {
        my $ret;
        for my $list ($h->content_list) {
            $c->in_list(1);
            $ret .= '<ParaStyle:箇条書き>・' . $c->parse_element($list) . "\n";
            $c->in_list(0);
        }
        return $ret;
    }
};

case ol => sub {
    my ($c, $h) = @_;
    my $out = '';
    my $style = $h->attr('class') || $c->default_list;
    my $i = 0;
    for my $list ($h->find('li')) {
        $out .= sprintf(
            "<ParaStyle:箇条書き>%s%s\n",
            _to_list_style($style, ++$i),
            $c->parse_element($list)
        );
    }
    return $out;
};

sub _to_list_style {
    my ($style, $i) = @_;

    if ($style eq 'disc') {
        my $code = 0x2776 - 1;
        return sprintf "<CharStyle:丸文字><%x><CharStyle:>", $code + $i;
    }

    if ($style eq 'circle') {
        my $code = 0x2460 - 1;
        return sprintf "<CharStyle:丸文字><%x><CharStyle:>", $code + $i;
    }

    if ($style eq 'square') {
        return sprintf "<cTypeface:B><cFont:A-OTF ゴシックMB101 Pro><cotfcalt:0><cotfl:nalt,7>%d<cTypeface:><cFont:><cotfcalt:><cotfl:>", $i;
    }

    if ($style eq 'alpha') {
        return sprintf "<CharStyle:丸文字><cLigatures:0><cOTFContAlt:0><cOTFeatureList:nalt,3>%s<cLigatures:><cOTFContAlt:><cOTFeatureList:><CharStyle:>", chr($i + 96);
    }
}

1;