#!env perl
use strict;
use warnings FATAL => 'all';

package MyGenerator;
use Moo;
use MooX::Cmd;
use MooX::Options;

option 'show_this_file' => (
    is => 'ro',
    format => 's',
      required => 1,
      doc => 'the file to display'
  );

sub execute {
    my ($self, $args, $chain) = @_;
    printf("%s.execute(\$self,[%s],[%s])\n",
           ref($self),                       # which command is executing?
           join(", ", @$args ),              # what where the arguments?
           join(", ", map { ref } @$chain)   # what's in the command chain?
        );
}

package main;
use POSIX qw/EXIT_SUCCESS/;

MyGenerator->new_with_cmd();

exit(EXIT_SUCCESS);
