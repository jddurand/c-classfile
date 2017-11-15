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

sub _parse_from {
    my ($self) = @_;

    $self->_debugf('Reading %s', $self->from);
    open(my $fh, '<', $self->from) || $self->_fatalf("Cannot open %s, %s", $self->from, $!);
    my $data = do { local $/; <$fh> };
    close($fh) || $self->_debugf('Cannot close %s, %s', $self->from, $!);
    my %struct = (
        def     => {identifier => undef, input => 'inputs', length => 'lengthl' },
        members => []
        );
    foreach my $line (grep { length } map { s/^\s*//; s/\s*$//; s/^#.*//; s/\s+/ /g; $_ } grep { defined && length } split(/\R/, $data)) {
        $self->_debugf('%s', $line);
        last if ($line eq '}');
        if (! $struct{def}{identifier}) {
            #
            # First parsable line must be in the form
            # "structName {" or
            # "structName(x1 => y1, x2 => y2, etc...) {"
            #
            if ($line =~ /^(\w+)\s*\{/) { # No explicit input
                $struct{def}{identifier} = $1;
                next;
            } elsif ($line =~ /^(\w+)\s*\(([^\)]*)\)\s*\{/) { # Explicit input
                $struct{def}{identifier} = $1;
                foreach my $assign (split(/,/, $2)) {
                    if ($assign =~ /^\s*(\w+)\s*=>\s*(\w+)\s*$/) {
                        my ($identifier, $value) = ($1, $2);

                        $self->_debugf('%s: Got assignment %s => %s', $line, $identifier, $value);
                        #
                        # identifier "identifier" is a reserved keyword
                        #
                        $self->_fatalf('%s: Assignment %s => %s is using reserved keyword "%s": %s', $line, $identifier, $value, $identifier)
                            if $identifier eq 'identifier';
                        #
                        # known identifiers "input" and "length" should have values ending with "p" and "l", respectively
                        #
                        $self->_warnf('%s: Assignment %s => %s should have a value ending with "p": %s', $line, $identifier, $value)
                            if ($identifier eq 'input') && (! ($value =~ /p$/));
                        $self->_warnf('%s: Assignment "%s => %s" should have a value ending with "l": %s', $line, $identifier, $value)
                            if ($identifier eq 'length') && (! ($value =~ /p$/));
                        $struct{def}{$identifier} = $value;
                    } else {
                        $self->_fatalf('%s: Assignment must be in the form word => word', $line);
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
            # "type memberIdentifier[something]" where something contains a math expression with only digits or a known previous memberIdentifier
            #
            my %member;
            if ($line =~ /^(\w+)\s+(\w+);$/) {
                %member = ( type => $1, identifier => $2, size => 0 );
                $self->_debugf('%s: type %s identifier %s', $line, $1, $2);
            }
            elsif ($line =~ /^(\w+)\s+(\w+)\s*\[([^\)]+)\]\s*;$/) {
                %member = ( type => $1, identifier => $2, size => $3 );
                $self->_debugf('%s: type %s identifier %s size %s', $line, $1, $2, $3);
            } else {
                $self->_fatalf('%s: unparsed member');
            }
            # It is illegal to have a member named "input" or "length"
            next unless %member;
            foreach (qw/input length/) {
                $self->_fatalf('%s: member identifier %s is not allowed', $line, $member{identifier}) if ($member{identifier} eq $_);
            }
            push(@{$struct{members}}, \%member);
        }
    }
    #
    # Global verification.
    #
    # If a structure has an assignment other than "input" or "length", then it must be a known member name.
    #
    foreach my $identifier (grep { ($_ ne 'identifier') && ($_ ne 'input') && ($_ ne 'length') } keys %{$struct{def}}) {
        $self->_fatalf('Structure entry point has assignment to an unknown member: %s', $identifier) unless grep { $identifier eq $_ } map { $_->{identifier} } @{$struct{members}};
        
    }
    $self->_tracef('Parsing result is: %s', \%struct);
}

package main;
use POSIX qw/EXIT_SUCCESS/;

MyGenerator->new_with_cmd();

exit(EXIT_SUCCESS);
