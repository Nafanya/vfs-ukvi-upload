#!/usr/bin/env perl
# Renames every .jpg/.jpeg under a folder (recursively) so it's safe for the
# VFS Global upload form: English letters/digits only, no special characters,
# at most one dot (the extension), max 100 characters. Cyrillic is
# transliterated to Latin; anything else gets replaced with "_" or "-".
# "-N-of-M" suffixes (from pdf2img.sh) are preserved and trimming happens
# on the prefix, not the suffix.
#
# Usage: ./rename_jpgs.pl [--dry-run] [root-folder]   (default: ~/Desktop/olga)
#
# Requires: perl (core modules only, no extra deps).

use strict;
use warnings;
use File::Find;
use File::Basename;

my $ROOT = "$ENV{HOME}/Desktop/olga";
my $DRYRUN = 0;
for my $a (@ARGV) {
    if ($a eq '--dry-run') { $DRYRUN = 1; }
    else { $ROOT = $a; }
}

# UTF-8 byte sequences (2-byte, Cyrillic block) => latin transliteration.
# Source file is saved as UTF-8 and this script does NOT `use utf8`,
# so these literals are the raw UTF-8 bytes of each Cyrillic letter,
# matching filesystem bytes exactly.
my %map = (
    'а'=>'a','б'=>'b','в'=>'v','г'=>'g','д'=>'d','е'=>'e','ё'=>'e','ж'=>'zh','з'=>'z','и'=>'i',
    'й'=>'y','к'=>'k','л'=>'l','м'=>'m','н'=>'n','о'=>'o','п'=>'p','р'=>'r','с'=>'s','т'=>'t',
    'у'=>'u','ф'=>'f','х'=>'h','ц'=>'c','ч'=>'ch','ш'=>'sh','щ'=>'sch','ъ'=>'','ы'=>'y','ь'=>'',
    'э'=>'e','ю'=>'yu','я'=>'ya',
    'А'=>'A','Б'=>'B','В'=>'V','Г'=>'G','Д'=>'D','Е'=>'E','Ё'=>'E','Ж'=>'Zh','З'=>'Z','И'=>'I',
    'Й'=>'Y','К'=>'K','Л'=>'L','М'=>'M','Н'=>'N','О'=>'O','П'=>'P','Р'=>'R','С'=>'S','Т'=>'T',
    'У'=>'U','Ф'=>'F','Х'=>'H','Ц'=>'C','Ч'=>'Ch','Ш'=>'Sh','Щ'=>'Sch','Ъ'=>'','Ы'=>'Y','Ь'=>'',
    'Э'=>'E','Ю'=>'Yu','Я'=>'Ya',
);

sub transliterate {
    my ($s) = @_;
    # drop combining diacritical marks (U+0300-036F) first, e.g. decomposed
    # "и" + combining breve (looks like "й") or "е" + combining diaeresis (looks like "ё")
    $s =~ s/[\xCC\xCD][\x80-\xBF]//g;
    $s =~ s/([\xD0-\xD3][\x80-\xBF])/exists $map{$1} ? $map{$1} : '_'/ge;
    return $s;
}

sub sanitize {
    my ($stem) = @_;
    $stem = transliterate($stem);
    # the only dot allowed in the final filename is the one before the
    # extension, which fileparse() already stripped off before we got here -
    # so any dot still inside $stem is an "extra" dot and must become a dash
    # (the site's validator rejects filenames with multiple dots).
    $stem =~ s/\./-/g;
    $stem =~ s/[^A-Za-z0-9_-]/_/g;
    $stem =~ s/_+/_/g;
    $stem =~ s/-+/-/g;
    $stem =~ s/^[_-]+//;
    $stem =~ s/[_-]+$//;
    return $stem;
}

sub fit_length {
    my ($stem, $max_stem) = @_;
    return $stem if length($stem) <= $max_stem;
    if ($stem =~ /^(.*?)(-\d+-of-\d+)$/) {
        my ($prefix, $suffix) = ($1, $2);
        my $max_prefix = $max_stem - length($suffix);
        $max_prefix = 1 if $max_prefix < 1;
        $prefix = substr($prefix, 0, $max_prefix);
        $prefix =~ s/[_-]+$//;
        return $prefix . $suffix;
    }
    my $t = substr($stem, 0, $max_stem);
    $t =~ s/[_-]+$//;
    return $t;
}

my @files;
find(sub {
    return unless -f $_;
    return unless /\.jpe?g$/i;
    push @files, $File::Find::name;
}, $ROOT);

my %used_in_dir;

for my $path (sort @files) {
    my ($base, $dir, $ext) = fileparse($path, qr/\.[^.]*/);
    $ext = lc($ext);
    $ext = '.jpg' if $ext eq '.jpeg';

    my $stem = sanitize($base);
    $stem = fit_length($stem, 100 - length($ext));
    $stem = 'file' if $stem eq '';

    my $newname = "$stem$ext";
    my $newpath = "$dir$newname";

    # collision avoidance within the same directory
    my $n = 2;
    while ((-e $newpath && $newpath ne $path) || ($used_in_dir{$newpath} && $newpath ne $path)) {
        my $suffix = "_$n";
        my $trimmed = fit_length($stem, 100 - length($ext) - length($suffix));
        $newname = "$trimmed$suffix$ext";
        $newpath = "$dir$newname";
        $n++;
    }
    $used_in_dir{$newpath} = 1;

    my $len = length($newname);
    if ($newpath eq $path) {
        printf("SAME:   %-90s (%d)\n", $newname, $len);
        next;
    }

    printf("%s %s\n  -> %s  (%d chars)\n", ($DRYRUN ? 'WOULD RENAME:' : 'RENAME:'), $path, $newname, $len);
    unless ($DRYRUN) {
        rename($path, $newpath) or warn "FAILED to rename $path: $!\n";
    }
}
