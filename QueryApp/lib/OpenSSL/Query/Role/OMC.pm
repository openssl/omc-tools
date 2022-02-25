#! /usr/bin/env perl
#
# Copyright 2017 The OpenSSL Project Authors. All Rights Reserved.
#
# Licensed under the OpenSSL license (the "License").  You may not use
# this file except in compliance with the License.  You can obtain a copy
# in the file LICENSE in the source distribution or at
# https://www.openssl.org/source/license.html

use strict;
use warnings;

package OpenSSL::Query::Role::OMC;

use Carp;
use File::Spec::Functions;
use Moo::Role;

has data => ( is => 'ro' );
has omc => ( is => 'ro' );	# Backward compat, data takes precedense
has bureau => ( is => 'ro' );	# Backward compat, data or omc take precedense

sub _find_file {
  my $self = shift;
  my $filename = shift;
  my $envvar = shift;

  my $data =
      $ENV{DATA} // $self->data
      // $ENV{OMC} // $self->omc
      // $ENV{BUREAU} // $self->bureau;
  my @paths = ( $ENV{$envvar} // (),
		$data ? catfile($data, $filename) : (),
		catfile('.', $filename) );
  foreach (@paths) {
    return $_ if -r $_;
  }
  croak "$filename not found in any of ", join(", ", @paths), "\n";
}

1;
