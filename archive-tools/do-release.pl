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
my $mail    = $ENV{"OPENSSL_MAIL"} // "mutt -s SUBJECT RECIP < BODY";
my %mailenv = (
    REPLYTO => $ENV{"OPENSSL_MAILFROM"} // 'openssl@openssl.org',
);

my @public_series = qw( 3.0 1.1.1 );
my @premium_series = qw( 1.0.2 );

#
# info takes the following arguments:
#
# - the series to be copied.
#
# It returns a HASH array with the following data:
#
# ftpdir => the path where the series should be stored
# olddir => the path to move older releases into, or undef to not do that
# annrecip => the list of recipients of the announcement email
#
sub info {
    my $serie = shift;
    my %info = (
        ftpdir => $ENV{"OPENSSL_FTP_DIR"},
        olddir => undef,
    );

    if ( grep { $serie eq $_ } @public_series ) {
        $info{ftpdir} //= "/srv/ftp/source";
        $info{olddir} = "$info{ftpdir}/old/$serie";
        $info{annrecip} = "openssl-project openssl-users openssl-announce";
    } elsif ( grep { $serie eq $_ } @premium_series ) {
        $info{ftpdir} //= "/srv/premium";
        $info{annrecip} = "premium-announce";
    }

    return %info;
}

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

my %versions;
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
        $versions{$+{FULL_VERSION}} = $+{SERIES};
    } else {
        die "Unexpected filename $_";
    }
}

die "No distribution in temp directory!" if ( scalar %versions == 0 );
print "OpenSSL versions to be released:\n";
foreach (sort keys %versions) {
    print "$_\n";
}
print "OK? (y/n)\n";
$_ = <STDIN>;
exit 1 unless /^y/i;

my %distinfo;

foreach (sort keys %versions) {
    $distinfo{$_} = { serie => $versions{$_},
                      files => [ "openssl-$_.tar.gz",
                                 "openssl-$_.tar.gz.sha1",
                                 "openssl-$_.tar.gz.sha256",
                                 "openssl-$_.tar.gz.asc" ] };
}

$do_copy = 0 if $mail_only;

my $bad = 0;
if ($do_copy) {
    foreach my $distinfo (sort keys %distinfo) {
        my %info = info($distinfo->{serie});
        foreach (@{$distinfo->{files}}) {
            if ( !-f "$tmpdir/$_" ) {
                print STDERR "File $_ not found in temp directory!\n";
                $bad = 1;
            }
            if ( !-d $info{ftpdir} ) {
                print STDERR "Can't find ftp directory $info{ftpdir}";
                $bad = 1;
            } elsif ( -e "$info{ftpdir}/$_" ) {
                print STDERR "File $_ already present in ftp directory!\n";
                $bad = 1;
            }
            if ( -e "$info{olddir}/$_" ) {
                print STDERR
                    "File $_ already present in old distributions directory!\n";
                $bad = 1;
            }
        }
    }
}

exit 1 if $bad;

print "Directory sanity check OK\n";

print "Starting release for OpenSSL ", join(' ', sort keys %versions), "\n";

if ($do_copy) {
    my @series = ();
    foreach my $distinfo (sort keys %distinfo) {
        push @series, $distinfo->{serie}
            unless grep { $_ eq $distinfo->{serie} } @series;
    }

    foreach my $serie (sort @series) {
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
        my %info = info($serie);
        my @tomove_ftp =
          map { basename ($_) }
          grep { -f $_ }
          map { glob("$info{ftpdir}/$_") }
          @glob_patterns;

        if ($info{olddir}) {
            mkdir $info{olddir}
                or die "Couldn't mkdir $info{olddir} : $!"
                if !-d $info{olddir};
            foreach (@tomove_ftp) {
                print "DEBUG: mv $info{ftpdir}/$_* $info{olddir}/\n" if $do_debug;
                system("mv $info{ftpdir}/$_* $info{olddir}/");
                die "Error moving $_* to old ftp directory!" if $?;
            }
            print
                "Moved existing $serie distributions files to $info{olddir}\n";
        }
    }

    foreach my $distinfo (sort keys %distinfo) {
        my %info = info($distinfo->{serie});
        foreach (@{$distinfo->{files}}) {
            print "DEBUG: cp $tmpdir/$_ $info{ftpdir}/$_\n" if $do_debug;
            system("cp $tmpdir/$_ $info{ftpdir}/$_");
            die "Error copying $_ to ftp directory!" if $?;
        }
        print "Copied new $distinfo->{serie} distributions files to $info{ftpdir}\n";
    }
} else {
    print "Test mode: no files copied\n";
}

foreach (sort keys %versions) {
    my %info = info($versions{$_});
    my $announce   = "openssl-$_.txt.asc";
    my $annversion = $_;
    $annversion =~ s/-pre(\d+$)/ pre release $1/;
    my $annmail = $mail;
    my $annrecip = join(' ', @{$info{annrecip}});
    $annmail =~ s/SUBJECT/"OpenSSL version $annversion published"/;
    $annmail =~ s/RECIP/$annrecip/;
    $annmail =~ s|BODY|$tmpdir/$announce|;

    if ($do_mail) {
        print "Sending announcement email for OpenSSL $_...\n";
        print "DEBUG: $annmail\n" if $do_debug;

        local %ENV = ( %ENV, %mailenv );
        system("$annmail");

        die "Error sending announcement email!" if $?;
        print "Don't forget to authorise the openssl-announce email.\n";
        push @{$distinfo{$_}->{files}}, $announce if $do_move;
    } else {
        local $annmail
            = join(' ',
                   ( map { "$_='$mailenv{$_}'" } sort keys %mailenv ),
                   $annmail);
        print "Announcement email not sent automatically\n";
        print "\nSend announcement mail manually with command:\n\n$annmail\n\n";
        print
"When done, move the announcement file away with command:\n\nmv $tmpdir/$announce $olddir/$announce\n\n"
          if $do_move;
    }
}

if ($do_move) {
    foreach my $distinfo (sort keys %distinfo) {
        foreach (@{$distinfo->{files}}) {
            print "DEBUG: rename( '$tmpdir/$_', '$olddir/$_' )\n" if $do_debug;
            rename( "$tmpdir/$_", "$olddir/$_" ) || die "Can't move $_: $!";
        }
    }
    print "Moved distribution files to old directory\n";
}

print "Successful!\n";

