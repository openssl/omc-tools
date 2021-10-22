#! /usr/bin/env perl
# Copyright 2010-2018 The OpenSSL Project Authors. All Rights Reserved.
#
# Licensed under the OpenSSL license (the "License").  You may not use
# this file except in compliance with the License.  You can obtain a copy
# in the file LICENSE in the source distribution or at
# https://www.openssl.org/source/license.html

use strict;
use warnings;

use File::Basename;

my $homedir = glob("~openssl");
my $tmpdir  = $ENV{"OPENSSL_TMP_DIR"} // $homedir . "/dist/new";
my $olddir  = $ENV{"OPENSSL_OLD_DIR"} // $homedir . "/dist/old";
my $ftpdir  = $ENV{"OPENSSL_FTP_DIR"} // "/srv/ftp/source";
my $mail    = $ENV{"OPENSSL_MAIL"} // "mutt -s SUBJECT RECIP < BODY";

my $do_mail   = 0;
my $do_copy   = 0;
my $do_move   = 0;
my $mail_only = 0;
my $do_debug = 0;

foreach (@ARGV) {
    if (/^--tmpdir=(.*)$/) {
        $tmpdir = $1;
    } elsif (/^--copy$/) {
        $do_copy = 1;
    }
    elsif (/^--move$/) {
        $do_move = 1;
    } elsif (/^--mail$/) {
        $do_mail = 1;
    } elsif (/^--mail-only$/) {
        $mail_only = 1;
        $do_mail   = 1;
    } elsif (/^--full-release$/) {
        $do_mail = 1;
        $do_copy = 1;
        $do_move = 1;
    } elsif (/^--debug$/) {
        $do_debug = 1;
    } else {
        print STDERR "Unknown command line argument $_";
        exit 1;
    }
}

if ( getpwuid($<) ne "openssl" && !exists $ENV{"OPENSSL_RELEASE_TEST"} ) {
    print "This script must be run as the \"openssl\" user\n";
    exit 1;
}

die "Can't find distribution directory $tmpdir"     unless -d $tmpdir;
die "Can't find old distribution directory $olddir" unless -d $olddir;
die "Can't find ftp directory $ftpdir"              unless -d $ftpdir;

my @versions;
my @series;
my @files = glob("$tmpdir/*.txt.asc");

# VERSION, FULL_VERSION and PRE_RELEASE correspond to these macros from
# opensslv.h in OpenSSL 3.0:
# OPENSSL_VERSION_STR, OPENSSL_FULL_VERSION_STR, OPENSSL_VERSION_PRE_RELEASE
my $tag_re_pre_30 = qr/-pre\d+/;
my $version_re_pre_30 = qr/
                              (?P<FULL_VERSION>
                                  (?P<VERSION>
                                      # We make sure this only applies
                                      # on pre-3.0 versions.
                                      (?P<SERIES>[01]\.\d+\.\d+)
                                      [a-z]*)
                                  (?P<PRE_RELEASE>${tag_re_pre_30})?)
                          /x;
my $tag_re_30 = qr/-(?:alpha|beta)\d+/;
my $version_re_30 = qr/
                          (?P<FULL_VERSION>
                              (?P<VERSION>
                                  (?P<SERIES>\d+\.\d+)
                                  \.\d+)
                              (?P<PRE_RELEASE>${tag_re_30})?)
                      /x;
my $version_re = qr/(?|${version_re_pre_30}|${version_re_30})/;
my $basefile_re = qr/openssl-${version_re}/;

foreach (@files) {
    if (m|^.*/${basefile_re}\Q.txt.asc\E$|) {
        my $serie = $+{SERIES};
        push @versions, $+{FULL_VERSION};
        push @series, $serie unless grep /^${serie}$/, @series;
    } else {
        die "Unexpected filename $_";
    }
}

die "No distribution in temp directory!" if ( scalar @versions == 0 );
print "OpenSSL versions to be released:\n";
foreach (@versions) {
    print "$_\n";
}
print "OK? (y/n)\n";
$_ = <STDIN>;
exit 1 unless /^y/i;

my @distfiles;
my @announce;

foreach (@versions) {
    push @distfiles, "openssl-$_.tar.gz";
    push @distfiles, "openssl-$_.tar.gz.sha1";
    push @distfiles, "openssl-$_.tar.gz.sha256";
    push @distfiles, "openssl-$_.tar.gz.asc";
    push @announce,  "openssl-$_.txt.asc";
}

$do_copy = 0 if $mail_only;

my $bad = 0;
if ($do_copy) {
    foreach (@distfiles) {
        if ( !-f "$tmpdir/$_" ) {
            print STDERR "File $_ not found in temp directory!\n";
            $bad = 1;
        }
        if ( -e "$ftpdir/$_" ) {
            print STDERR "File $_ already present in ftp directory!\n";
            $bad = 1;
        }
        if ( -e "$olddir/$_" ) {
            print STDERR
              "File $_ already present in old distributions directory!\n";
            $bad = 1;
        }
    }
}

exit 1 if $bad;

print "Directory sanity check OK\n";

print "Starting release for OpenSSL @versions\n";

if ($do_copy) {
    foreach my $serie (@series) {
        my @glob_patterns =
            $serie =~ m|^[01]\.|
            ? ( # pre-3.0 patterns
               "openssl-$serie.tar.gz",
               "openssl-$serie?.tar.gz",
               "openssl-$serie-pre[0-9].tar.gz",
               "openssl-$serie?-pre[0-9].tar.gz",
               "openssl-$serie-pre[0-9][0-9].tar.gz",
               "openssl-$serie?-pre[0-9][0-9].tar.gz",
              )
            : ( # 3.0 and on;
               "openssl-$serie.[0-9].tar.gz",
               "openssl-$serie.[0-9]-alpha[0-9].tar.gz",
               "openssl-$serie.[0-9]-beta[0-9].tar.gz",
               "openssl-$serie.[0-9][0-9].tar.gz",
               "openssl-$serie.[0-9][0-9]-alpha[0-9].tar.gz",
               "openssl-$serie.[0-9][0-9]-beta[0-9].tar.gz",
              );
        my $tomove_oldftp = "$ftpdir/old/$serie";
        my @tomove_ftp =
          map { basename ($_) }
          grep { -f $_ }
          map { glob("$ftpdir/$_") }
          @glob_patterns;

        mkdir $tomove_oldsrc
          or die "Couldn't mkdir $tomove_oldsrc : $!"
          if !-d $tomove_oldsrc;
        mkdir $tomove_oldftp
          or die "Couldn't mkdir $tomove_oldftp : $!"
          if !-d $tomove_oldftp;
        foreach (@tomove_ftp) {
            print "DEBUG: mv $ftpdir/$_* $tomove_oldftp/\n" if $do_debug;
            system("mv $ftpdir/$_* $tomove_oldftp/");
            die "Error moving $_* to old ftp directory!" if $?;
        }
        print
            "Moved $serie distributions files to source/old and ftp/old directories\n";
    }

    foreach (@distfiles) {
        print "DEBUG: cp $tmpdir/$_ $ftpdir/$_\n" if $do_debug;
        system("cp $tmpdir/$_ $ftpdir/$_");
        die "Error copying $_ to ftp directory!" if $?;
    }
    print "Copied distributions files to source and ftp directories\n";
}
else {
    print "Test mode: no files copied\n";
}

foreach (@versions) {
    my $announce   = "openssl-$_.txt.asc";
    my $annversion = $_;
    $annversion =~ s/-pre(\d+$)/ pre release $1/;
    my $annmail = $mail;
    $annmail =~ s/SUBJECT/"OpenSSL version $annversion published"/;
    $annmail =~ s/RECIP/openssl-project openssl-users openssl-announce/;
    $annmail =~ s|BODY|$tmpdir/$announce|;

    if ($do_mail) {
        print "Sending announcement email for OpenSSL $_...\n";
        print "DEBUG: $annmail\n" if $do_debug;
        system("$annmail");
        die "Error sending announcement email!" if $?;
        print "Don't forget to authorise the openssl-announce email.\n";
        push @distfiles, $announce if $do_move;
    } else {
        print "Announcement email not sent automatically\n";
        print "\nSend announcement mail manually with command:\n\n$annmail\n\n";
        print
"When done, move the announcement file away with command:\n\nmv $tmpdir/$announce $olddir/$announce\n\n"
          if $do_move;
    }
}

if ($do_move) {
    foreach (@distfiles) {
        print "DEBUG: rename( '$tmpdir/$_', '$olddir/$_' )\n" if $do_debug;
        rename( "$tmpdir/$_", "$olddir/$_" ) || die "Can't move $_: $!";
    }
    print "Moved distribution files to old directory\n";
}

print "Successful!\n";

