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
use File::Path qw/make_path/;
use File::Basename qw/dirname basename/;
use File::Spec;
use IO::File;
use Moo;
use MooX::Cmd;
use MooX::Options;
use Log::Any qw/$log/;
use POSIX qw/EXIT_FAILURE/;

my $prefix = 'classparser';
my $structheader = File::Spec->catfile('include', 'classfile', 'struct.h');
my $parserheader = File::Spec->catfile('include', 'classfile', 'internal', 'parser.h');
my $parsersource = File::Spec->catfile('src', 'internal', 'parser.c');

option 'prefix' => (
    is => 'ro',
    format => 's',
    default => $prefix,
    doc => "global prefix, default is: $prefix"
);

option 'from' => (
    is => 'ro',
    format => 's',
    required => 1,
    doc => 'description of a structure. Required.'
);

option 'structheader' => (
    is => 'ro',
    format => 's',
    default => $structheader,
    required => 1,
    doc => "destination header file hosting structures, default is: $structheader"
);

option 'parserheader' => (
    is => 'ro',
    format => 's',
    default => $parserheader,
    required => 1,
    doc => "destination header file hosting internal parser, default is: $parserheader"
);

option 'parsersource' => (
    is => 'ro',
    format => 's',
    default => $parsersource,
    required => 1,
    doc => "destination source file hosting internal parser, default is: $parsersource"
);

sub execute {
    my ($self, $args, $chain) = @_;

    my ($structs, $unions) = $self->_parse_from;
    $self->_generate_structheader($structs, $unions);
    $self->_generate_parserheader($structs, $unions);
    $self->_generate_parsersource($structs, $unions);
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

    my %structs = ();
    my %unions = ();
    my $currentName;
    my $currentStructOrUnion;
    foreach my $line (grep { length } map { s/^\s*//; s/\s*$//; s/^#.*//; s/\s+/ /g; $_ } grep { defined && length } split(/\R/, $data)) {
        $self->_tracef('%s', $line);
        if ($line eq '}') {
	    next;
	} elsif ($line =~ /^struct\s+(\w+)\s*\{/) {
	    $currentName = $1;
	    $currentStructOrUnion = \%structs;
	    $self->_infof('%s: structure <%s>', $line, $currentName);
	    $currentStructOrUnion->{$currentName} = [];
	    next;
	} elsif ($line =~ /^union\s+(\w+)\s*\{/) {
	    $currentName = $1;
	    $currentStructOrUnion = \%unions;
	    $self->_infof('%s: union <%s>', $line, $currentName);
	    $currentStructOrUnion->{$currentName} = [];
	    next;
        } else {
            my ($type, $identifier, $size);
            if ($line =~ /^(\w+)\s+(\w+);$/) {
                ($type, $identifier, $size) = ($1, $2, 0);
            }
            elsif ($line =~ /^(\w+)\s+(\w+)\s*\[([^\)]+)\]\s*;$/) {
                ($type, $identifier, $size) = ($1, $2, $3);
                while ($size =~ m/(\b\w+\b)/smg) {
                    my $component = $1;
                    if ($component =~ /^\d+$/) {
                        $self->_tracef('%s: size component %s is ok (digits)', $line, $component);
                    } else {
                        if (! grep { $_ eq $component } map { $_->{identifier} } @{$currentStructOrUnion->{$currentName}} ) {
                            $self->_fatalf('%s: unknown member in size specification: %s', $line, $component);
                        } else {
                            $self->_tracef('%s: size component %s is ok (known member)', $line, $component);
                        }
                    }
                }
            } else {
                $self->_fatalf('%s: unparsed member', $line);
            }
            $self->_infof('%s: struct %s: type <%s> identifier <%s> size <%s>', $line, $currentName, $type, $identifier, $size);
            push(@{$currentStructOrUnion->{$currentName}}, { type => $type, identifier => $identifier, size => $size });
        }
    }
    $self->_tracef("Parsed structures:\n%s", Dumper(\%structs));
    $self->_tracef("Parsed unions:\n%s", Dumper(\%unions));

    return (\%structs, \%unions);
}

sub _generate_structheader {
    my ($self, $structs, $unions) = @_;

    make_path(dirname($self->structheader));

    $log->infof('Generating %s', $self->structheader);
    my $fh = IO::File->new($self->structheader, '>') || die $self->structheader . " open failure: $!";
    my $PREFIX = uc($self->prefix);

    print $fh "#ifndef ${PREFIX}_STRUCT_H\n";
    print $fh "#define ${PREFIX}_STRUCT_H\n";
    print $fh "\n";
    printf $fh "typedef unsigned char  %s_u1_t;  /* Can host at least 0x00-0xFF */\n", $self->prefix;
    printf $fh "typedef unsigned short %s_u2_t;  /* Can host at least 0x00-0xFFFF */\n", $self->prefix;
    printf $fh "typedef unsigned long  %s_u4_t;  /* Can host at least 0x00-0xFFFFFFFF */\n", $self->prefix;
    print $fh "\n";
    $self->_generate_typedef_by_type($fh, 'struct', $structs);
    $self->_generate_typedef_by_type($fh, 'union', $unions);
    print $fh "\n";
    $self->_generate_typecontent_by_type($fh, 'struct', $structs);
    $self->_generate_typecontent_by_type($fh, 'union', $unions);
    print $fh "\n";
    print $fh "#endif /* ${PREFIX}_STRUCT_H */\n";
    $fh->close || warn $self->structheader . " close failure: $!";
}

sub _generate_parserheader {
    my ($self, $structs, $unions) = @_;

    make_path(dirname($self->parserheader));

    $log->infof('Generating %s', $self->parserheader);
    my $fh = IO::File->new($self->parserheader, '>') || die $self->parserheader . " open failure: $!";
    my $PREFIX = uc($self->prefix);

    print $fh "#ifndef ${PREFIX}_PARSER_H\n";
    print $fh "#define ${PREFIX}_PARSER_H\n";
    #
    # We need to remove eventual "include" part of the structheader
    #
    my @dirs = File::Spec->splitdir(dirname($self->structheader));
    splice(@dirs, 0, 1) if @dirs && (lc($dirs[0]) eq 'include');
    print $fh "\n";
    printf $fh "#include <%s>\n", 'stddef.h';
    printf $fh "#include <%s>\n", File::Spec::Unix->catfile(@dirs, basename($self->structheader));
    print $fh "\n";
    $self->_generate_parsedecl_by_type($fh, 'struct', $structs);
    $self->_generate_parsedecl_by_type($fh, 'union', $unions);
    print $fh "\n";
    print $fh "#endif /* ${PREFIX}_PARSER_H */\n";
    $fh->close || warn $self->parserheader . " close failure: $!";
}

sub _generate_parsersource {
    my ($self, $structs, $unions) = @_;

    make_path(dirname($self->parsersource));

    $log->infof('Generating %s', $self->parsersource);
    my $fh = IO::File->new($self->parsersource, '>') || die $self->parsersource . " open failure: $!";
    my $PREFIX = uc($self->prefix);

    #
    # We need to remove eventual "include" part of the parserheader
    #
    my @dirs = File::Spec->splitdir(dirname($self->parserheader));
    splice(@dirs, 0, 1) if @dirs && (lc($dirs[0]) eq 'include');
    print $fh "\n";
    printf $fh "#include <%s>\n", 'stdlib.h';
    printf $fh "#include <%s>\n", 'errno.h';
    printf $fh "#include <%s>\n", File::Spec::Unix->catfile(@dirs, basename($self->parserheader));
    print $fh "\n";
    $self->_generate_parsedefs_by_type($fh, 'struct', $structs);
    $self->_generate_parsedefs_by_type($fh, 'union', $unions);
    print $fh "\n";
    $fh->close || warn $self->parsersource . " close failure: $!";
}

sub _generate_typedef_by_type {
    my ($self, $fh, $type, $hash) = @_;

    foreach (sort keys %{$hash}) {
	my $name = $self->prefix . "_$_";
	print $fh "typedef $type $name ${name}_t;\n";
    }
}

sub _generate_typecontent_by_type {
    my ($self, $fh, $type, $hash) = @_;

    foreach (sort keys %{$hash}) {
	my $name = $self->prefix . "_$_";
	print $fh "$type $name {\n";
	foreach (@{$hash->{$_}}) {
	    my $pointers = $_->{size} ? '**' : '';
	    printf $fh "\t%s_t %s%s;\n", $self->prefix . '_' . $_->{type}, $pointers, $_->{identifier};
	}
	print $fh "};\n";
    }
}

sub _generate_parsedecl_by_type {
    my ($self, $fh, $type, $hash) = @_;

    foreach (sort keys %{$hash}) {
	my $name = $self->prefix . "_$_";
	my $typedef = "${name}_t";
	print $fh "extern short ${name}_parseb($typedef **${name}pp, const char *inputp, size_t lengthl, char **inputpp, size_t *lengthlp);\n";
	print $fh "extern void ${name}_freev($typedef *${name}p);\n";
    }
}

sub _generate_parsedefs_by_type {
    my ($self, $fh, $type, $hash) = @_;

    foreach (sort keys %{$hash}) {
	my $name = $self->prefix . "_$_";
	my $typedef = "${name}_t";
	print $fh "/* *********************************************************\n";
	print $fh "   ${name}_parseb\n";
	print $fh "   *********************************************************/\n";
	print $fh "short ${name}_parseb($typedef **outputpp, const char *inputp, size_t lengthl, char **inputpp, size_t *lengthlp) {\n";
	print $fh "  $typedef *${name}p;\n";
	print $fh "\n";
	print $fh "  /* Check arguments */\n";
	print $fh "  if ((outputpp == NULL) || (inputp == NULL) || (lengthl == 0)) {\n";
	print $fh "    errno = EINVAL;\n";
	print $fh "    goto err;\n";
	print $fh "  }\n";
	print $fh "\n";
	print $fh "  /* Allocation */\n";
	print $fh "  ${name}p = malloc(sizeof($typedef))\n";
	print $fh "  if (${name}p == NULL) {\n";
	print $fh "    goto err;\n";
	print $fh "  }\n";
	print $fh "\n";
	print $fh "  /* Initialization of pointers if any */\n";
	foreach my $subhash (@{$hash->{$_}}) {
	    my $subname = $self->prefix . '_' . $subhash->{type};
	    if (! grep { $subhash->{type} eq $_ } qw/u1 u2 u4/) {
		print $fh "  ${name}p->$subhash->{identifier} = NULL;\n";
	    }
	}
	print $fh "\n";
	print $fh "  /* Parse */\n";
	foreach my $subhash (@{$hash->{$_}}) {
	    my $subname = $self->prefix . '_' . $subhash->{type};
	    if ($subhash->{size}) {
		print $fh "  {\n";
		print $fh "    size_t sizel = ${name}p->$subhash->{size};\n";
		print $fh "\n";
		print $fh "    /* Allocation */\n";
		print $fh "    if (sizel > 0) {\n";
		print $fh "      size_t i;\n";
		print $fh "      ${subname}_t **p;\n";
		print $fh "\n";
		print $fh "      ${name}p->$subhash->{identifier} = (${subname}_t **) malloc(sizel * sizeof(${subname}_t *));\n";
		print $fh "      if (${name}p->$subhash->{identifier} == NULL) {\n";
		print $fh "        goto err;\n";
		print $fh "      }\n";
		print $fh "      p = ${name}p->$subhash->{identifier};\n";
		print $fh "      for (i = 0; i < sizel; i++) {\n";
		print $fh "        *p++ = NULL;\n";
		print $fh "      }\n";
		print $fh "\n";
		print $fh "      p = ${name}p->$subhash->{identifier};\n";
		print $fh "      for (i = 0; i < sizel; i++) {\n";
		print $fh "        if (! ${subname}_parseb(*p, inputp, lengthl, &inputp, &lengthl)) goto err;\n";
		print $fh "      }\n";
		print $fh "    }\n";
		print $fh "  }\n";
	    } else {
		print $fh "  if (! ${subname}_parseb(&(${name}p->$subhash->{identifier}), inputp, lengthl, &inputp, &lengthl)) goto err;\n";
	    }
	}
	print $fh "\n";
	print $fh "  *outputpp = ${name}p;\n";
	print $fh "  *inputpp = inputp;\n";
	print $fh "  *lengthlp = lengthl;\n";
	print $fh "  return 1;\n";
	print $fh "\n";
	print $fh "  err:\n";
	print $fh "  ${name}_free($typedef *${name}p);\n";
	print $fh "  return 0;\n";
	print $fh "}\n";
	print $fh "\n";
	print $fh "/* *********************************************************\n";
	print $fh "   ${name}_freev\n";
	print $fh "   *********************************************************/\n";
	print $fh "void ${name}_freev($typedef *${name}p) {\n";
	print $fh "  if (${name}p != NULL) {\n";
	foreach my $subhash (@{$hash->{$_}}) {
	    my $subname = $self->prefix . '_' . $subhash->{type};
	    my $subfree = $self->prefix . '_' . $subhash->{type} . '_freev';
	    if (! grep { $subhash->{type} eq $_ } qw/u1 u2 u4/) {
		if ($subhash->{size}) {
		    print $fh "    {\n";
		    print $fh "      size_t sizel = ${name}p->$subhash->{size};\n";
		    print $fh "\n";
		    print $fh "      if (sizel > 0) {\n";
		    print $fh "        size_t i;\n";
		    print $fh "        ${subname}_t **p = ${name}p->$subhash->{identifier};\n";
		    print $fh "\n";
		    print $fh "        for (i = 0; i < sizel; i++) {\n";
		    print $fh "          $subfree(*p++);\n";
		    print $fh "        }\n";
		    print $fh "      }\n";
		    print $fh "    }\n";
		} else {
		    print $fh "    $subfree(${name}p->$subhash->{identifier});\n";
		}
	    }
	}
	print $fh "    free(${name}p);\n";
	print $fh "  }\n";
	print $fh "}\n";
    }
}

package main;
use POSIX qw/EXIT_SUCCESS/;

MyGenerator->new_with_cmd();

exit(EXIT_SUCCESS);
