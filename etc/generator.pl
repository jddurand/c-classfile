#!env perl
use strict;
use warnings FATAL => 'all';
use Log::Log4perl qw/:easy/;
use Log::Any::Adapter;
#
# Init log
#
our $defaultLog4perlConf = '
log4perl.rootLogger              = TRACE, Screen
log4perl.appender.Screen         = Log::Log4perl::Appender::Screen
log4perl.appender.Screen.stderr  = 0
log4perl.appender.Screen.layout  = PatternLayout
log4perl.appender.Screen.layout.ConversionPattern = %d %-5p %6P %m{chomp}%n
';
Log::Log4perl::init(\$defaultLog4perlConf);
Log::Any::Adapter->set('Log4perl');

package MyGenerator;
use Carp qw/croak/;
use Clone qw/clone/; # or Storable qw/dclone/
use Data::Dumper;
use Moo;
use MooX::Cmd;
use MooX::Options;
use Log::Any qw/$log/;
use POSIX qw/EXIT_FAILURE/;

my $PREFIX = 'classfile_';

option 'prefix' => (
    is => 'ro',
    format => 's',
    default => $PREFIX,
    doc => "global prefix, default is: $PREFIX"
);

option 'from' => (
    is => 'ro',
    format => 's',
    required => 1,
    doc => 'description of a structure. Required.'
);

sub execute {
    my ($self, $args, $chain) = @_;

    $self->_parse_from;
}

sub _fatalf {
    my ($self, $fmts, @args) = @_;
    $log->fatalf($fmts, @args);
    exit(EXIT_FAILURE);
}

sub _warnf {
    my ($self, $fmts, @args) = @_;
    $log->warnf($fmts, @args);
}

sub _tracef {
    my ($self, $fmts, @args) = @_;
    $log->tracef($fmts, @args);
}

sub _debugf {
    my ($self, $fmts, @args) = @_;
    $log->debugf($fmts, @args);
}

sub _infof {
    my ($self, $fmts, @args) = @_;
    $log->infof($fmts, @args);
}

sub _parse_from {
    my ($self) = @_;

    $self->_debugf('Reading %s', $self->from);
    open(my $fh, '<', $self->from) || $self->_fatalf("Cannot open %s, %s", $self->from, $!);
    my $data = do { local $/; <$fh> };
    close($fh) || $self->_warnf('Cannot close %s, %s', $self->from, $!);

    my @structs = ();
    my %defaultstruct = (
        def     => {_identifier => undef, _input => '$input', _length => '$length' },
        members => []
        );
    my %struct = ();
    foreach my $line (grep { length } map { s/^\s*//; s/\s*$//; s/^#.*//; s/\s+/ /g; $_ } grep { defined && length } split(/\R/, $data)) {
        $self->_tracef('%s', $line);
        if ($line eq '}') {
            #
            # Global struct verification.
            #
            # If a structure has an assignment other than "input" or "length", then it must be a known member name.
            #
            foreach my $_identifier (grep { ($_ ne '_identifier') && ($_ ne '_input') && ($_ ne '_length') } keys %{$struct{def}}) {
                $self->_fatalf('Structure entry point has assignment to an unknown member: %s', $_identifier) unless grep { $_identifier eq $_ } map { $_->{_identifier} } @{$struct{members}};
                
            }
            push(@structs, \%{clone(\%struct)});
            %struct = ();
            next;
        }
        if (! %struct) {
            %struct = %{clone(\%defaultstruct)};
            #
            # First parsable line must be in the form
            # "structName {" or
            # "structName(x1 => y1, x2 => y2, etc...) {"
            #
            if ($line =~ /^(\w+)\s*\{/) { # No explicit input
                $self->_infof('%s: _identifier <%s>', $line, $1);
                $struct{def}{_identifier} = $1;
                next;
            } elsif ($line =~ /^(\w+)\s*\(([^\)]*)\)\s*\{/) { # Explicit input
                $self->_infof('%s: _identifier <%s>', $line, $1);
                $struct{def}{_identifier} = $1;
                foreach my $assign (split(/,/, $2)) {
                    if ($assign =~ /^\s*(\w+)\s*=>\s*(\$\w+)\s*$/) {
                        my ($_identifier, $value) = ($1, $2);
                        #
                        # "identifier" is a reserved keyword during assignment
                        #
                        $self->_fatalf('%s: Assignment %s => %s is using reserved keyword "%s"', $line, $_identifier, $value, $_identifier)
                            if $_identifier eq '_identifier';
                        $self->_infof('%s: %s <%s>', $line, $_identifier, $1);
                        $struct{def}{$_identifier} = $value;
                    } else {
                        $self->_fatalf('%s: Assignment must be in the form word => $word', $line);
                    }
                }
                next;
            } else {
                $self->_fatalf('First line does not describe a structure: %s', $line);
            }
        } else {
            #
            # A member must be in the form
            # "type memberIdentifier" or
            # "type $memberIdentifier" or
            # "type memberIdentifier[something]" where something contains a math expression with only digits or a known previous memberIdentifier
            #
            my %member;
            my ($_type, $_identifier, $_size);
            if ($line =~ /^(\w+)\s+(\w+);$/) {
                ($_type, $_identifier, $_size) = ($1, $2, 0);
            }
            elsif ($line =~ /^(\w+)\s+(\w+)\s*\[([^\)]+)\]\s*;$/) {
                ($_type, $_identifier, $_size) = ($1, $2, $3);
                while ($_size =~ m/(\b\w+\b)/smg) {
                    my $component = $1;
                    if ($component =~ /^\d+$/) {
                        $self->_tracef('%s: size component %s is ok (digits)', $line, $component);
                    } else {
                        if (! grep { $_ eq $component } map { $_->{_identifier} } @{$struct{members}} ) {
                            $self->_fatalf('%s: unknown member in size specification: %s', $line, $component);
                        } else {
                            $self->_tracef('%s: size component %s is ok (known member)', $line, $component);
                        }
                    }
                }
            } else {
                $self->_fatalf('%s: unparsed member', $line);
            }
            %member = ( _type => $_type, _identifier => $_identifier, _size => $_size );
            $self->_infof('%s: _type <%s> _identifier <%s> _size <%s>', $line, $_type, $_identifier, $_size);
            # It is illegal to have a member named "input" or "length"
            next unless %member;
            foreach (qw/_input _length/) {
                $self->_fatalf('%s: member identifier %s is not allowed', $line, $member{_identifier}) if ($member{_identifier} eq $_);
            }
            push(@{$struct{members}}, \%member);
        }
    }
    $self->_fatalf('Unfinished structure definition') if %struct;
    $self->_tracef("Parsing result is:\n%s", Dumper(\@structs));
}

package main;
use POSIX qw/EXIT_SUCCESS/;

MyGenerator->new_with_cmd();

exit(EXIT_SUCCESS);
